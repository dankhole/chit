import AppKit
import Combine
import Foundation
import TodoCore

@MainActor
final class AppModel: ObservableObject {
    enum EditField: String, Codable, Sendable { case title, notes, subtaskTitle }

    struct EditConflict: Identifiable, Equatable {
        let id: String
        let itemID: String
        let field: EditField
        let localValue: String
        let remoteValue: String
    }

    struct OrphanedDraft: Identifiable, Equatable {
        let id: String
        let title: String
        let notes: String
    }

    struct CatalogRecoveryNotice {
        let preservedCatalogURL: URL?
    }

    /// A single stable-ID collection lets a native editor move between active and
    /// completed rows without becoming a different SwiftUI child.
    enum TaskListEntry: Identifiable, Equatable {
        case task(TaskItem)
        case addTask(projectID: String)
        case completedHeader(projectID: String, count: Int)

        var id: String {
            switch self {
            case .task(let task): return task.id
            case .addTask(let projectID): return "add:" + projectID
            case .completedHeader(let projectID, _): return "completed:" + projectID
            }
        }
    }

    enum ProjectDropTarget: Equatable {
        case before(String)
        case after(String)
        case group(String?)
    }

    enum TaskDropTarget: Equatable {
        case before(String)
        case after(String)
    }

    private struct Draft: Codable {
        let itemID: String
        let field: EditField
        var projectID: String?
        var base: String
        var value: String
        var key: String { AppModel.draftKey(itemID, field, projectID: projectID) }
        var recoveryID: String { AppModel.itemKey(itemID, projectID: projectID) }
    }

    let store: TodoStore
    /// Private drag scope for this workspace instance; never carries task content.
    let projectDragScope = UUID().uuidString
    let taskDragScope = UUID().uuidString
    let undoManager = UndoManager()
    @Published private(set) var workspace = Workspace()
    @Published var selectedProjectID = "" { didSet { persistPreferences() } }
    @Published var collapsedGroupIDs: Set<String> = [] { didSet { persistPreferences() } }
    @Published var expandedTaskIDs: [String: String] = [:] { didSet { persistPreferences() } }
    @Published private(set) var selectedTaskIDs: [String: String] = [:]
    @Published private(set) var expandedCompletedProjectIDs: Set<String> = [] { didSet { persistPreferences() } }
    @Published var entryDrafts: [String: String] = [:] { didSet { persistPreferences() } }
    @Published var errorMessage: String?
    @Published var listIdentityConflict: ListIdentityConflict?
    @Published private(set) var listLocations: [String: ListLocation] = [:]
    @Published private(set) var listIssues: [String: ListIssue] = [:]
    @Published private(set) var isStoreAvailable = false
    @Published private(set) var isCatalogRecoveryPresented = false
    @Published private(set) var catalogRecoveryPlan: CatalogRecoveryPlan?
    @Published private(set) var catalogRecoverySelectedURLs: Set<URL> = []
    @Published private(set) var catalogRecoveryErrorMessage: String?
    @Published private(set) var catalogRecoveryNotice: CatalogRecoveryNotice?
    @Published private(set) var backgroundOpacity = 0.80
    @Published private var drafts: [String: Draft] = [:]
    @Published private var editConflicts: [String: EditConflict] = [:]
    @Published private var overdueTaskIDs: [String: Set<String>] = [:]

    private let preferences: UserDefaults
    private let preferenceKey: String
    private var restoringPreferences = true
    private var autosave: Task<Void, Never>?
    private var watchers: [String: StorePathWatcher] = [:]
    private var observationRefresh: Task<Void, Never>?
    private var deadlineClock: Task<Void, Never>?
    private var deadlineSubscriptions: [AnyCancellable] = []
    private var additionalCatalogRecoveryURLs: Set<URL> = []
    private let watchChanges: Bool
    private static let backgroundOpacityKey = "appearance.backgroundOpacity"
    private static let completedCompositionMessage = "Finish the current text composition before hiding completed tasks."
    private static let removeCompositionMessage = "Finish the current text composition before hiding this list."

    init(store: TodoStore = TodoStore(), preferences: UserDefaults = .standard, watchChanges: Bool = true) {
        self.store = store
        self.preferences = preferences
        self.watchChanges = watchChanges
        // Preserve the path-based key through the brand rename so navigation and drafts survive.
        preferenceKey = "workspace." + Data(store.url.standardizedFileURL.path.utf8).base64EncodedString()
        if let opacity = preferences.object(forKey: Self.backgroundOpacityKey) as? NSNumber,
           opacity.doubleValue.isFinite {
            backgroundOpacity = min(1, max(0.30, opacity.doubleValue))
        }
        let saved = preferences.dictionary(forKey: preferenceKey) ?? [:]
        selectedProjectID = saved["selectedProjectID"] as? String ?? ""
        collapsedGroupIDs = Set(saved["collapsedGroupIDs"] as? [String] ?? [])
        expandedTaskIDs = saved["expandedTaskIDs"] as? [String: String] ?? [:]
        expandedCompletedProjectIDs = Set(saved["expandedCompletedProjectIDs"] as? [String] ?? [])
        entryDrafts = saved["entryDrafts"] as? [String: String] ?? [:]
        if let data = saved["drafts"] as? Data,
           let restored = try? JSONDecoder().decode([Draft].self, from: data) {
            drafts = Dictionary(restored.map { ($0.key, $0) }, uniquingKeysWith: { _, latest in latest })
        }
        undoManager.levelsOfUndo = 100
        // Store mutations are complete user actions. Group them explicitly so
        // flushing an edit and then moving a task remain separate undo steps.
        undoManager.groupsByEvent = false
        restoringPreferences = false
        refresh()
        startDeadlineObservationIfNeeded()
        if !drafts.isEmpty { scheduleAutosave() }
    }

    var selectedProject: Project? { workspace.projects.first { $0.id == selectedProjectID } }
    var selectedListIssue: ListIssue? { listIssues[selectedProjectID] }
    var isSelectedListAvailable: Bool { isStoreAvailable && selectedProject != nil && selectedListIssue == nil }
    var hasRetainedWork: Bool { !drafts.isEmpty || entryDrafts.values.contains { !$0.isEmpty } }

    func location(for id: String) -> ListLocation? { listLocations[id] }
    func issue(for id: String) -> ListIssue? { listIssues[id] }

    func isOverdue(_ task: TaskItem, projectID: String) -> Bool {
        isStoreAvailable && listIssues[projectID] == nil && overdueTaskIDs[projectID]?.contains(task.id) == true
    }

    func hasOverdueTasks(projectID: String) -> Bool {
        isStoreAvailable && listIssues[projectID] == nil && !(overdueTaskIDs[projectID]?.isEmpty ?? true)
    }

    /// Refresh only overdue membership, so clock ticks do not disturb native editors.
    /// An explicit date keeps fixtures deterministic without background observation.
    func updateDeadlineStatus(at date: Date = Date()) {
        var next: [String: Set<String>] = [:]
        if isStoreAvailable {
            for project in workspace.projects where listIssues[project.id] == nil {
                let overdue = Set(project.tasks.filter { $0.isOverdue(at: date) }.map(\.id))
                if !overdue.isEmpty { next[project.id] = overdue }
            }
        }
        if next != overdueTaskIDs { overdueTaskIDs = next }
        scheduleDeadlineUpdate(at: date)
    }

    func hasRetainedDrafts(listID: String) -> Bool {
        if drafts.values.contains(where: { draft in
            if let owner = draft.projectID ?? projectID(for: draft.itemID) { return owner == listID }
            return listIssues[listID] != nil
        }) { return true }
        return entryDrafts.contains { key, value in
            guard !value.isEmpty else { return false }
            if key == listID { return true }
            guard key.hasPrefix("subtask:") else { return false }
            let parts = key.dropFirst(8).split(separator: ":")
            if parts.count == 2 { return String(parts[0]) == listID }
            let itemID = String(key.dropFirst(8))
            if let owner = projectID(for: itemID) { return owner == listID }
            return listIssues[listID] != nil
        }
    }

    var expandedTaskID: String? { expandedTaskIDs[selectedProjectID] }
    var selectedTaskID: String? { selectedTaskIDs[selectedProjectID] }
    func selectedTaskID(projectID: String) -> String? { selectedTaskIDs[projectID] }
    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }

    func setBackgroundOpacity(_ value: Double) {
        guard value.isFinite else { return }
        let opacity = min(1, max(0.30, value))
        guard opacity != backgroundOpacity else { return }
        backgroundOpacity = opacity
        preferences.set(opacity, forKey: Self.backgroundOpacityKey)
    }

    func isCompletedExpanded(projectID: String) -> Bool {
        expandedCompletedProjectIDs.contains(projectID)
    }

    func taskListEntries(projectID: String) -> [TaskListEntry] {
        guard let project = workspace.projects.first(where: { $0.id == projectID }) else { return [] }
        var entries: [TaskListEntry] = [.addTask(projectID: projectID)]
        entries.append(contentsOf: project.tasks.filter { !$0.completed }.map(TaskListEntry.task))
        let completed = project.tasks.filter(\.completed)
        if !completed.isEmpty {
            entries.append(.completedHeader(projectID: projectID, count: completed.count))
            if isCompletedExpanded(projectID: projectID) {
                entries.append(contentsOf: completed.map(TaskListEntry.task))
            }
        }
        return entries
    }

    @discardableResult
    func toggleCompleted(projectID: String) -> Bool {
        guard let project = workspace.projects.first(where: { $0.id == projectID }) else { return false }
        guard isCompletedExpanded(projectID: projectID) else {
            expandedCompletedProjectIDs.insert(projectID)
            return true
        }
        let editedIDs = [expandedTaskIDs[projectID], selectedTaskIDs[projectID]].compactMap { $0 }
        if project.tasks.contains(where: { editedIDs.contains($0.id) && $0.completed }) {
            // Closing this section removes its editor. Native composition must
            // finish first, and a failed save must leave the draft accessible.
            if projectID == selectedProjectID,
               let editor = NSApp?.keyWindow?.firstResponder as? NSTextView,
               editor.hasMarkedText() {
                errorMessage = Self.completedCompositionMessage
                return false
            }
            guard flushTaskInteractionEdits(projectID: projectID) else { return false }
            if project.tasks.contains(where: { $0.id == expandedTaskIDs[projectID] && $0.completed }) {
                expandedTaskIDs.removeValue(forKey: projectID)
            }
            if project.tasks.contains(where: { $0.id == selectedTaskIDs[projectID] && $0.completed }) {
                selectedTaskIDs.removeValue(forKey: projectID)
                if projectID == selectedProjectID { NSApp?.keyWindow?.makeFirstResponder(nil) }
            }
        }
        expandedCompletedProjectIDs.remove(projectID)
        if errorMessage == Self.completedCompositionMessage { errorMessage = store.migrationWarning }
        return true
    }

    var orphanedDrafts: [OrphanedDraft] {
        guard isStoreAvailable else { return [] }
        let removed = drafts.values.filter { !isDraftUnavailable($0) && storedText(for: $0) == nil }
        return Dictionary(grouping: removed, by: \.recoveryID).map { recoveryID, edits in
            let title = edits.first { $0.field == .title || $0.field == .subtaskTitle }?.value ?? ""
            return OrphanedDraft(id: recoveryID, title: title, notes: edits.first { $0.field == .notes }?.value ?? "")
        }.sorted { $0.id < $1.id }
    }

    func scrollAnchor(projectID: String) -> String? {
        preferences.string(forKey: preferenceKey + ".scroll." + projectID)
    }

    func setScrollAnchor(projectID: String, taskID: String?) {
        preferences.set(taskID, forKey: preferenceKey + ".scroll." + projectID)
    }

    nonisolated private static func itemKey(_ itemID: String, projectID: String?) -> String {
        projectID.map { $0 + ":" + itemID } ?? itemID
    }

    nonisolated private static func draftKey(_ itemID: String, _ field: EditField, projectID: String?) -> String {
        itemKey(itemID, projectID: projectID) + ":" + field.rawValue
    }

    func text(itemID: String, field: EditField, fallback: String, projectID: String? = nil) -> String {
        let owner = projectID ?? editingProjectID(for: itemID)
        let key = Self.draftKey(itemID, field, projectID: owner)
        if let draft = drafts[key] { return draft.value }
        if owner == nil { return drafts[Self.draftKey(itemID, field, projectID: nil)]?.value ?? fallback }
        return fallback
    }

    func setText(itemID: String, field: EditField, value: String, expectedBase: String? = nil, projectID: String? = nil) {
        let owner = projectID ?? editingProjectID(for: itemID) ?? (expectedBase == nil ? nil : selectedProject?.id)
        let key = Self.draftKey(itemID, field, projectID: owner)
        let stored = storedText(itemID: itemID, field: field, projectID: owner)
        guard let baseline = drafts[key]?.base ?? expectedBase ?? stored else { return }
        if value == stored {
            drafts.removeValue(forKey: key)
            editConflicts.removeValue(forKey: key)
        } else {
            drafts[key] = Draft(itemID: itemID, field: field, projectID: owner, base: baseline, value: value)
            reconcileDrafts()
        }
        persistPreferences()
        scheduleAutosave()
    }

    func conflicts(itemID: String, projectID: String? = nil) -> [EditConflict] {
        let owner = projectID ?? editingProjectID(for: itemID)
        return editConflicts.values.filter { $0.itemID == itemID && drafts[$0.id]?.projectID == owner }.sorted { $0.field.rawValue < $1.field.rawValue }
    }

    func recoverOrphanedDraft(id: String) {
        guard let draft = orphanedDrafts.first(where: { $0.id == id }), let project = selectedProject else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recovered task" : draft.title
        let task = TaskItem(title: title, notes: draft.notes)
        if perform(.addTask(projectID: project.id, task: task, index: nil), name: "Recover Task", listID: project.id) {
            discardOrphan(id: id)
            expandedTaskIDs[project.id] = task.id
        }
    }

    func discardOrphanedDraft(id: String) {
        guard orphanedDrafts.contains(where: { $0.id == id }) else { return }
        discardOrphan(id: id)
        if orphanedDrafts.isEmpty { errorMessage = store.migrationWarning }
    }

    func resolveConflict(id: String, keepMine: Bool) {
        guard let conflict = editConflicts[id], var draft = drafts[id] else { return }
        do {
            let latest = try store.load()
            adopt(latest)
            guard !isDraftUnavailable(draft) else { return }
            guard let remote = storedText(for: draft) else {
                errorMessage = "This task was removed. Your unsaved text is still retained: \(draft.value)"
                return
            }
            // A second external edit needs a new review rather than an implicit overwrite.
            guard remote == conflict.remoteValue else {
                reconcileDrafts()
                errorMessage = "The task changed again. Review the latest text before choosing."
                return
            }
            if keepMine {
                draft.base = remote
                drafts[id] = draft
                editConflicts.removeValue(forKey: id)
                _ = flushDraft(id)
            } else {
                drafts.removeValue(forKey: id)
                editConflicts.removeValue(forKey: id)
                errorMessage = store.migrationWarning
            }
            persistPreferences()
        } catch { report(error) }
    }

    func selectProject(_ id: String) {
        guard workspace.projects.contains(where: { $0.id == id }) else { return }
        _ = flushPendingEdits()
        selectedProjectID = id
    }

    func toggleGroup(_ id: String) {
        if collapsedGroupIDs.contains(id) { collapsedGroupIDs.remove(id) }
        else { collapsedGroupIDs.insert(id) }
    }

    @discardableResult
    func selectTaskForEditing(taskID: String, projectID: String) -> Bool {
        guard projectID == selectedProjectID, taskWithID(taskID, projectID: projectID) != nil else { return false }
        if selectedTaskIDs[projectID] == taskID { return true }
        guard !hasActiveTextComposition, flushTaskInteractionEdits(projectID: projectID) else { return false }
        if expandedTaskIDs[projectID] != taskID { expandedTaskIDs.removeValue(forKey: projectID) }
        selectedTaskIDs[projectID] = taskID
        return true
    }

    @discardableResult
    func clickSelectedTaskTitle(taskID: String, projectID: String) -> Bool {
        guard projectID == selectedProjectID, selectedTaskIDs[projectID] == taskID else { return false }
        return toggleDetails(taskID: taskID)
    }

    @discardableResult
    func clearTaskSelection() -> Bool {
        guard !hasActiveTextComposition, flushTaskInteractionEdits(projectID: selectedProjectID) else { return false }
        expandedTaskIDs.removeValue(forKey: selectedProjectID)
        selectedTaskIDs.removeValue(forKey: selectedProjectID)
        NSApp?.keyWindow?.makeFirstResponder(nil)
        return true
    }

    @discardableResult
    func toggleDetails(taskID: String) -> Bool {
        guard taskWithID(taskID, projectID: selectedProjectID) != nil,
              !hasActiveTextComposition else { return false }
        if selectedTaskID == taskID && expandedTaskID == nil {
            // Opening this editor's guidance does not hide any existing input.
            // A blank or conflicting title must still have a way to recover.
            _ = flushTaskInteractionEdits(projectID: selectedProjectID)
        } else if !flushTaskInteractionEdits(projectID: selectedProjectID) { return false }
        selectedTaskIDs[selectedProjectID] = taskID
        if expandedTaskID == taskID { expandedTaskIDs.removeValue(forKey: selectedProjectID) }
        else {
            if selectedProject?.tasks.contains(where: { $0.id == taskID && $0.completed }) == true {
                expandedCompletedProjectIDs.insert(selectedProjectID)
            }
            expandedTaskIDs[selectedProjectID] = taskID
        }
        return true
    }

    private func flushTaskInteractionEdits(projectID: String) -> Bool {
        // Navigation in one list must not be blocked by a retained draft in
        // another list. Save the editors this interaction can actually hide.
        for key in drafts.keys.sorted() {
            guard let draft = drafts[key], (draft.projectID ?? self.projectID(for: draft.itemID)) == projectID else { continue }
            if !flushDraft(key) { persistPreferences(); return false }
        }
        persistPreferences()
        return true
    }

    func addTask(_ title: String) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let project = selectedProject else { return }
        if perform(.addTask(projectID: project.id, task: TaskItem(title: title), index: 0), name: "Add Task", listID: project.id) {
            entryDrafts[project.id] = ""
        }
    }

    func addSubtask(parentID: String, title: String, projectID: String? = nil) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let owner = projectID ?? self.projectID(for: parentID), taskWithID(parentID, projectID: owner) != nil else { return }
        if perform(.addSubtask(parentID: parentID, subtask: Subtask(title: title), index: nil), name: "Add Subtask", listID: owner) {
            setSubtaskEntry(parentID: parentID, projectID: owner, value: "")
        }
    }

    func subtaskEntry(parentID: String, projectID: String) -> String {
        entryDrafts[Self.subtaskEntryKey(parentID, projectID: projectID)] ?? ""
    }

    func setSubtaskEntry(parentID: String, projectID: String, value: String) {
        entryDrafts[Self.subtaskEntryKey(parentID, projectID: projectID)] = value
    }

    nonisolated private static func subtaskEntryKey(_ parentID: String, projectID: String) -> String {
        "subtask:" + projectID + ":" + parentID
    }

    func toggleTask(_ task: TaskItem, projectID: String? = nil) {
        guard let owner = projectID ?? self.projectID(for: task.id), let current = taskWithID(task.id, projectID: owner) else { return }
        _ = perform(.patchTask(id: task.id, patch: TaskPatch(completed: FieldChange(expected: current.completed, value: !current.completed))), name: current.completed ? "Reopen Task" : "Complete Task", listID: owner)
    }

    @discardableResult
    func prepareDeadlineEditing(projectID: String) -> Bool {
        guard isStoreAvailable, listIssues[projectID] == nil,
              workspace.projects.contains(where: { $0.id == projectID }),
              !hasActiveTextComposition else { return false }
        return flushTaskInteractionEdits(projectID: projectID)
    }

    @discardableResult
    func setDeadline(_ deadline: Date?, for task: TaskItem, projectID: String) -> Bool {
        guard taskWithID(task.id, projectID: projectID) != nil else { return false }
        // The menu's snapshot supplies the baseline even after an external refresh.
        // A deadline edit must not overwrite a value the user has not seen.
        return perform(.patchTask(id: task.id, patch: TaskPatch(deadline: FieldChange(expected: task.deadline, value: deadline))),
                       name: deadline == nil ? "Clear Deadline" : "Set Deadline", listID: projectID)
    }

    func toggleSubtask(_ subtask: Subtask, projectID: String? = nil) {
        guard let owner = projectID ?? self.projectID(for: subtask.id), let current = subtaskWithID(subtask.id, projectID: owner) else { return }
        _ = perform(.patchSubtask(id: subtask.id, patch: SubtaskPatch(completed: FieldChange(expected: current.completed, value: !current.completed))), name: current.completed ? "Reopen Subtask" : "Complete Subtask", listID: owner)
    }

    func deleteTask(_ task: TaskItem, projectID: String? = nil) {
        guard let owner = projectID ?? self.projectID(for: task.id) else { return }
        let itemIDs = Set([task.id] + task.subtasks.map(\.id))
        guard prepareDeletion(itemIDs, projectID: owner), let current = taskWithID(task.id, projectID: owner) else { return }
        if perform(.deleteTask(id: current.id, expected: current), name: "Delete Task", listID: owner) {
            discardDrafts(for: itemIDs, projectID: owner)
        }
    }

    func deleteSubtask(_ subtask: Subtask, projectID: String? = nil) {
        guard let owner = projectID ?? self.projectID(for: subtask.id) else { return }
        let itemIDs: Set<String> = [subtask.id]
        guard prepareDeletion(itemIDs, projectID: owner), let current = subtaskWithID(subtask.id, projectID: owner) else { return }
        if perform(.deleteSubtask(id: current.id, expected: current), name: "Delete Subtask", listID: owner) {
            discardDrafts(for: itemIDs, projectID: owner)
        }
    }

    @discardableResult
    func createList(name: String, at url: URL? = nil, groupID: String? = nil) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return listAction {
            let project = try store.createList(name: name, at: url, groupID: groupID)
            adopt(try store.load())
            selectedProjectID = project.id
            if let groupID = project.groupID { collapsedGroupIDs.remove(groupID) }
        }
    }

    @discardableResult
    func openList(at url: URL, groupID: String? = nil) -> Bool {
        listIdentityConflict = nil
        return listAction {
            let project = try store.openList(at: url, groupID: groupID)
            adopt(try store.load())
            selectedProjectID = project.id
            if let groupID = project.groupID { collapsedGroupIDs.remove(groupID) }
        }
    }

    @discardableResult
    func moveList(id: String, to url: URL) -> Bool {
        listAction {
            try store.moveList(id: id, to: url)
            adopt(try store.load())
        }
    }

    @discardableResult
    func relinkList(id: String, to url: URL) -> Bool {
        listAction {
            try store.relinkList(id: id, to: url)
            adopt(try store.load())
        }
    }

    @discardableResult
    func removeList(id: String) -> Bool {
        if selectedProjectID == id, let editor = NSApp?.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() {
            errorMessage = Self.removeCompositionMessage
            return false
        }
        // Unlinking leaves the file and unsaved text available for recovery.
        return listAction {
            try store.removeList(id: id)
            adopt(try store.load())
        }
    }

    /// Save edited tasks, while retaining unfinished task/subtask entries locally.
    /// Run before opening the confirmation and again after it returns.
    @discardableResult
    func prepareListDeletion(id: String, expectedURL: URL) -> Bool {
        guard isStoreAvailable, location(for: id)?.url == expectedURL else {
            errorMessage = "This list's location changed. Review its current file and confirm Delete List again."
            return false
        }
        guard issue(for: id) == nil else {
            errorMessage = "This list is unavailable. Locate or retry its file before deleting, or use Hide List."
            return false
        }
        if selectedProjectID == id, let editor = NSApp?.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() {
            errorMessage = "Finish the current text composition before deleting this list."
            return false
        }
        for key in drafts.keys.sorted() {
            guard let draft = drafts[key], (draft.projectID ?? projectID(for: draft.itemID)) == id else { continue }
            guard flushDraft(key) else { persistPreferences(); return false }
        }
        persistPreferences()
        return true
    }

    @discardableResult
    func deleteList(id: String, expectedURL: URL) -> Bool {
        guard prepareListDeletion(id: id, expectedURL: expectedURL) else { return false }
        return listAction {
            try store.deleteList(id: id, expectedURL: expectedURL)
            adopt(try store.load())
        }
    }

    private func listAction(_ action: () throws -> Void) -> Bool {
        guard isStoreAvailable else { return false }
        do {
            try action()
            listIdentityConflict = nil
            errorMessage = store.migrationWarning
            return true
        } catch {
            if let latest = try? store.load() { adopt(latest) }
            listIdentityConflict = error as? ListIdentityConflict
            report(error)
            return false
        }
    }

    func createProject(name: String, groupID: String?) {
        _ = createList(name: name, groupID: groupID)
    }

    func renameProject(_ project: Project, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = perform(.patchProject(id: project.id, name: FieldChange(expected: project.name, value: name), groupID: nil), name: "Rename List")
    }

    func moveProject(_ project: Project, groupID: String?) {
        _ = moveProject(project, to: .group(groupID))
    }

    @discardableResult
    func moveTask(_ task: TaskItem, projectID: String, to target: TaskDropTarget, expectedOrder: [String]? = nil) -> Bool {
        guard !hasActiveTextComposition, flushTaskInteractionEdits(projectID: projectID) else { return false }
        guard let project = workspace.projects.first(where: { $0.id == projectID }),
              let current = project.tasks.first(where: { $0.id == task.id }),
              current.completed == task.completed else {
            errorMessage = "This task was removed or changed sections. Refresh the list and try again."
            return false
        }
        let originalOrder = expectedOrder ?? project.tasks.filter { $0.completed == task.completed }.map(\.id)
        let targetID: String
        switch target {
        case .before(let id), .after(let id): targetID = id
        }
        guard originalOrder.contains(task.id),
              let destination = project.tasks.first(where: { $0.id == targetID }),
              destination.completed == task.completed,
              originalOrder.contains(targetID) else {
            errorMessage = "Tasks can only be reordered within the same list and completion section."
            return false
        }
        var order = originalOrder.filter { $0 != task.id }
        if targetID == task.id { order = originalOrder }
        else if let index = order.firstIndex(of: targetID) {
            order.insert(task.id, at: index + (target == .after(targetID) ? 1 : 0))
        }
        return perform(.reorderTasks(projectID: projectID, completed: task.completed,
            change: FieldChange(expected: originalOrder, value: order)), name: "Move Task", listID: projectID)
    }

    func canStartTaskDrag(projectID: String) -> Bool {
        isStoreAvailable && issue(for: projectID) == nil && selectedProjectID == projectID && !hasActiveTextComposition
    }

    func canMoveTask(_ task: TaskItem, projectID: String, offset: Int) -> Bool {
        adjacentTaskTarget(task, projectID: projectID, offset: offset) != nil
    }

    private func adjacentTaskTarget(_ task: TaskItem, projectID: String, offset: Int) -> TaskDropTarget? {
        guard offset == -1 || offset == 1,
              let project = workspace.projects.first(where: { $0.id == projectID }) else { return nil }
        let siblings = project.tasks.filter { $0.completed == task.completed }
        guard let index = siblings.firstIndex(where: { $0.id == task.id }),
              siblings.indices.contains(index + offset) else { return nil }
        let destination = siblings[index + offset].id
        return offset < 0 ? .before(destination) : .after(destination)
    }

    @discardableResult
    func moveTask(_ task: TaskItem, projectID: String, offset: Int) -> Bool {
        guard let target = adjacentTaskTarget(task, projectID: projectID, offset: offset) else { return false }
        return moveTask(task, projectID: projectID, to: target)
    }

    @discardableResult
    func moveProject(_ project: Project, to target: ProjectDropTarget, expectedOrder: [String]? = nil) -> Bool {
        guard workspace.projects.contains(where: { $0.id == project.id }) else {
            errorMessage = "This list was removed. Refresh the lists and try again."
            return false
        }
        let originalOrder = expectedOrder ?? workspace.projects.map(\.id)
        var order = originalOrder.filter { $0 != project.id }
        let destinationGroup: String?
        let insertionIndex: Int
        var operations: [StoreOperation] = []
        switch target {
        case .before(let targetID), .after(let targetID):
            if targetID == project.id { return true }
            guard let destination = workspace.projects.first(where: { $0.id == targetID }),
                  let index = order.firstIndex(of: targetID) else {
                errorMessage = "The destination list was removed. Refresh the lists and try again."
                return false
            }
            destinationGroup = destination.groupID
            insertionIndex = index + (target == .after(targetID) ? 1 : 0)
            // Protect the drop's target group against a concurrent group move.
            operations.append(.patchProject(id: destination.id, name: nil,
                groupID: FieldChange(expected: destination.groupID, value: destination.groupID)))
        case .group(let groupID):
            guard groupID == nil || workspace.groups.contains(where: { $0.id == groupID }) else {
                errorMessage = "The destination group was removed. Refresh the lists and try again."
                return false
            }
            destinationGroup = groupID
            let siblingIDs = Set(workspace.projects.filter { $0.groupID == groupID }.map(\.id))
            insertionIndex = order.lastIndex(where: { siblingIDs.contains($0) }).map { $0 + 1 } ?? order.endIndex
        }
        order.insert(project.id, at: insertionIndex)
        operations.append(.patchProject(id: project.id, name: nil,
            groupID: FieldChange(expected: project.groupID, value: destinationGroup)))
        operations.append(.reorderProjects(change: FieldChange(expected: originalOrder, value: order)))
        return perform(.batch(operations), name: "Move List")
    }

    func canMoveProject(_ project: Project, offset: Int) -> Bool {
        guard offset == -1 || offset == 1 else { return false }
        let siblings = workspace.projects.filter { $0.groupID == project.groupID }
        guard let index = siblings.firstIndex(where: { $0.id == project.id }) else { return false }
        return siblings.indices.contains(index + offset)
    }

    @discardableResult
    func moveProject(_ project: Project, offset: Int) -> Bool {
        guard canMoveProject(project, offset: offset) else { return false }
        let siblings = workspace.projects.filter { $0.groupID == project.groupID }
        guard let index = siblings.firstIndex(where: { $0.id == project.id }) else { return false }
        let destinationID = siblings[index + offset].id
        return moveProject(project, to: offset < 0 ? .before(destinationID) : .after(destinationID))
    }

    func deleteProject(_ project: Project) {
        _ = removeList(id: project.id)
    }

    func createGroup(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = perform(.addGroup(group: ProjectGroup(name: name), index: nil), name: "Add Group")
    }

    func renameGroup(_ group: ProjectGroup, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = perform(.renameGroup(id: group.id, change: FieldChange(expected: group.name, value: name)), name: "Rename Group")
    }

    func deleteGroup(_ group: ProjectGroup) {
        _ = perform(.deleteGroup(id: group.id, expected: group), name: "Delete Group")
    }

    @discardableResult
    func flushPendingEdits() -> Bool {
        autosave?.cancel()
        autosave = nil
        guard isStoreAvailable else { return drafts.isEmpty }
        var saved = true
        for key in drafts.keys.sorted() {
            if !flushDraft(key) { saved = false }
        }
        persistPreferences()
        return saved
    }

    /// Unavailable files keep durable local drafts without trapping the app open.
    /// Healthy drafts still need to save before their native editor disappears.
    @discardableResult
    func flushEditsForDismissal() -> Bool {
        autosave?.cancel()
        autosave = nil
        guard isStoreAvailable else { persistPreferences(); return true }
        let saved = flushAvailableEdits()
        persistPreferences()
        return saved
    }

    func refresh() {
        do {
            let latest = try store.load()
            isStoreAvailable = true
            cancelCatalogRecovery()
            errorMessage = store.migrationWarning
            adopt(latest)
        } catch {
            isStoreAvailable = false
            updateDeadlineStatus()
            autosave?.cancel()
            autosave = nil
            startWatcherIfNeeded()
            report(error)
        }
    }

    /// Catalog recovery is deliberately separate from ordinary per-list backups.
    /// Preparing a preview never flushes drafts or changes a list file.
    @discardableResult
    func beginCatalogRecovery() -> Bool {
        guard !isStoreAvailable, !hasActiveTextComposition else { return false }
        isCatalogRecoveryPresented = true
        return refreshCatalogRecovery()
    }

    @discardableResult
    func refreshCatalogRecovery(additionalURLs: [URL] = []) -> Bool {
        guard !isStoreAvailable, isCatalogRecoveryPresented, !hasActiveTextComposition else { return false }
        autosave?.cancel()
        autosave = nil
        additionalCatalogRecoveryURLs.formUnion(additionalURLs)
        do {
            let plan = try store.prepareCatalogRecovery(additionalURLs: Array(additionalCatalogRecoveryURLs))
            let nextURLs = Set(plan.candidates.map(\.url))
            if let previous = catalogRecoveryPlan {
                let previousURLs = Set(previous.candidates.map(\.url))
                // Refreshes retain explicit exclusions, including hidden lists
                // rediscovered in the managed folder. Newly chosen files start selected.
                catalogRecoverySelectedURLs = catalogRecoverySelectedURLs.intersection(nextURLs)
                    .union(nextURLs.subtracting(previousURLs))
            } else {
                catalogRecoverySelectedURLs = nextURLs
            }
            catalogRecoveryPlan = plan
            catalogRecoveryErrorMessage = nil
            persistPreferences()
            return true
        } catch {
            catalogRecoveryErrorMessage = error.localizedDescription
            persistPreferences()
            return false
        }
    }

    func setCatalogRecoverySelection(_ url: URL, isSelected: Bool) {
        guard catalogRecoveryPlan?.candidates.contains(where: { $0.url == url }) == true else { return }
        if isSelected { catalogRecoverySelectedURLs.insert(url) }
        else { catalogRecoverySelectedURLs.remove(url) }
    }

    func cancelCatalogRecovery() {
        isCatalogRecoveryPresented = false
        catalogRecoveryPlan = nil
        catalogRecoverySelectedURLs = []
        catalogRecoveryErrorMessage = nil
        additionalCatalogRecoveryURLs = []
    }

    @discardableResult
    func rebuildCatalog() -> Bool {
        guard !isStoreAvailable, isCatalogRecoveryPresented,
              let plan = catalogRecoveryPlan, !hasActiveTextComposition else { return false }
        autosave?.cancel()
        autosave = nil
        observationRefresh?.cancel()
        observationRefresh = nil
        persistPreferences()
        do {
            let result = try store.rebuildCatalog(using: plan, selectedURLs: Array(catalogRecoverySelectedURLs))
            isStoreAvailable = true
            listIdentityConflict = nil
            errorMessage = store.migrationWarning
            undoManager.removeAllActions()
            // Retain navigation for an excluded list so reopening it can recover
            // its local editor state alongside owner-scoped drafts and entries.
            adopt(result.workspace, preservingRecoveryPreferences: true)
            catalogRecoveryNotice = CatalogRecoveryNotice(preservedCatalogURL: result.preservedCatalogURL)
            cancelCatalogRecovery()
            return true
        } catch {
            // A changed catalog or selected file needs another preview. Keep the
            // current review and its choices visible, with all local work intact.
            catalogRecoveryErrorMessage = error.localizedDescription
            persistPreferences()
            startWatcherIfNeeded()
            return false
        }
    }

    func dismissCatalogRecoveryNotice() { catalogRecoveryNotice = nil }

    private var hasActiveTextComposition: Bool {
        (NSApp?.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    func undo() {
        guard flushAvailableEdits(), undoManager.canUndo else { return }
        undoManager.undo()
        objectWillChange.send()
    }

    func redo() {
        guard flushAvailableEdits(), undoManager.canRedo else { return }
        undoManager.redo()
        objectWillChange.send()
    }

    func availableBackups(listID: String? = nil) -> [BackupInfo] {
        guard isStoreAvailable else { return [] }
        let owner = listID ?? selectedProjectID
        guard !owner.isEmpty else { return [] }
        do { return try store.backups(listID: owner) }
        catch { report(error); return [] }
    }

    func restoreBackup(_ backup: BackupInfo, listID: String? = nil) {
        do {
            let restored = try store.restoreBackup(at: backup.url, listID: listID ?? selectedProjectID)
            isStoreAvailable = true
            errorMessage = store.migrationWarning
            undoManager.removeAllActions()
            adopt(restored)
        } catch { report(error) }
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        guard isStoreAvailable else { autosave = nil; return }
        autosave = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.flushPendingEdits()
        }
    }

    private func prepareDeletion(_ itemIDs: Set<String>, projectID: String) -> Bool {
        // Save valid target edits for useful Undo, but permit the explicit deletion
        // offered when a title is blank. Other items' drafts remain independent.
        for (key, draft) in drafts where itemIDs.contains(draft.itemID) && draft.projectID == projectID {
            if draft.field != .notes && draft.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if !flushDraft(key) { return false }
        }
        return true
    }

    private func discardDrafts(for itemIDs: Set<String>, projectID: String) {
        drafts = drafts.filter { !itemIDs.contains($0.value.itemID) || $0.value.projectID != projectID }
        editConflicts = editConflicts.filter { drafts[$0.key] != nil }
        persistPreferences()
    }

    private func discardOrphan(id: String) {
        drafts = drafts.filter { $0.value.recoveryID != id }
        editConflicts = editConflicts.filter { drafts[$0.key] != nil }
        persistPreferences()
    }

    private func flushDraft(_ key: String) -> Bool {
        guard let draft = drafts[key] else { return true }
        guard !isDraftUnavailable(draft), editConflicts[key] == nil else { return false }
        guard storedText(for: draft) != nil else {
            errorMessage = "A task with unsaved changes was removed. Recover or discard its retained draft."
            return false
        }
        if draft.field != .notes && draft.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Give this task a title, or use Delete Task. Your draft is retained."
            return false
        }
        let change = FieldChange(expected: draft.base, value: draft.value)
        let operation: StoreOperation
        switch draft.field {
        case .title: operation = .patchTask(id: draft.itemID, patch: TaskPatch(title: change))
        case .notes: operation = .patchTask(id: draft.itemID, patch: TaskPatch(notes: change))
        case .subtaskTitle: operation = .patchSubtask(id: draft.itemID, patch: SubtaskPatch(title: change))
        }
        do {
            let result = try store.apply(operation, owningListID: draft.projectID)
            drafts.removeValue(forKey: key)
            editConflicts.removeValue(forKey: key)
            adopt(result.workspace)
            registerUndo(result.undo, name: "Edit Task", listID: draft.projectID)
            errorMessage = store.migrationWarning
            return true
        } catch {
            // Reload the current values to present a conflict, preserving the local draft.
            if let latest = try? store.load() { adopt(latest) }
            report(error)
            return false
        }
    }

    @discardableResult
    private func perform(_ operation: StoreOperation, name: String, listID: String? = nil) -> Bool {
        guard isStoreAvailable else { return false }
        do {
            let result = try store.apply(operation, owningListID: listID)
            adopt(result.workspace)
            registerUndo(result.undo, name: name, listID: listID)
            errorMessage = store.migrationWarning
            return true
        } catch {
            if let latest = try? store.load() { adopt(latest) }
            report(error)
            return false
        }
    }

    private func registerUndo(_ inverse: StoreOperation?, name: String, listID: String?) {
        guard let inverse else { return }
        let needsGroup = undoManager.groupingLevel == 0
        if needsGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { model in
            _ = model.perform(inverse, name: name, listID: listID)
        }
        undoManager.setActionName(name)
        if needsGroup { undoManager.endUndoGrouping() }
        objectWillChange.send()
    }

    private func adopt(_ latest: Workspace, preservingRecoveryPreferences: Bool = false) {
        // Persist ownership before replacing a snapshot; older preferences have no owner.
        var ownedDrafts: [String: Draft] = [:]
        for var draft in drafts.values {
            if draft.projectID == nil { draft.projectID = retainedOwner(for: draft.itemID, latest: latest) }
            ownedDrafts[draft.key] = draft
        }
        drafts = ownedDrafts
        // Old entry preferences used only the parent ID. Bind them before a
        // snapshot disappears, and leave ambiguous legacy text retained locally.
        for key in Array(entryDrafts.keys) where key.hasPrefix("subtask:") {
            let parentID = String(key.dropFirst(8))
            guard !parentID.contains(":"), let owner = retainedOwner(for: parentID, latest: latest) else { continue }
            let scopedKey = Self.subtaskEntryKey(parentID, projectID: owner)
            if entryDrafts[scopedKey] == nil { entryDrafts[scopedKey] = entryDrafts[key] }
            entryDrafts.removeValue(forKey: key)
        }
        if listLocations != store.listLocations { listLocations = store.listLocations }
        if listIssues != store.listIssues { listIssues = store.listIssues }
        let projectIDs = Set(latest.projects.map(\.id))
        var visibleCompleted = preservingRecoveryPreferences
            ? expandedCompletedProjectIDs : expandedCompletedProjectIDs.intersection(projectIDs)
        for project in latest.projects {
            let editedIDs = [expandedTaskIDs[project.id], selectedTaskIDs[project.id]].compactMap { $0 }
            if project.tasks.contains(where: { editedIDs.contains($0.id) && $0.completed }) {
                visibleCompleted.insert(project.id)
            }
        }
        // Reveal before publishing the moved task, including externally completed
        // tasks whose native editor may currently contain unpublished IME text.
        if visibleCompleted != expandedCompletedProjectIDs {
            expandedCompletedProjectIDs = visibleCompleted
        }
        if workspace != latest { workspace = latest }
        updateDeadlineStatus()
        if !workspace.projects.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectID = workspace.projects.first?.id ?? ""
        }
        if !preservingRecoveryPreferences {
            let groupIDs = Set(workspace.groups.map(\.id))
            collapsedGroupIDs.formIntersection(groupIDs)
            expandedTaskIDs = expandedTaskIDs.filter { projectID, taskID in
                workspace.projects.first(where: { $0.id == projectID })?.tasks.contains(where: { $0.id == taskID }) == true || listIssues[projectID] != nil
            }
            selectedTaskIDs = selectedTaskIDs.filter { projectID, taskID in
                workspace.projects.first(where: { $0.id == projectID })?.tasks.contains(where: { $0.id == taskID }) == true || listIssues[projectID] != nil
            }
        }
        // Entry text is local unfinished work. Unlinking does not discard it;
        // reopening the same list restores its task and subtask entries.
        reconcileDrafts()
        persistPreferences()
        startWatcherIfNeeded()
    }

    private func reconcileDrafts() {
        var next: [String: EditConflict] = [:]
        var satisfied: [String] = []
        for (key, draft) in drafts {
            guard !isDraftUnavailable(draft) else { continue }
            guard let remote = storedText(for: draft) else {
                errorMessage = "A task with unsaved changes was removed. Recover or discard its retained draft."
                continue
            }
            if remote == draft.value { satisfied.append(key) }
            else if remote != draft.base {
                next[key] = EditConflict(id: key, itemID: draft.itemID, field: draft.field, localValue: draft.value, remoteValue: remote)
            }
        }
        for key in satisfied { drafts.removeValue(forKey: key) }
        if editConflicts != next { editConflicts = next }
    }

    private func projectID(for itemID: String) -> String? {
        workspace.projects.first { project in
            listIssues[project.id] == nil &&
            project.tasks.contains { $0.id == itemID || $0.subtasks.contains { $0.id == itemID } }
        }?.id
    }

    private func editingProjectID(for itemID: String) -> String? {
        if let selectedProject, selectedProject.tasks.contains(where: { $0.id == itemID || $0.subtasks.contains { $0.id == itemID } }) ||
            drafts.values.contains(where: { $0.itemID == itemID && $0.projectID == selectedProject.id }) {
            return selectedProject.id
        }
        return projectID(for: itemID)
    }

    private func retainedOwner(for itemID: String, latest: Workspace) -> String? {
        func owners(in snapshot: Workspace) -> [String] {
            snapshot.projects.filter { project in
                project.tasks.contains { $0.id == itemID || $0.subtasks.contains { $0.id == itemID } }
            }.map(\.id)
        }
        let previous = owners(in: workspace)
        if previous.count == 1, listIssues.isEmpty { return previous[0] }
        // A legacy ownerless draft cannot safely bind to a replacement ID while
        // another linked list is unavailable.
        guard store.listIssues.isEmpty else { return nil }
        let current = owners(in: latest)
        return current.count == 1 ? current[0] : nil
    }

    private func isDraftUnavailable(_ draft: Draft) -> Bool {
        guard isStoreAvailable else { return true }
        if let owner = draft.projectID { return listIssues[owner] != nil }
        // Legacy drafts lack ownership. Avoid claiming their task was deleted
        // when any linked document cannot currently be read.
        return !listIssues.isEmpty
    }

    private func flushAvailableEdits() -> Bool {
        guard isStoreAvailable else { return false }
        var saved = true
        for key in drafts.keys.sorted() {
            if let draft = drafts[key], !isDraftUnavailable(draft), !flushDraft(key) { saved = false }
        }
        return saved
    }

    private func storedText(for draft: Draft) -> String? {
        storedText(itemID: draft.itemID, field: draft.field, projectID: draft.projectID)
    }

    private func storedText(itemID: String, field: EditField, projectID: String? = nil) -> String? {
        switch field {
        case .title: return taskWithID(itemID, projectID: projectID)?.title
        case .notes: return taskWithID(itemID, projectID: projectID)?.notes
        case .subtaskTitle: return subtaskWithID(itemID, projectID: projectID)?.title
        }
    }

    private func taskWithID(_ id: String, projectID: String? = nil) -> TaskItem? {
        workspace.projects.lazy.filter { self.listIssues[$0.id] == nil && (projectID == nil || $0.id == projectID) }.flatMap(\.tasks).first { $0.id == id }
    }

    private func subtaskWithID(_ id: String, projectID: String? = nil) -> Subtask? {
        workspace.projects.lazy.filter { self.listIssues[$0.id] == nil && (projectID == nil || $0.id == projectID) }.flatMap(\.tasks).flatMap(\.subtasks).first { $0.id == id }
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        persistPreferences()
    }

    private func persistPreferences() {
        guard !restoringPreferences else { return }
        var values: [String: Any] = [
            "selectedProjectID": selectedProjectID,
            "collapsedGroupIDs": Array(collapsedGroupIDs),
            "expandedTaskIDs": expandedTaskIDs,
            "expandedCompletedProjectIDs": Array(expandedCompletedProjectIDs),
            "entryDrafts": entryDrafts
        ]
        if let data = try? JSONEncoder().encode(Array(drafts.values)) { values["drafts"] = data }
        preferences.set(values, forKey: preferenceKey)
    }

    private func startWatcherIfNeeded() {
        guard watchChanges else { return }
        var paths = Set(store.observedDirectories.map { $0.standardizedFileURL.path })
        paths.insert(store.url.deletingLastPathComponent().standardizedFileURL.path)
        paths.insert(store.catalogURL.standardizedFileURL.path)
        for location in listLocations.values {
            paths.insert(location.url.standardizedFileURL.path)
            paths.insert(location.url.deletingLastPathComponent().standardizedFileURL.path)
        }
        // If a drive/folder disappears, observe the nearest existing ancestor so
        // restoring it can recover without a timer per list or task.
        for path in Array(paths) {
            var ancestor = URL(fileURLWithPath: path)
            while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
                ancestor.deleteLastPathComponent()
            }
            paths.insert(ancestor.path)
        }
        watchers = watchers.filter { paths.contains($0.key) && $0.value.matchesCurrentFile }
        for path in paths where watchers[path] == nil {
            watchers[path] = StorePathWatcher(url: URL(fileURLWithPath: path)) { [weak self] in
                Task { @MainActor [weak self] in self?.scheduleObservationRefresh() }
            }
        }
    }

    private func startDeadlineObservationIfNeeded() {
        guard watchChanges else { return }
        let notifications = [
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification),
            NotificationCenter.default.publisher(for: .NSSystemClockDidChange),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        ]
        deadlineSubscriptions = notifications.map { publisher in
            publisher.sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateDeadlineStatus() }
            }
        }
    }

    private func scheduleDeadlineUpdate(at date: Date) {
        deadlineClock?.cancel()
        deadlineClock = nil
        guard watchChanges, isStoreAvailable else { return }
        let deadlines = workspace.projects.filter { listIssues[$0.id] == nil }
            .flatMap(\.tasks).filter { !$0.completed }.compactMap(\.deadline)
        guard !deadlines.isEmpty else { return }
        // Wake at the next deadline; the bounded fallback also corrects wall-clock
        // changes when a notification is missed or the app stays hidden.
        let nextDeadline = deadlines.filter { $0 >= date }.min()
        let interval = min(30, max(0.01, (nextDeadline?.timeIntervalSince(date) ?? 30) + 0.01))
        deadlineClock = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.updateDeadlineStatus()
        }
    }

    private func scheduleObservationRefresh() {
        observationRefresh?.cancel()
        observationRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    deinit { deadlineClock?.cancel() }
}

private final class StorePathWatcher: @unchecked Sendable {
    private let url: URL
    private let device: dev_t
    private let inode: ino_t
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "Chit.store-observation")

    var matchesCurrentFile: Bool {
        guard (try? LabEnvironment.requireAllowed(url)) != nil else { return false }
        var info = stat()
        return stat(url.path, &info) == 0 && info.st_dev == device && info.st_ino == inode
    }

    init?(url: URL, changed: @escaping @Sendable () -> Void) {
        guard (try? LabEnvironment.requireAllowed(url)) != nil else { return nil }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { close(descriptor); return nil }
        self.url = url
        device = info.st_dev
        inode = info.st_ino
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .revoke], queue: queue)
        self.source = source
        source.setEventHandler(handler: changed)
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit { source?.cancel() }
}

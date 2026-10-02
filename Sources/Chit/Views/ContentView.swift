import AppKit
import SwiftUI
import TodoCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var compositionInProgress = false
    @State private var newListPresented = false
    @State private var newListGroupID: String?
    @State private var recoveryBackups: [BackupInfo] = []
    @State private var recoveryListID = ""

    var body: some View {
        GeometryReader { _ in
            let layout = SidebarLayout(expanded: model.sidebarExpanded, preferredWidth: model.sidebarExpandedWidth)
            VStack(spacing: 0) {
                if displaysCatalogRecovery {
                    CatalogRecoveryHeader()
                        .padding(.horizontal, 5).padding(.vertical, 2)
                    Rectangle().fill(Mocha.secondary.opacity(0.13)).frame(height: 1)
                        .padding(.horizontal, 10)
                    CatalogRecoveryView(model: model)
                } else {
                    ProjectHeader(model: model, sidebarExpanded: model.sidebarExpanded, onToggleSidebar: {
                        model.toggleSidebar()
                    })
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                    Rectangle().fill(Mocha.secondary.opacity(0.13)).frame(height: 1)
                        .padding(.horizontal, 10)
                    adaptiveWorkspace(layout: layout)
                }
            }
        }
        .foregroundStyle(Mocha.text)
        .tint(Mocha.blue)
        .preferredColorScheme(.dark)
        .frame(minWidth: SidebarLayout.minimumCollapsedWindowWidth, minHeight: 180)
        .onReceive(NotificationCenter.default.publisher(for: NSText.didChangeNotification)) { _ in
            compositionInProgress = selectedEditorHasMarkedText
        }
        .onReceive(NotificationCenter.default.publisher(for: NSText.didEndEditingNotification)) { _ in
            compositionInProgress = selectedEditorHasMarkedText
        }
        .onReceive(NotificationCenter.default.publisher(for: HeaderDragView.blankClick)) { _ in
            _ = model.clearTaskSelection()
        }
        .sheet(isPresented: $newListPresented) {
            NewListForm(model: model, groupID: newListGroupID) { newListPresented = false }
        }
        .onChange(of: model.errorMessage, initial: true) { _, _ in refreshRecoveryBackups() }
        .onChange(of: model.selectedProjectID) { _, _ in
            refreshRecoveryBackups()
        }
        .onChange(of: model.selectedListIssue) { _, _ in refreshRecoveryBackups() }
        .onChange(of: model.isStoreAvailable) { _, _ in refreshRecoveryBackups() }
    }

    private func presentNewList(_ groupID: String?) {
        newListGroupID = groupID
        newListPresented = true
    }

    private func adaptiveWorkspace(layout: SidebarLayout) -> some View {
        ZStack(alignment: .leading) {
            // This subtree stays at the same identity and parent in every
            // sidebar mode. Only its available width changes; native text
            // editors, their composition, selection and Undo remain alive.
            taskWorkspace
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, layout.taskInset)
                .accessibilityIdentifier("task-workspace")
            ProjectSidebar(model: model, onNewList: presentNewList)
                .frame(width: layout.sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(Color(red: 30 / 255, green: 30 / 255, blue: 46 / 255).opacity(0.25))
                .background(SidebarInteractionBoundary(onBlankToggle: model.toggleSidebar))
                .accessibilityIdentifier("list-sidebar")
            Rectangle().fill(Mocha.secondary.opacity(0.13))
                .frame(width: SidebarLayout.dividerWidth)
                .frame(maxHeight: .infinity)
                .offset(x: layout.sidebarWidth)
                .opacity(model.sidebarExpanded ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            SidebarResizeDivider(model: model)
                .frame(width: SidebarResizeDivider.hitWidth)
                .frame(maxHeight: .infinity)
                .offset(x: layout.sidebarWidth + SidebarLayout.dividerWidth / 2 - SidebarResizeDivider.hitWidth / 2)
                .opacity(model.sidebarExpanded ? 1 : 0)
                .accessibilityHidden(!model.sidebarExpanded)
        }
        .clipped()
    }

    private var taskWorkspace: some View {
        VStack(spacing: 0) {
            CatalogRecoveryNoticeView(model: model)
            if let error = model.errorMessage {
                VStack(alignment: .leading, spacing: 5) {
                    Text(error).font(.system(size: 12)).textSelection(.enabled)
                    HStack {
                        Button("Retry") { model.refresh(); _ = model.flushPendingEdits() }
                        recoveryMenu
                    }
                    .font(.system(size: 11))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Mocha.hover)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 10)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Save or recovery error")
            }
            if !model.orphanedDrafts.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(model.orphanedDrafts) { draft in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Unsaved text from a removed task")
                                    .fontWeight(.medium)
                                Text(draft.title).textSelection(.enabled)
                                if !draft.notes.isEmpty { Text(draft.notes).textSelection(.enabled) }
                                HStack {
                                    Button("Restore as task") { model.recoverOrphanedDraft(id: draft.id) }
                                        .disabled(model.selectedProject == nil || !model.isSelectedListAvailable)
                                    Button("Discard", role: .destructive) { model.discardOrphanedDraft(id: draft.id) }
                                }
                            }
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .frame(maxHeight: 150)
                .background(Mocha.hover)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 10)
                .accessibilityLabel("Retained text recovery")
            }
            if let issue = model.selectedListIssue, let project = model.selectedProject,
               !compositionInProgress && !selectedEditorHasMarkedText {
                VStack(alignment: .leading, spacing: 8) {
                    Text(issue.isMissing ? "List file not found" : "This list needs attention")
                        .font(.system(size: 13, weight: .medium))
                    Text(issue.message).font(.system(size: 12)).foregroundStyle(Mocha.secondary)
                        .textSelection(.enabled)
                    if model.hasRetainedDrafts(listID: project.id) {
                        Text("Your unsaved text is kept in Chit.")
                            .font(.system(size: 11)).foregroundStyle(Mocha.secondary)
                    }
                    HStack(spacing: 10) {
                        Button("Retry") { model.refresh() }
                        Button("Locate List…") { ListActions.locate(project, model: model) }
                    }
                    .font(.system(size: 12))
                    recoveryMenu.font(.system(size: 11))
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("List file error")
            } else if let project = model.selectedProject {
                ProjectTaskList(model: model, project: project)
                    .id(project.id)
            } else if model.isStoreAvailable {
                VStack(spacing: 12) {
                    Text("No lists yet")
                        .font(.system(size: 13)).foregroundStyle(Mocha.secondary)
                    HStack(spacing: 10) {
                        Menu("New List") {
                            NewListDestinationOptions(model: model) {
                                newListGroupID = nil
                                newListPresented = true
                            }
                        }
                        .menuStyle(.borderedButton)
                        .fixedSize()
                        Button("Open List…") { ListActions.open(model: model) }
                    }
                    .font(.system(size: 12))
                    .controlSize(.small)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                CatalogRecoveryView(model: model)
            }
        }
    }

    private var recoveryMenu: some View {
        Menu("Recover from backup") {
            if recoveryBackups.isEmpty { Text("No valid backups available") }
            ForEach(recoveryBackups) { backup in
                Button(backup.date.formatted(date: .abbreviated, time: .standard)) {
                    model.restoreBackup(backup, listID: recoveryListID)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func refreshRecoveryBackups() {
        recoveryListID = model.selectedProjectID
        recoveryBackups = model.isStoreAvailable && (model.errorMessage != nil || model.selectedListIssue != nil)
            ? model.availableBackups(listID: recoveryListID) : []
    }

    private var displaysCatalogRecovery: Bool {
        // Retain the editor until its unpublished IME composition can commit to
        // an owner-scoped draft. Recovery must never replace marked text.
        !model.isStoreAvailable && !compositionInProgress && !selectedEditorHasMarkedText
    }

    private var selectedEditorHasMarkedText: Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? PlainTextView,
              let project = model.selectedProject else { return false }
        let identities = Set(project.tasks.flatMap { task in
            ["\(task.id):title", "\(task.id):notes", "add-child:\(task.id)"]
                + task.subtasks.map { "\($0.id):title" }
        } + ["add:\(project.id)"])
        return identities.contains(editor.editorIdentity) && editor.hasMarkedText()
    }
}

private struct ProjectTaskList: View {
    @ObservedObject var model: AppModel
    let project: Project
    @State private var topTaskID: String?
    @State private var interactiveFrames: [CGRect] = []
    @StateObject private var dragState = TaskDragState()

    init(model: AppModel, project: Project) {
        self.model = model
        self.project = project
        _topTaskID = State(initialValue: model.scrollAnchor(projectID: project.id))
    }

    var body: some View {
        let entries = model.taskListEntries(projectID: project.id)
        let shadedIDs = alternatingBackgroundTaskIDs(in: entries)
        ScrollView {
            // Eager rows retain the one expanded native editor when completion
            // moves it below a long list, even if its new position is offscreen.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { item in
                    switch item {
                    case .task(let task):
                        TaskRow(model: model, task: task, projectID: project.id, dragState: dragState)
                            .background(TaskInteractiveBounds())
                            .background {
                                if shadedIDs.contains(task.id) { TaskStripeBackground() }
                            }
                            .id(item.id)
                    case .addTask:
                        addTaskEntry
                            .background(TaskInteractiveBounds())
                            .padding(.horizontal, 11)
                            .id(item.id)
                    case .completedHeader(_, let count):
                        completedHeader(count: count)
                            .background(TaskInteractiveBounds())
                            .padding(.horizontal, 11)
                            .id(item.id)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.top, 7)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .coordinateSpace(name: "task-list-interaction")
        .onPreferenceChange(TaskInteractiveFrames.self) { interactiveFrames = $0 }
        .background {
            TaskBlankClickArea(excludedRects: interactiveFrames, onBlankClick: model.clearTaskSelection)
        }
        .scrollPosition(id: $topTaskID, anchor: .top)
        .disabled(!model.isSelectedListAvailable)
        .onDisappear { dragState.finish() }
        .onReceive(NotificationCenter.default.publisher(for: ListActions.focusEntry)) { notification in
            guard notification.object as? String == project.id else { return }
            topTaskID = model.taskListEntries(projectID: project.id).first {
                if case .addTask = $0 { return true }
                return false
            }?.id
            DispatchQueue.main.async { ListActions.focusEditor(identity: "add:\(project.id)") }
        }
        .onChange(of: topTaskID) { _, value in
            model.setScrollAnchor(projectID: project.id, taskID: value)
        }
        .onChange(of: editingTask?.completed) { old, new in
            guard old != nil, new != nil, let task = editingTask,
                  let editor = NSApp.keyWindow?.firstResponder as? PlainTextView else { return }
            let identities = ["\(task.id):title", "\(task.id):notes", "add-child:\(task.id)"]
                + task.subtasks.map { "\($0.id):title" }
            if identities.contains(editor.editorIdentity) { topTaskID = task.id }
        }
    }

    private var editingTask: TaskItem? {
        let taskID = model.selectedTaskID(projectID: project.id) ?? model.expandedTaskIDs[project.id]
        return project.tasks.first { $0.id == taskID }
    }

    private func alternatingBackgroundTaskIDs(in entries: [AppModel.TaskListEntry]) -> Set<String> {
        var shadedIDs = Set<String>()
        var taskIndex = 0
        for entry in entries {
            switch entry {
            case .task(let task):
                if taskIndex.isMultiple(of: 2) { shadedIDs.insert(task.id) }
                taskIndex += 1
            case .completedHeader:
                taskIndex = 0
            case .addTask:
                break
            }
        }
        return shadedIDs
    }

    private var entry: Binding<String> {
        Binding(get: { model.entryDrafts[project.id] ?? "" }, set: { model.entryDrafts[project.id] = $0 })
    }

    private var addTaskEntry: some View {
        HStack(alignment: .top, spacing: 3) {
            Image(systemName: "plus").font(.system(size: 14))
                .foregroundStyle(Mocha.secondary).frame(width: 22, height: 28)
            NativeTextEditor(text: entry, identity: "add:\(project.id)", placeholder: "Add a task…", submitOnReturn: true, onSubmit: {
                model.addTask(entry.wrappedValue)
            })
        }
        .disabled(!model.isSelectedListAvailable)
    }

    private func completedHeader(count: Int) -> some View {
        let expanded = model.isCompletedExpanded(projectID: project.id)
        return Button { model.toggleCompleted(projectID: project.id) } label: {
            HStack(spacing: 3) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 22, height: 26)
                Text("Completed").font(.system(size: 12))
                Text("\(count)").font(.system(size: 11)).padding(.leading, 2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Mocha.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityLabel("Completed tasks, \(count)")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint(expanded ? "Hide completed tasks" : "Show completed tasks")
    }
}

private struct TaskInteractiveFrames: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

private struct TaskInteractiveBounds: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: TaskInteractiveFrames.self,
                                   value: [geometry.frame(in: .named("task-list-interaction"))])
        }
    }
}

private struct TaskBarControlFrames: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

private struct TaskBarControlBounds: View {
    let taskID: String
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: TaskBarControlFrames.self,
                                   value: [geometry.frame(in: .named(taskID))])
        }
    }
}

private struct TaskRow: View {
    @ObservedObject var model: AppModel
    let task: TaskItem
    let projectID: String
    @ObservedObject var dragState: TaskDragState
    @State private var controlFrames: [CGRect] = []
    @State private var deadlineEditorPresented = false
    @State private var deadlineBase: TaskItem?
    @State private var deadlineDraft = Date()
    @State private var deadlineSaveError: String?
    private var expanded: Bool { model.expandedTaskID == task.id }
    private var selected: Bool { model.selectedTaskID(projectID: projectID) == task.id }
    private var overdue: Bool { model.isOverdue(task, projectID: projectID) }
    private var title: String { model.text(itemID: task.id, field: .title, fallback: task.title, projectID: projectID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 3) {
                CompletionButton(completed: task.completed, title: title) { model.toggleTask(task, projectID: projectID) }
                    .background(TaskBarControlBounds(taskID: task.id))
                NativeTextEditor(text: text(.title, task.title), identity: "\(task.id):title",
                    placeholder: expanded ? "" : "Untitled draft", completed: task.completed, submitOnReturn: true,
                    compactTrailingNewlines: !expanded && !selected,
                    deadlineActions: nativeDeadlineActions,
                    onTitlePointerDown: selectTitle, onTitleSingleClick: {
                        _ = model.clickSelectedTaskTitle(taskID: task.id, projectID: projectID)
                    }, onTitleFocus: {
                        model.selectTaskForEditing(taskID: task.id, projectID: projectID)
                    }, onSubmit: commit, onEndEditing: { _ = model.flushPendingEdits() }, onTextChange: { value, base in
                        model.setText(itemID: task.id, field: .title, value: value, expectedBase: base, projectID: projectID)
                    })
                if overdue {
                    Button(action: editDeadline) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Mocha.warning)
                            .frame(width: 22, height: Mocha.textRowHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(deadlineDescription)
                    .accessibilityLabel(deadlineDescription + ". Edit deadline")
                    .background(TaskBarControlBounds(taskID: task.id))
                }
                if selected || expanded || !task.notes.isEmpty || !task.subtasks.isEmpty || task.deadline != nil {
                    Button(action: toggleDetails) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Mocha.secondary)
                            .frame(width: 22, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? "Close task details" : "Open task details")
                    .accessibilityIdentifier("task-details:\(task.id)")
                    .background(TaskBarControlBounds(taskID: task.id))
                }
                taskGrip
                    .background(TaskBarControlBounds(taskID: task.id))
            }
            .frame(minHeight: 30, alignment: .top)
            if expanded {
                VStack(alignment: .leading, spacing: 1) {
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Enter a title to save, or delete this task.")
                            .font(.system(size: 11)).foregroundStyle(Mocha.blue)
                    }
                    ConflictChoices(model: model, itemID: task.id, projectID: projectID)
                        .background(TaskBarControlBounds(taskID: task.id))
                    if task.deadline != nil {
                        Button(action: editDeadline) {
                            Label(deadlineDescription, systemImage: overdue ? "exclamationmark.triangle.fill" : "calendar")
                                .font(.system(size: 11))
                                .foregroundStyle(overdue ? Mocha.warning : Mocha.secondary)
                                .multilineTextAlignment(.leading)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .help("Edit deadline")
                        .background(TaskBarControlBounds(taskID: task.id))
                    }
                    HStack(alignment: .top, spacing: 3) {
                        Image(systemName: "plus").font(.system(size: 13))
                            .foregroundStyle(Mocha.secondary).frame(width: 22, height: Mocha.textRowHeight)
                        NativeTextEditor(text: subtaskEntry, identity: "add-child:\(task.id)", placeholder: "Add subtask…", fontSize: 13, secondary: true, submitOnReturn: true, onSubmit: {
                            let value = subtaskEntry.wrappedValue
                            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            model.addSubtask(parentID: task.id, title: value, projectID: projectID)
                        })
                        Menu {
                            Button("Close details", action: toggleDetails)
                            deadlineMenu
                            if !task.subtasks.isEmpty {
                                Menu("Delete subtask") {
                                    ForEach(task.subtasks) { subtask in
                                        Button(subtask.title, role: .destructive) { model.deleteSubtask(subtask, projectID: projectID) }
                                    }
                                }
                            }
                            Button("Delete task", role: .destructive) { model.deleteTask(task, projectID: projectID) }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 20, height: Mocha.textRowHeight)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Task actions")
                    }
                    .background(TaskBarControlBounds(taskID: task.id))
                    ForEach(task.subtasks) { subtask in
                        SubtaskRow(model: model, subtask: subtask, projectID: projectID)
                            .background(TaskBarControlBounds(taskID: task.id))
                    }
                    NativeTextEditor(text: text(.notes, task.notes), identity: "\(task.id):notes", placeholder: "Add notes or a link…", fontSize: 13, secondary: true, links: true, deadlineActions: nativeDeadlineActions, onEndEditing: { _ = model.flushPendingEdits() }, onTextChange: { value, base in
                        model.setText(itemID: task.id, field: .notes, value: value, expectedBase: base, projectID: projectID)
                    })
                    .padding(.top, 3)
                }
                .padding(.leading, 25)
                .padding(.bottom, 5)
            }
        }
        .padding(.horizontal, 11)
        .background(overdue ? Mocha.overdueBackground : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5))
        .coordinateSpace(name: task.id)
        .onPreferenceChange(TaskBarControlFrames.self) { controlFrames = $0 }
        .background {
            TaskBarClickArea(taskID: task.id, excludedRects: controlFrames, onPointerDown: {
                let disposition = selectTitle()
                if disposition == .editOnly { ListActions.focusEditor(identity: "\(task.id):title") }
                return disposition
            }, onSingleClick: {
                if model.clickSelectedTaskTitle(taskID: task.id, projectID: projectID) {
                    ListActions.focusEditor(identity: "\(task.id):title")
                }
            })
        }
        .overlay {
            TaskDragHandle(model: model, state: dragState, task: task, projectID: projectID)
        }
        .overlay(alignment: .top) {
            if dragState.hoveredTarget == .before(task.id) { insertionIndicator }
        }
        .overlay(alignment: .bottom) {
            if dragState.hoveredTarget == .after(task.id) { insertionIndicator }
        }
        .contextMenu {
            Button(task.completed ? "Mark incomplete" : "Mark complete") { model.toggleTask(task, projectID: projectID) }
            Button(expanded ? "Close details" : "Edit task", action: toggleDetails)
            Divider()
            deadlineMenu
            Divider()
            Button("Move earlier") { _ = model.moveTask(task, projectID: projectID, offset: -1) }
                .disabled(!model.canMoveTask(task, projectID: projectID, offset: -1))
            Button("Move later") { _ = model.moveTask(task, projectID: projectID, offset: 1) }
                .disabled(!model.canMoveTask(task, projectID: projectID, offset: 1))
            Divider()
            Button("Delete task", role: .destructive) { model.deleteTask(task, projectID: projectID) }
        }
        .popover(isPresented: $deadlineEditorPresented, arrowEdge: .bottom) {
            deadlineEditor
        }
    }

    private var taskGrip: some View {
        VStack(spacing: 2) {
            ForEach(0..<3) { _ in
                HStack(spacing: 2) {
                    Circle().frame(width: 2, height: 2)
                    Circle().frame(width: 2, height: 2)
                }
            }
        }
        .foregroundStyle(Mocha.secondary.opacity(0.65))
        .frame(width: 16, height: 28)
        .contentShape(Rectangle())
        .overlay {
            TaskDragHandle(model: model, state: dragState, task: task, projectID: projectID, isSource: true)
        }
        .help("Drag to reorder task")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reorder \(title)")
        .accessibilityAction(named: "Move earlier") { _ = model.moveTask(task, projectID: projectID, offset: -1) }
        .accessibilityAction(named: "Move later") { _ = model.moveTask(task, projectID: projectID, offset: 1) }
    }

    private var insertionIndicator: some View {
        Rectangle().fill(Mocha.blue).frame(height: 2).padding(.horizontal, 11)
            .allowsHitTesting(false)
    }

    private var deadlineDescription: String {
        guard let deadline = task.deadline else { return "No deadline" }
        return "\(overdue ? "Overdue" : "Due") · \(deadline.formatted(date: .abbreviated, time: .shortened))"
    }

    private var nativeDeadlineActions: TaskDeadlineActions {
        TaskDeadlineActions(hasDeadline: task.deadline != nil, edit: editDeadline, remove: removeDeadline)
    }

    @ViewBuilder private var deadlineMenu: some View {
        Button(task.deadline == nil ? "Set deadline…" : "Edit deadline…", action: editDeadline)
        if task.deadline != nil { Button("Remove deadline", action: removeDeadline) }
    }

    private var deadlineEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(deadlineBase?.deadline == nil ? "Set deadline" : "Edit deadline")
                .font(.system(size: 13, weight: .semibold))
            DatePicker("Deadline", selection: $deadlineDraft, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.field)
                .accessibilityLabel("Deadline date and time")
            Text("Unfinished tasks stay highlighted once overdue.")
                .font(.system(size: 11)).foregroundStyle(Mocha.secondary)
            if let deadlineSaveError {
                Text(deadlineSaveError).font(.system(size: 11)).foregroundStyle(Mocha.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { deadlineEditorPresented = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    guard let deadlineBase else { return }
                    let date = Date(timeIntervalSince1970: floor(deadlineDraft.timeIntervalSince1970 / 60) * 60)
                    if model.setDeadline(date, for: deadlineBase, projectID: projectID) {
                        deadlineEditorPresented = false
                    } else {
                        deadlineSaveError = model.errorMessage ?? "Could not save the deadline. Close and reopen to try again."
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14).frame(width: 270)
        .foregroundStyle(Mocha.text)
        .preferredColorScheme(.dark)
    }

    private func editDeadline() {
        guard model.prepareDeadlineEditing(projectID: projectID) else { return }
        deadlineBase = task
        deadlineDraft = task.deadline ?? Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970 / 3600) * 3600)
        deadlineSaveError = nil
        deadlineEditorPresented = true
    }

    private func removeDeadline() {
        _ = model.setDeadline(nil, for: task, projectID: projectID)
    }

    private func text(_ field: AppModel.EditField, _ fallback: String) -> Binding<String> {
        Binding(get: { model.text(itemID: task.id, field: field, fallback: fallback, projectID: projectID) }, set: { model.setText(itemID: task.id, field: field, value: $0, projectID: projectID) })
    }
    private var subtaskEntry: Binding<String> {
        Binding(get: { model.subtaskEntry(parentID: task.id, projectID: projectID) }, set: { model.setSubtaskEntry(parentID: task.id, projectID: projectID, value: $0) })
    }
    private func commit() {
        if model.flushPendingEdits() { NSApp.keyWindow?.makeFirstResponder(nil) }
    }
    private func selectTitle() -> TitleClickDisposition {
        let wasSelected = selected
        guard model.selectTaskForEditing(taskID: task.id, projectID: projectID) else { return .reject }
        return wasSelected ? .toggleDetails : .editOnly
    }
    private func toggleDetails() {
        guard model.toggleDetails(taskID: task.id) else { return }
        DispatchQueue.main.async { ListActions.focusEditor(identity: "\(task.id):title") }
    }
}

private struct SubtaskRow: View {
    @ObservedObject var model: AppModel
    let subtask: Subtask
    let projectID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: 3) {
                CompletionButton(completed: subtask.completed, title: subtask.title) { model.toggleSubtask(subtask, projectID: projectID) }
                NativeTextEditor(text: Binding(get: {
                    model.text(itemID: subtask.id, field: .subtaskTitle, fallback: subtask.title, projectID: projectID)
                }, set: { model.setText(itemID: subtask.id, field: .subtaskTitle, value: $0, projectID: projectID) }), identity: "\(subtask.id):title", placeholder: "Subtask title", fontSize: 13, secondary: true, completed: subtask.completed, submitOnReturn: true, onSubmit: {
                    if model.flushPendingEdits() { NSApp.keyWindow?.makeFirstResponder(nil) }
                }, onEndEditing: { _ = model.flushPendingEdits() }, onTextChange: { value, base in
                    model.setText(itemID: subtask.id, field: .subtaskTitle, value: value, expectedBase: base, projectID: projectID)
                })
            }
            ConflictChoices(model: model, itemID: subtask.id, projectID: projectID)
        }
        .contextMenu {
            Button(subtask.completed ? "Mark incomplete" : "Mark complete") { model.toggleSubtask(subtask, projectID: projectID) }
            Button("Delete subtask", role: .destructive) { model.deleteSubtask(subtask, projectID: projectID) }
        }
    }
}

private struct ConflictChoices: View {
    @ObservedObject var model: AppModel
    let itemID: String
    let projectID: String
    var body: some View {
        ForEach(model.conflicts(itemID: itemID, projectID: projectID)) { conflict in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(conflict.field == .notes ? "Notes" : "Title") changed elsewhere")
                    .fontWeight(.medium)
                Text("Your draft: \(conflict.localValue)").textSelection(.enabled)
                Text("Updated: \(conflict.remoteValue)").textSelection(.enabled)
                HStack {
                    Button("Keep mine") { model.resolveConflict(id: conflict.id, keepMine: true) }
                    Button("Use updated") { model.resolveConflict(id: conflict.id, keepMine: false) }
                }
            }
            .font(.system(size: 11))
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Mocha.hover, in: RoundedRectangle(cornerRadius: 5))
        }
    }
}

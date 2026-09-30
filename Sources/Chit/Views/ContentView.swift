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
        VStack(spacing: 0) {
            ProjectStrip(model: model, onNewList: { groupID in
                newListGroupID = groupID
                newListPresented = true
            })
                .padding(.horizontal, 2)
                .padding(.vertical, 5)
            Rectangle().fill(Mocha.secondary.opacity(0.13)).frame(height: 1)
                .padding(.horizontal, 10)
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
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.isStoreAvailable ? "A little space for your next task." : "Your lists could not be loaded. Retry or restore a backup above.")
                        .font(.system(size: 13)).foregroundStyle(Mocha.secondary)
                    if model.isStoreAvailable {
                        HStack(spacing: 10) {
                            Button("New List…") { newListGroupID = nil; newListPresented = true }
                            Button("Open List…") { ListActions.open(model: model) }
                        }
                        .font(.system(size: 12))
                    }
                }
                .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .foregroundStyle(Mocha.text)
        .tint(Mocha.blue)
        .preferredColorScheme(.dark)
        .frame(minWidth: 300, minHeight: 180)
        .onReceive(NotificationCenter.default.publisher(for: NSText.didChangeNotification)) { _ in
            compositionInProgress = selectedEditorHasMarkedText
        }
        .onReceive(NotificationCenter.default.publisher(for: NSText.didEndEditingNotification)) { _ in
            compositionInProgress = selectedEditorHasMarkedText
        }
        .sheet(isPresented: $newListPresented) {
            NewListForm(model: model, groupID: newListGroupID) { newListPresented = false }
        }
        .onChange(of: model.errorMessage, initial: true) { _, _ in refreshRecoveryBackups() }
        .onChange(of: model.selectedProjectID) { _, _ in refreshRecoveryBackups() }
        .onChange(of: model.selectedListIssue) { _, _ in refreshRecoveryBackups() }
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
        recoveryBackups = model.errorMessage != nil || model.selectedListIssue != nil
            ? model.availableBackups(listID: recoveryListID) : []
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

    init(model: AppModel, project: Project) {
        self.model = model
        self.project = project
        _topTaskID = State(initialValue: model.scrollAnchor(projectID: project.id))
    }

    var body: some View {
        ScrollView {
            // Eager rows retain the one expanded native editor when completion
            // moves it below a long list, even if its new position is offscreen.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.taskListEntries(projectID: project.id)) { item in
                    switch item {
                    case .task(let task):
                        TaskRow(model: model, task: task, projectID: project.id)
                            .id(item.id)
                    case .addTask:
                        addTaskEntry
                            .id(item.id)
                    case .completedHeader(_, let count):
                        completedHeader(count: count)
                            .id(item.id)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 11)
            .padding(.top, 7)
            .padding(.bottom, 10)
        }
        .scrollPosition(id: $topTaskID, anchor: .top)
        .disabled(!model.isSelectedListAvailable)
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
        .onChange(of: expandedTask?.completed) { old, new in
            guard old != nil, new != nil, let task = expandedTask,
                  let editor = NSApp.keyWindow?.firstResponder as? PlainTextView else { return }
            let identities = ["\(task.id):title", "\(task.id):notes", "add-child:\(task.id)"]
                + task.subtasks.map { "\($0.id):title" }
            if identities.contains(editor.editorIdentity) { topTaskID = task.id }
        }
    }

    private var expandedTask: TaskItem? {
        project.tasks.first { $0.id == model.expandedTaskID }
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
        .padding(.top, 1)
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

private struct TaskRow: View {
    @ObservedObject var model: AppModel
    let task: TaskItem
    let projectID: String
    private var expanded: Bool { model.expandedTaskID == task.id }
    private var title: String { model.text(itemID: task.id, field: .title, fallback: task.title, projectID: projectID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 3) {
                CompletionButton(completed: task.completed, title: title) { model.toggleTask(task, projectID: projectID) }
                if expanded {
                    NativeTextEditor(text: text(.title, task.title), identity: "\(task.id):title", completed: task.completed, submitOnReturn: true, onSubmit: commit, onEndEditing: { _ = model.flushPendingEdits() }, onTextChange: { value, base in
                        model.setText(itemID: task.id, field: .title, value: value, expectedBase: base, projectID: projectID)
                    })
                } else {
                    Button { model.toggleDetails(taskID: task.id) } label: {
                        Text(title.isEmpty ? "Untitled draft" : title)
                            .font(.system(size: 14))
                            .foregroundStyle(task.completed ? Mocha.secondary : Mocha.text)
                            .strikethrough(task.completed)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(title)")
                }
                if expanded || !task.notes.isEmpty || !task.subtasks.isEmpty {
                    Button { model.toggleDetails(taskID: task.id) } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Mocha.secondary)
                            .frame(width: 22, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? "Close task details" : "Open task details")
                }
            }
            .frame(minHeight: 30, alignment: .top)
            if expanded {
                VStack(alignment: .leading, spacing: 1) {
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Enter a title to save, or delete this task.")
                            .font(.system(size: 11)).foregroundStyle(Mocha.blue)
                    }
                    ConflictChoices(model: model, itemID: task.id, projectID: projectID)
                    NativeTextEditor(text: text(.notes, task.notes), identity: "\(task.id):notes", placeholder: "Add notes or a link…", fontSize: 13, secondary: true, links: true, onEndEditing: { _ = model.flushPendingEdits() }, onTextChange: { value, base in
                        model.setText(itemID: task.id, field: .notes, value: value, expectedBase: base, projectID: projectID)
                    })
                        .padding(.bottom, task.subtasks.isEmpty ? 0 : 3)
                    ForEach(task.subtasks) { subtask in
                        SubtaskRow(model: model, subtask: subtask, projectID: projectID)
                    }
                    HStack(alignment: .top, spacing: 3) {
                        Image(systemName: "plus").font(.system(size: 13))
                            .foregroundStyle(Mocha.secondary).frame(width: 22, height: 26)
                        NativeTextEditor(text: subtaskEntry, identity: "add-child:\(task.id)", placeholder: "Add subtask…", fontSize: 13, secondary: true, submitOnReturn: true, onSubmit: {
                            let value = subtaskEntry.wrappedValue
                            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            model.addSubtask(parentID: task.id, title: value, projectID: projectID)
                        })
                        Menu {
                            Button("Close details") { model.toggleDetails(taskID: task.id) }
                            if !task.subtasks.isEmpty {
                                Menu("Delete subtask") {
                                    ForEach(task.subtasks) { subtask in
                                        Button(subtask.title, role: .destructive) { model.deleteSubtask(subtask, projectID: projectID) }
                                    }
                                }
                            }
                            Button("Delete task", role: .destructive) { model.deleteTask(task, projectID: projectID) }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 20, height: 26)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Task actions")
                    }
                }
                .padding(.leading, 25)
                .padding(.bottom, 5)
            }
        }
        .contextMenu {
            Button(task.completed ? "Mark incomplete" : "Mark complete") { model.toggleTask(task, projectID: projectID) }
            Button(expanded ? "Close details" : "Edit task") { model.toggleDetails(taskID: task.id) }
            Divider()
            Button("Delete task", role: .destructive) { model.deleteTask(task, projectID: projectID) }
        }
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

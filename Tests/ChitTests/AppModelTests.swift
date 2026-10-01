import Combine
import Foundation
import XCTest
@testable import TodoCore
@testable import Chit

@MainActor
final class AppModelTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let store: TodoStore
        let external: TodoStore
        let preferences: UserDefaults
        let preferencesSuite: String
        let model: AppModel
        let projectID: String
        let task: TaskItem
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try body(fixture)
    }

    private func makeFixture(watchChanges: Bool = false) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ChitModelTests-\(UUID().uuidString)", isDirectory: true)
        let dataDirectory = root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let suite = "ChitModelTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = TodoStore(url: dataDirectory.appendingPathComponent("workspace.json"))
        let projectID = try XCTUnwrap(store.load().projects.first?.id)
        let task = TaskItem(title: "Original title", notes: "Original notes", subtasks: [Subtask(title: "Child")])
        _ = try store.apply(.addTask(projectID: projectID, task: task, index: nil))
        let model = AppModel(store: store, preferences: preferences, watchChanges: watchChanges)
        return Fixture(root: root, store: store, external: TodoStore(url: store.url), preferences: preferences,
                       preferencesSuite: suite, model: model, projectID: projectID, task: task)
    }

    private func cleanUp(_ fixture: Fixture) {
        fixture.preferences.removePersistentDomain(forName: fixture.preferencesSuite)
        try? FileManager.default.removeItem(at: fixture.root)
    }

    private func storedTask(_ fixture: Fixture) throws -> TaskItem {
        try XCTUnwrap(fixture.store.load().projects.flatMap(\.tasks).first { $0.id == fixture.task.id })
    }

    private func draft(_ fixture: Fixture, field: AppModel.EditField = .title) -> String {
        fixture.model.text(itemID: fixture.task.id, field: field, fallback: "No draft")
    }

    func testDeadlineSetClearAndRelaunchPreserveStoredValue() throws {
        try withFixture { f in
            let deadline = Date(timeIntervalSince1970: 1_800_000_000)
            XCTAssertTrue(f.model.setDeadline(deadline, for: f.task, projectID: f.projectID))
            XCTAssertEqual(try storedTask(f).deadline, deadline)

            let reopened = AppModel(store: f.store, preferences: f.preferences, watchChanges: false)
            let saved = try XCTUnwrap(reopened.selectedProject?.tasks.first { $0.id == f.task.id })
            XCTAssertEqual(saved.deadline, deadline)
            XCTAssertTrue(reopened.setDeadline(nil, for: saved, projectID: f.projectID))
            XCTAssertNil(try storedTask(f).deadline)
            XCTAssertFalse(reopened.hasOverdueTasks(projectID: f.projectID))
        }
    }

    func testDeadlineUndoAndRedoPreserveUnrelatedExternalEdits() throws {
        try withFixture { f in
            let deadline = Date(timeIntervalSince1970: 1_800_000_000)
            XCTAssertTrue(f.model.setDeadline(deadline, for: f.task, projectID: f.projectID))
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(
                notes: FieldChange(expected: f.task.notes, value: "Agent notes"),
                completed: FieldChange(expected: false, value: true))))

            f.model.undo()
            var saved = try storedTask(f)
            XCTAssertNil(saved.deadline)
            XCTAssertEqual(saved.notes, "Agent notes")
            XCTAssertTrue(saved.completed)

            f.model.redo()
            saved = try storedTask(f)
            XCTAssertEqual(saved.deadline, deadline)
            XCTAssertEqual(saved.notes, "Agent notes")
            XCTAssertTrue(saved.completed)
        }
    }

    func testDeadlineRejectsConcurrentSetAndClearAfterModelRefresh() throws {
        try withFixture { f in
            let first = Date(timeIntervalSince1970: 1_800_000_000)
            let second = first.addingTimeInterval(60)
            let proposed = first.addingTimeInterval(120)
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(deadline: FieldChange(expected: nil, value: first))))
            f.model.refresh()
            XCTAssertFalse(f.model.setDeadline(proposed, for: f.task, projectID: f.projectID))
            XCTAssertEqual(try storedTask(f).deadline, first)
            XCTAssertNotNil(f.model.errorMessage)

            let captured = try storedTask(f)
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(deadline: FieldChange(expected: first, value: second))))
            f.model.refresh()
            XCTAssertFalse(f.model.setDeadline(nil, for: captured, projectID: f.projectID))
            XCTAssertEqual(try storedTask(f).deadline, second)
            XCTAssertNotNil(f.model.errorMessage)
        }
    }

    func testDeadlineStatusChangesOnlyAtBoundaryAndCompletionOrReopen() throws {
        try withFixture { f in
            let deadline = Date().addingTimeInterval(-60)
            XCTAssertTrue(f.model.setDeadline(deadline, for: f.task, projectID: f.projectID))
            let saved = try storedTask(f)
            f.model.updateDeadlineStatus(at: deadline.addingTimeInterval(-1))
            XCTAssertFalse(f.model.isOverdue(saved, projectID: f.projectID))

            var publications = 0
            let observation = f.model.objectWillChange.sink { _ in publications += 1 }
            f.model.updateDeadlineStatus(at: deadline.addingTimeInterval(1))
            XCTAssertTrue(f.model.isOverdue(saved, projectID: f.projectID))
            XCTAssertTrue(f.model.hasOverdueTasks(projectID: f.projectID))
            XCTAssertEqual(publications, 1)
            f.model.updateDeadlineStatus(at: deadline.addingTimeInterval(2))
            XCTAssertEqual(publications, 1, "An unchanged clock tick must not refresh active text editors.")
            f.model.updateDeadlineStatus(at: deadline.addingTimeInterval(-1))
            XCTAssertFalse(f.model.hasOverdueTasks(projectID: f.projectID), "Moving the clock backward recalculates overdue state.")
            XCTAssertEqual(publications, 2)
            observation.cancel()

            f.model.toggleTask(saved, projectID: f.projectID)
            let completed = try storedTask(f)
            XCTAssertEqual(completed.deadline, deadline)
            XCTAssertFalse(f.model.hasOverdueTasks(projectID: f.projectID))
            f.model.toggleTask(completed, projectID: f.projectID)
            XCTAssertTrue(f.model.hasOverdueTasks(projectID: f.projectID))
            XCTAssertEqual(try storedTask(f).deadline, deadline)
        }
    }

    func testDeadlineStatusKeepsListsIndependentAndSuppressesUnavailableData() throws {
        try withFixture { f in
            let past = Date().addingTimeInterval(-3600)
            let future = Date().addingTimeInterval(3600)
            XCTAssertTrue(f.model.setDeadline(past, for: f.task, projectID: f.projectID))
            XCTAssertTrue(f.model.createList(name: "Other list"))
            let otherID = f.model.selectedProjectID
            f.model.addTask("Future deadline")
            let otherTask = try XCTUnwrap(f.model.selectedProject?.tasks.first)
            XCTAssertTrue(f.model.setDeadline(future, for: otherTask, projectID: otherID))
            XCTAssertTrue(f.model.hasOverdueTasks(projectID: f.projectID))
            XCTAssertFalse(f.model.hasOverdueTasks(projectID: otherID))
            XCTAssertFalse(f.model.isOverdue(f.task, projectID: otherID))

            let deadlineTask = try storedTask(f)
            let listURL = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            let bytes = try Data(contentsOf: listURL)
            try FileManager.default.removeItem(at: listURL)
            f.model.refresh()
            XCTAssertFalse(f.model.hasOverdueTasks(projectID: f.projectID))
            XCTAssertFalse(f.model.isOverdue(f.task, projectID: f.projectID))
            XCTAssertFalse(f.model.setDeadline(nil, for: deadlineTask, projectID: f.projectID))
            try bytes.write(to: listURL)
            f.model.refresh()
            XCTAssertTrue(f.model.hasOverdueTasks(projectID: f.projectID))

            try Data("{invalid catalog".utf8).write(to: f.store.catalogURL)
            f.model.refresh()
            XCTAssertFalse(f.model.isStoreAvailable)
            XCTAssertFalse(f.model.hasOverdueTasks(projectID: f.projectID))
            XCTAssertFalse(f.model.isOverdue(f.task, projectID: f.projectID))
        }
    }

    func testDeadlineClockMarksTaskOverdueWithoutRefresh() async throws {
        let f = try makeFixture(watchChanges: true)
        defer { cleanUp(f) }
        XCTAssertTrue(f.model.setDeadline(Date().addingTimeInterval(0.75), for: f.task, projectID: f.projectID))
        XCTAssertFalse(f.model.hasOverdueTasks(projectID: f.projectID))
        let timeout = Date().addingTimeInterval(3)
        while !f.model.hasOverdueTasks(projectID: f.projectID), Date() < timeout {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(f.model.hasOverdueTasks(projectID: f.projectID))
    }

    func testDeadlinePreparationIgnoresOtherListInvalidAndConflictingDrafts() throws {
        try withFixture { f in
            XCTAssertTrue(f.model.createList(name: "Healthy"))
            let healthyID = f.model.selectedProjectID
            f.model.addTask("Healthy task")
            let healthyTask = try XCTUnwrap(f.model.selectedProject?.tasks.first)
            f.model.setText(itemID: f.task.id, field: .title, value: "", projectID: f.projectID)
            f.model.setText(itemID: healthyTask.id, field: .notes, value: "Healthy notes", projectID: healthyID)

            XCTAssertTrue(f.model.prepareDeadlineEditing(projectID: healthyID))
            XCTAssertEqual(f.model.selectedProject?.tasks.first?.notes, "Healthy notes")
            XCTAssertEqual(f.model.text(itemID: f.task.id, field: .title, fallback: "No draft", projectID: f.projectID), "")
            XCTAssertEqual(try storedTask(f).title, f.task.title)

            f.model.setText(itemID: f.task.id, field: .title, value: "Retained local title", projectID: f.projectID)
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(title: FieldChange(expected: f.task.title, value: "External title"))))
            f.model.refresh()
            XCTAssertFalse(f.model.conflicts(itemID: f.task.id, projectID: f.projectID).isEmpty)

            XCTAssertTrue(f.model.prepareDeadlineEditing(projectID: healthyID))
            XCTAssertEqual(f.model.text(itemID: f.task.id, field: .title, fallback: "No draft", projectID: f.projectID), "Retained local title")
            XCTAssertFalse(f.model.conflicts(itemID: f.task.id, projectID: f.projectID).isEmpty)
            XCTAssertEqual(try storedTask(f).title, "External title")
        }
    }

    func testDeadlinePreparationAllowsHealthyListWhileOtherDraftIsUnavailable() throws {
        try withFixture { f in
            XCTAssertTrue(f.model.createList(name: "Healthy"))
            let healthyID = f.model.selectedProjectID
            f.model.addTask("Healthy task")
            let healthyTask = try XCTUnwrap(f.model.selectedProject?.tasks.first)
            f.model.setText(itemID: f.task.id, field: .notes, value: "Retained missing-list notes", projectID: f.projectID)
            let missingURL = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            try FileManager.default.removeItem(at: missingURL)
            f.model.refresh()
            XCTAssertTrue(f.model.hasRetainedDrafts(listID: f.projectID))

            XCTAssertTrue(f.model.prepareDeadlineEditing(projectID: healthyID))
            XCTAssertTrue(f.model.setDeadline(Date(timeIntervalSince1970: 1_800_000_000), for: healthyTask, projectID: healthyID))
            XCTAssertFalse(f.model.prepareDeadlineEditing(projectID: f.projectID))
            XCTAssertFalse(f.model.prepareDeadlineEditing(projectID: "missing-project"))
            XCTAssertEqual(f.model.text(itemID: f.task.id, field: .notes, fallback: "No draft", projectID: f.projectID), "Retained missing-list notes")
            XCTAssertTrue(f.model.hasRetainedDrafts(listID: f.projectID))
            XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))

            try Data("{invalid catalog".utf8).write(to: f.store.catalogURL)
            f.model.refresh()
            XCTAssertFalse(f.model.prepareDeadlineEditing(projectID: healthyID))
        }
    }

    func testDeadlinePreparationRejectsAndPreservesInvalidTargetDraft() throws {
        try withFixture { f in
            XCTAssertTrue(f.model.selectTaskForEditing(taskID: f.task.id, projectID: f.projectID))
            XCTAssertTrue(f.model.toggleDetails(taskID: f.task.id))
            f.model.setText(itemID: f.task.id, field: .title, value: "", projectID: f.projectID)

            XCTAssertFalse(f.model.prepareDeadlineEditing(projectID: f.projectID))
            XCTAssertEqual(draft(f), "")
            XCTAssertEqual(try storedTask(f).title, f.task.title)
            XCTAssertEqual(f.model.selectedTaskID, f.task.id)
            XCTAssertEqual(f.model.expandedTaskID, f.task.id)
            XCTAssertNotNil(f.model.errorMessage)

            f.model.setText(itemID: f.task.id, field: .title, value: "Corrected title", projectID: f.projectID)
            XCTAssertTrue(f.model.prepareDeadlineEditing(projectID: f.projectID))
            XCTAssertEqual(try storedTask(f).title, "Corrected title")
            XCTAssertEqual(f.model.selectedTaskID, f.task.id)
            XCTAssertEqual(f.model.expandedTaskID, f.task.id)
        }
    }

    func testRefreshPreservesDirtyTitleWhileExternalWriterAddsAndCompletes() throws {
        try withFixture { f in
            f.model.setText(itemID: f.task.id, field: .title, value: "Local typing")
            let added = TaskItem(title: "Agent-added task")
            _ = try f.external.apply(.batch([
                .addTask(projectID: f.projectID, task: added, index: nil),
                .patchTask(id: f.task.id, patch: TaskPatch(completed: FieldChange(expected: false, value: true)))
            ]))
            f.model.refresh()

            XCTAssertEqual(draft(f), "Local typing")
            XCTAssertTrue(try XCTUnwrap(f.model.selectedProject?.tasks.first { $0.id == f.task.id }).completed)
            XCTAssertTrue(f.model.selectedProject?.tasks.contains { $0.id == added.id } == true)
            XCTAssertTrue(f.model.conflicts(itemID: f.task.id).isEmpty)
            XCTAssertTrue(f.model.flushPendingEdits())
            let saved = try storedTask(f)
            XCTAssertEqual(saved.title, "Local typing")
            XCTAssertTrue(saved.completed)
            XCTAssertTrue(try f.store.load().projects.flatMap(\.tasks).contains { $0.id == added.id })
        }
    }

    func testSeparateTextFieldsMergeWithoutRefreshBeforeSave() throws {
        try withFixture { f in
            f.model.setText(itemID: f.task.id, field: .notes, value: "Local notes\nhttps://example.com/plain")
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(title: FieldChange(expected: f.task.title, value: "Agent title"))))

            XCTAssertTrue(f.model.flushPendingEdits())
            let saved = try storedTask(f)
            XCTAssertEqual(saved.title, "Agent title")
            XCTAssertEqual(saved.notes, "Local notes\nhttps://example.com/plain")
            XCTAssertTrue(f.model.conflicts(itemID: f.task.id).isEmpty)
        }
    }

    func testEditorExpectedBasePreservesIMECommitAcrossRemoteRefresh() throws {
        try withFixture { f in
            // The editor began composing against A, without publishing marked text.
            let editorBase = f.task.title
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(title: FieldChange(expected: editorBase, value: "Remote C"))))
            f.model.refresh()

            // Composition commits B after the model has already adopted remote C.
            f.model.setText(itemID: f.task.id, field: .title, value: "Composed B", expectedBase: editorBase)

            XCTAssertEqual(draft(f), "Composed B")
            let conflict = try XCTUnwrap(f.model.conflicts(itemID: f.task.id).first)
            XCTAssertEqual(conflict.localValue, "Composed B")
            XCTAssertEqual(conflict.remoteValue, "Remote C")
            XCTAssertFalse(f.model.flushPendingEdits())
            XCTAssertEqual(try storedTask(f).title, "Remote C")
        }
    }

    func testRealDirectoryWatcherAdoptsExternalChangeAndRetainsBlankDraft() async throws {
        let f = try makeFixture(watchChanges: true)
        defer { cleanUp(f) }
        f.model.setText(itemID: f.task.id, field: .title, value: "")
        let added = TaskItem(title: "Added by external process")
        _ = try f.external.apply(.batch([
            .addTask(projectID: f.projectID, task: added, index: nil),
            .patchTask(id: f.task.id, patch: TaskPatch(completed: FieldChange(expected: false, value: true)))
        ]))

        // Yield the main actor so DispatchSource delivery can trigger a real reload.
        let deadline = Date().addingTimeInterval(4)
        while !(f.model.selectedProject?.tasks.contains { $0.id == added.id } ?? false), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(f.model.selectedProject?.tasks.contains { $0.id == added.id } == true)
        XCTAssertTrue(try XCTUnwrap(f.model.selectedProject?.tasks.first { $0.id == f.task.id }).completed)
        XCTAssertEqual(draft(f), "")
        XCTAssertFalse(f.model.flushPendingEdits())
        XCTAssertEqual(try storedTask(f).title, f.task.title)
    }

    func testSameFieldConflictKeepsLocalDraftAndRemoteStoredValue() throws {
        try withFixture { f in
            f.model.setText(itemID: f.task.id, field: .title, value: "My title")
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(title: FieldChange(expected: f.task.title, value: "Agent title"))))
            f.model.refresh()

            XCTAssertFalse(f.model.flushPendingEdits())
            XCTAssertEqual(draft(f), "My title")
            XCTAssertEqual(try storedTask(f).title, "Agent title")
            let conflict = try XCTUnwrap(f.model.conflicts(itemID: f.task.id).first)
            XCTAssertEqual(conflict.field, .title)
            XCTAssertEqual(conflict.localValue, "My title")
            XCTAssertEqual(conflict.remoteValue, "Agent title")
        }
    }

    func testKeepMineResolvesConflictAndPreservesUnrelatedExternalChange() throws {
        try withFixture { f in
            f.model.setText(itemID: f.task.id, field: .title, value: "My title")
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(title: FieldChange(expected: f.task.title, value: "Agent title"))))
            f.model.refresh()
            let conflict = try XCTUnwrap(f.model.conflicts(itemID: f.task.id).first)
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(completed: FieldChange(expected: false, value: true))))

            f.model.resolveConflict(id: conflict.id, keepMine: true)

            XCTAssertTrue(f.model.flushPendingEdits())
            XCTAssertEqual(try storedTask(f).title, "My title")
            XCTAssertTrue(try storedTask(f).completed)
            XCTAssertTrue(f.model.conflicts(itemID: f.task.id).isEmpty)
        }
    }

    func testUseUpdatedResolvesConflictWithoutWritingLocalDraft() throws {
        try withFixture { f in
            f.model.setText(itemID: f.task.id, field: .notes, value: "My notes")
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(notes: FieldChange(expected: f.task.notes, value: "Agent notes"))))
            f.model.refresh()
            let conflict = try XCTUnwrap(f.model.conflicts(itemID: f.task.id).first)

            f.model.resolveConflict(id: conflict.id, keepMine: false)

            XCTAssertTrue(f.model.flushPendingEdits())
            XCTAssertEqual(f.model.text(itemID: f.task.id, field: .notes, fallback: "Agent notes"), "Agent notes")
            XCTAssertEqual(try storedTask(f).notes, "Agent notes")
            XCTAssertTrue(f.model.conflicts(itemID: f.task.id).isEmpty)
        }
    }

    func testKeepMineRechecksRemoteValueBeforeOverwriting() throws {
        try withFixture { f in
            f.model.setText(itemID: f.task.id, field: .title, value: "My title")
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(title: FieldChange(expected: f.task.title, value: "Agent version one"))))
            f.model.refresh()
            let conflict = try XCTUnwrap(f.model.conflicts(itemID: f.task.id).first)
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(title: FieldChange(expected: "Agent version one", value: "Agent version two"))))

            f.model.resolveConflict(id: conflict.id, keepMine: true)

            XCTAssertEqual(try storedTask(f).title, "Agent version two", "The unseen second edit must receive a new conflict decision.")
            XCTAssertEqual(draft(f), "My title")
            XCTAssertEqual(f.model.conflicts(itemID: f.task.id).first?.remoteValue, "Agent version two")
            XCTAssertFalse(f.model.flushPendingEdits())
        }
    }

    func testUndoAndRedoPreserveAgentAddedTasks() throws {
        try withFixture { f in
            f.model.addTask("My new task")
            let localID = try XCTUnwrap(f.model.selectedProject?.tasks.first { $0.title == "My new task" }?.id)
            let added = TaskItem(title: "Agent-added task")
            _ = try f.external.apply(.addTask(projectID: f.projectID, task: added, index: nil))
            f.model.refresh()

            f.model.undo()
            let afterUndo = try f.store.load().projects.flatMap(\.tasks)
            XCTAssertFalse(afterUndo.contains { $0.id == localID })
            XCTAssertTrue(afterUndo.contains { $0.id == added.id })
            XCTAssertTrue(f.model.canRedo)

            f.model.redo()
            let afterRedo = try f.store.load().projects.flatMap(\.tasks)
            XCTAssertTrue(afterRedo.contains { $0.id == localID })
            XCTAssertTrue(afterRedo.contains { $0.id == added.id })
        }
    }

    func testUndoTextEditPreservesExternalCompletion() throws {
        try withFixture { f in
            f.model.setText(itemID: f.task.id, field: .notes, value: "My notes")
            XCTAssertTrue(f.model.flushPendingEdits())
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(completed: FieldChange(expected: false, value: true))))

            f.model.undo()

            XCTAssertEqual(try storedTask(f).notes, f.task.notes)
            XCTAssertTrue(try storedTask(f).completed)
        }
    }

    func testUndoRejectsConflictingExternalTextInsteadOfOverwritingIt() throws {
        try withFixture { f in
            f.model.setText(itemID: f.task.id, field: .title, value: "My saved title")
            XCTAssertTrue(f.model.flushPendingEdits())
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(title: FieldChange(expected: "My saved title", value: "Agent newest title"))))

            f.model.undo()

            XCTAssertEqual(try storedTask(f).title, "Agent newest title")
            XCTAssertNotNil(f.model.errorMessage)
        }
    }

    func testUndoDeletionRestoresParentAndChildrenAlongsideAgentAddition() throws {
        try withFixture { f in
            f.model.deleteTask(f.task)
            let added = TaskItem(title: "Agent addition after deletion")
            _ = try f.external.apply(.addTask(projectID: f.projectID, task: added, index: nil))

            f.model.undo()

            XCTAssertEqual(try storedTask(f), f.task)
            XCTAssertTrue(try f.store.load().projects.flatMap(\.tasks).contains { $0.id == added.id })
        }
    }

    func testCollapsedCurrentGroupPreservesSelectionExpansionAndDraft() throws {
        try withFixture { f in
            let group = ProjectGroup(name: "Work")
            _ = try f.external.apply(.batch([
                .addGroup(group: group, index: nil),
                .patchProject(id: f.projectID, name: nil, groupID: FieldChange(expected: nil, value: group.id))
            ]))
            f.model.refresh()
            f.model.toggleDetails(taskID: f.task.id)
            f.model.setText(itemID: f.task.id, field: .title, value: "Still typing")

            f.model.toggleGroup(group.id)

            XCTAssertTrue(f.model.collapsedGroupIDs.contains(group.id))
            XCTAssertEqual(f.model.selectedProjectID, f.projectID)
            XCTAssertEqual(f.model.expandedTaskID, f.task.id)
            XCTAssertEqual(draft(f), "Still typing")
            XCTAssertEqual(f.model.selectedProject?.groupID, group.id)
        }
    }

    func testProjectSwitchRetainsOneExpandedTaskPerProjectAndUnsavedBlankDraft() throws {
        try withFixture { f in
            let otherTask = TaskItem(title: "Other task")
            let other = Project(name: "Other", tasks: [otherTask])
            _ = try f.external.apply(.addProject(project: other, index: nil))
            f.model.refresh()
            f.model.toggleDetails(taskID: f.task.id)
            f.model.setText(itemID: f.task.id, field: .title, value: "   ")

            f.model.selectProject(other.id)
            f.model.toggleDetails(taskID: otherTask.id)
            XCTAssertEqual(f.model.expandedTaskID, otherTask.id)
            f.model.selectProject(f.projectID)

            XCTAssertEqual(f.model.expandedTaskID, f.task.id)
            XCTAssertEqual(draft(f), "   ")
            XCTAssertFalse(f.model.flushPendingEdits())
            XCTAssertEqual(try storedTask(f), f.task)
        }
    }

    func testNavigationAndUnsavedDraftAreRestoredFromLocalPreferences() throws {
        try withFixture { f in
            let group = ProjectGroup(name: "Work")
            let otherTask = TaskItem(title: "Other task")
            let other = Project(name: "Other", groupID: group.id, tasks: [otherTask])
            _ = try f.external.apply(.batch([
                .addGroup(group: group, index: nil),
                .addProject(project: other, index: nil)
            ]))
            f.model.refresh()
            f.model.selectProject(other.id)
            f.model.toggleDetails(taskID: otherTask.id)
            f.model.toggleGroup(group.id)
            f.model.entryDrafts[other.id] = "Unsubmitted addition"
            f.model.setText(itemID: otherTask.id, field: .title, value: "")

            let reopened = AppModel(store: f.store, preferences: f.preferences, watchChanges: false)

            XCTAssertEqual(reopened.selectedProjectID, other.id)
            XCTAssertEqual(reopened.expandedTaskID, otherTask.id)
            XCTAssertTrue(reopened.collapsedGroupIDs.contains(group.id))
            XCTAssertEqual(reopened.entryDrafts[other.id], "Unsubmitted addition")
            XCTAssertEqual(reopened.text(itemID: otherTask.id, field: .title, fallback: otherTask.title), "")
            XCTAssertFalse(reopened.flushPendingEdits())
            XCTAssertEqual(try f.store.load().projects.first { $0.id == other.id }?.tasks.first?.title, otherTask.title)
        }
    }

    func testUnsubmittedTaskAndSubtaskEntriesSurviveExternalRefresh() throws {
        try withFixture { f in
            f.model.entryDrafts[f.projectID] = "New task being composed"
            f.model.setSubtaskEntry(parentID: f.task.id, projectID: f.projectID, value: "New child being composed")
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(completed: FieldChange(expected: false, value: true))))

            f.model.refresh()

            XCTAssertEqual(f.model.entryDrafts[f.projectID], "New task being composed")
            XCTAssertEqual(f.model.subtaskEntry(parentID: f.task.id, projectID: f.projectID), "New child being composed")
        }
    }

    func testParentAndChildCompletionAreIndependent() throws {
        try withFixture { f in
            f.model.toggleTask(f.task)
            var saved = try storedTask(f)
            XCTAssertTrue(saved.completed)
            XCTAssertFalse(saved.subtasks[0].completed)

            f.model.toggleSubtask(saved.subtasks[0])
            saved = try storedTask(f)
            XCTAssertTrue(saved.completed)
            XCTAssertTrue(saved.subtasks[0].completed)

            f.model.toggleTask(saved)
            saved = try storedTask(f)
            XCTAssertFalse(saved.completed)
            XCTAssertTrue(saved.subtasks[0].completed)
        }
    }

    func testSubtaskTitleDraftMergesWithExternalParentNotes() throws {
        try withFixture { f in
            let child = f.task.subtasks[0]
            f.model.setText(itemID: child.id, field: .subtaskTitle, value: "Local child title")
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(notes: FieldChange(expected: f.task.notes, value: "Agent parent notes"))))
            f.model.refresh()

            XCTAssertTrue(f.model.flushPendingEdits())
            XCTAssertEqual(try storedTask(f).subtasks[0].title, "Local child title")
            XCTAssertEqual(try storedTask(f).notes, "Agent parent notes")
        }
    }

    func testCorruptRefreshAndSavePreserveLastGoodWorkspaceAndDraft() throws {
        try withFixture { f in
            let before = f.model.workspace
            f.model.setText(itemID: f.task.id, field: .notes, value: "Unsaved notes")
            let malformed = Data("{not valid JSON".utf8)
            try malformed.write(to: f.store.catalogURL)

            f.model.refresh()

            XCTAssertEqual(f.model.workspace, before)
            XCTAssertEqual(draft(f, field: .notes), "Unsaved notes")
            XCTAssertFalse(f.model.isStoreAvailable)
            XCTAssertNotNil(f.model.errorMessage)
            XCTAssertFalse(f.model.flushPendingEdits())
            XCTAssertEqual(try Data(contentsOf: f.store.catalogURL), malformed)
            XCTAssertEqual(f.model.workspace, before)
        }
    }

    func testLaunchingWithCorruptStoreDoesNotReplaceItWithInbox() throws {
        try withFixture { f in
            let malformed = Data("unreadable existing workspace".utf8)
            try malformed.write(to: f.store.catalogURL)

            let reopened = AppModel(store: f.store, preferences: f.preferences, watchChanges: false)

            XCTAssertFalse(reopened.isStoreAvailable)
            XCTAssertNotNil(reopened.errorMessage)
            reopened.addTask("Cannot save this over the corrupt data")
            XCTAssertEqual(try Data(contentsOf: f.store.catalogURL), malformed)
            XCTAssertTrue(reopened.flushPendingEdits(), "No dirty edits exist, so the unavailable store must not trap the user in the app.")
        }
    }

    func testBackupRestoreOrphanDraftSurvivesRelaunchAndRecoversAsOneTask() throws {
        try withFixture { f in
            let backup = try XCTUnwrap(f.model.availableBackups().first)
            f.model.setText(itemID: f.task.id, field: .title, value: "Unsaved recovered title")
            f.model.setText(itemID: f.task.id, field: .notes, value: "Unsaved notes\nhttps://example.com")

            f.model.restoreBackup(backup)

            XCTAssertFalse(f.model.workspace.projects.flatMap(\.tasks).contains { $0.id == f.task.id })
            XCTAssertEqual(f.model.orphanedDrafts.count, 1)
            XCTAssertFalse(f.model.flushPendingEdits())
            let reopened = AppModel(store: f.store, preferences: f.preferences, watchChanges: false)
            let orphan = try XCTUnwrap(reopened.orphanedDrafts.first)
            XCTAssertEqual(orphan.id, "\(f.projectID):\(f.task.id)", "Recovery identity retains both the original list and task, so reused task IDs cannot combine drafts from different lists.")
            XCTAssertEqual(orphan.title, "Unsaved recovered title")
            XCTAssertEqual(orphan.notes, "Unsaved notes\nhttps://example.com")

            reopened.recoverOrphanedDraft(id: orphan.id)

            let tasks = try f.store.load().projects.flatMap(\.tasks)
            XCTAssertEqual(tasks.count, 1, "Title and notes from one removed item recover together.")
            let recovered = try XCTUnwrap(tasks.first)
            XCTAssertNotEqual(recovered.id, f.task.id)
            XCTAssertEqual(recovered.title, orphan.title)
            XCTAssertEqual(recovered.notes, orphan.notes)
            XCTAssertTrue(reopened.orphanedDrafts.isEmpty)
            XCTAssertTrue(reopened.flushPendingEdits())
        }
    }

    func testExplicitDiscardOfBackupRestoreOrphanUnblocksFlushWithoutCreatingTask() throws {
        try withFixture { f in
            let backup = try XCTUnwrap(f.model.availableBackups().first)
            f.model.setText(itemID: f.task.id, field: .title, value: "Unwanted draft")
            f.model.restoreBackup(backup)
            XCTAssertFalse(f.model.flushPendingEdits())
            let orphan = try XCTUnwrap(f.model.orphanedDrafts.first)

            f.model.discardOrphanedDraft(id: orphan.id)

            XCTAssertTrue(f.model.orphanedDrafts.isEmpty)
            XCTAssertTrue(f.model.flushPendingEdits())
            XCTAssertTrue(try f.store.load().projects.flatMap(\.tasks).isEmpty)
            let reopened = AppModel(store: f.store, preferences: f.preferences, watchChanges: false)
            XCTAssertTrue(reopened.orphanedDrafts.isEmpty)
            XCTAssertTrue(reopened.flushPendingEdits())
        }
    }

    func testFailedOrphanRecoveryRetainsNotesAndRetriesWithFallbackTitle() throws {
        try withFixture { f in
            let backup = try XCTUnwrap(f.model.availableBackups().first)
            f.model.setText(itemID: f.task.id, field: .notes, value: "Only these notes were being edited")
            f.model.restoreBackup(backup)
            let orphan = try XCTUnwrap(f.model.orphanedDrafts.first)
            let validBytes = try Data(contentsOf: f.store.catalogURL)
            let corruptBytes = Data("temporarily unreadable".utf8)
            try corruptBytes.write(to: f.store.catalogURL)

            f.model.recoverOrphanedDraft(id: orphan.id)

            XCTAssertEqual(f.model.orphanedDrafts.first?.notes, orphan.notes)
            XCTAssertEqual(try Data(contentsOf: f.store.catalogURL), corruptBytes)
            XCTAssertNotNil(f.model.errorMessage)

            try validBytes.write(to: f.store.catalogURL)
            f.model.refresh()
            f.model.recoverOrphanedDraft(id: orphan.id)
            let recovered = try XCTUnwrap(f.store.load().projects.flatMap(\.tasks).first)
            XCTAssertEqual(recovered.title, "Recovered task")
            XCTAssertEqual(recovered.notes, orphan.notes)
            XCTAssertTrue(f.model.orphanedDrafts.isEmpty)
            XCTAssertTrue(f.model.flushPendingEdits())
        }
    }

    func testCompositionCommittedAfterExternalDeletionRetainsRecoverableText() throws {
        try withFixture { f in
            _ = try f.external.apply(.deleteTask(id: f.task.id, expected: f.task))
            f.model.refresh()

            f.model.setText(itemID: f.task.id, field: .title, value: "Committed after deletion", expectedBase: f.task.title)

            let orphan = try XCTUnwrap(f.model.orphanedDrafts.first)
            XCTAssertEqual(orphan.title, "Committed after deletion")
            XCTAssertFalse(f.model.flushPendingEdits())
            f.model.recoverOrphanedDraft(id: orphan.id)
            XCTAssertEqual(try f.store.load().projects.flatMap(\.tasks).first?.title, orphan.title)
            XCTAssertTrue(f.model.flushPendingEdits())
        }
    }

    func testFailedStoreAccessRetainsDraftAndCanRetryAfterRecovery() throws {
        try withFixture { f in
            f.model.setText(itemID: f.task.id, field: .notes, value: "Notes to retry")
            let dataDirectory = f.store.url.deletingLastPathComponent()
            let offlineDirectory = f.root.appendingPathComponent("offline", isDirectory: true)
            try FileManager.default.moveItem(at: dataDirectory, to: offlineDirectory)
            try Data("Temporarily blocked directory".utf8).write(to: dataDirectory)

            XCTAssertFalse(f.model.flushPendingEdits())
            XCTAssertEqual(draft(f, field: .notes), "Notes to retry")
            XCTAssertNotNil(f.model.errorMessage)
            XCTAssertTrue(f.model.workspace.projects.flatMap(\.tasks).contains { $0.id == f.task.id })

            try FileManager.default.removeItem(at: dataDirectory)
            try FileManager.default.moveItem(at: offlineDirectory, to: dataDirectory)
            f.model.refresh()
            XCTAssertTrue(f.model.flushPendingEdits())
            XCTAssertEqual(try storedTask(f).notes, "Notes to retry")
        }
    }

    func testBlankAddDoesNotCreateTaskAndMultilineTitleRemainsOneTask() throws {
        try withFixture { f in
            f.model.addTask(" \n\t ")
            XCTAssertEqual(try f.store.load().projects.flatMap(\.tasks).count, 1)
            f.model.addTask("First line\nSecond line")
            let tasks = try f.store.load().projects.flatMap(\.tasks)
            XCTAssertEqual(tasks.count, 2)
            XCTAssertTrue(tasks.contains { $0.title == "First line\nSecond line" })
        }
    }

    func testAddingTasksPrependsBelowEntryAndUndoPreservesExistingOrderAndDetails() throws {
        try withFixture { f in
            let completed = TaskItem(title: "Already completed", completed: true)
            let active = TaskItem(title: "Manually placed first")
            _ = try f.external.apply(.batch([
                .addTask(projectID: f.projectID, task: completed, index: 0),
                .addTask(projectID: f.projectID, task: active, index: 0)
            ]))
            f.model.refresh()
            XCTAssertTrue(f.model.selectTaskForEditing(taskID: f.task.id, projectID: f.projectID))
            XCTAssertTrue(f.model.toggleDetails(taskID: f.task.id))
            XCTAssertTrue(f.model.toggleCompleted(projectID: f.projectID))
            let originalTasks = [active, completed, f.task]

            f.model.entryDrafts[f.projectID] = "First new task"
            f.model.addTask("First new task")
            let first = try XCTUnwrap(f.model.selectedProject?.tasks.first)
            XCTAssertEqual(first.title, "First new task")
            XCTAssertEqual(f.model.entryDrafts[f.projectID], "")
            XCTAssertEqual(f.model.taskListEntries(projectID: f.projectID), [
                .addTask(projectID: f.projectID), .task(first), .task(active), .task(f.task),
                .completedHeader(projectID: f.projectID, count: 1), .task(completed)
            ])

            f.model.entryDrafts[f.projectID] = "Second new task"
            f.model.addTask("Second new task")
            let second = try XCTUnwrap(f.model.selectedProject?.tasks.first)
            XCTAssertEqual(second.title, "Second new task")
            XCTAssertEqual(f.model.entryDrafts[f.projectID], "")
            XCTAssertEqual(try f.store.load().projects.first { $0.id == f.projectID }?.tasks,
                           [second, first] + originalTasks)
            XCTAssertEqual(f.model.taskListEntries(projectID: f.projectID), [
                .addTask(projectID: f.projectID), .task(second), .task(first), .task(active), .task(f.task),
                .completedHeader(projectID: f.projectID, count: 1), .task(completed)
            ])
            XCTAssertEqual(f.model.selectedTaskID, f.task.id)
            XCTAssertEqual(f.model.expandedTaskID, f.task.id)

            f.model.undo()
            XCTAssertEqual(try f.store.load().projects.first { $0.id == f.projectID }?.tasks, [first] + originalTasks)
            f.model.undo()
            XCTAssertEqual(try f.store.load().projects.first { $0.id == f.projectID }?.tasks, originalTasks)
            f.model.redo()
            f.model.redo()
            XCTAssertEqual(try f.store.load().projects.first { $0.id == f.projectID }?.tasks,
                           [second, first] + originalTasks)
            XCTAssertEqual(f.model.selectedTaskID, f.task.id)
            XCTAssertEqual(f.model.expandedTaskID, f.task.id)
        }
    }

    func testAddingSubtasksPrependsAndUndoPreservesExistingOrder() throws {
        try withFixture { f in
            let completed = Subtask(title: "Already completed", completed: true)
            _ = try f.external.apply(.addSubtask(parentID: f.task.id, subtask: completed, index: 0))
            f.model.refresh()
            let originalSubtasks = [completed] + f.task.subtasks

            f.model.setSubtaskEntry(parentID: f.task.id, projectID: f.projectID, value: "First new subtask")
            f.model.addSubtask(parentID: f.task.id, title: "First new subtask", projectID: f.projectID)
            let first = try XCTUnwrap(try storedTask(f).subtasks.first)
            XCTAssertEqual(first.title, "First new subtask")
            XCTAssertEqual(f.model.subtaskEntry(parentID: f.task.id, projectID: f.projectID), "")
            XCTAssertEqual(try storedTask(f).subtasks, [first] + originalSubtasks)

            f.model.addSubtask(parentID: f.task.id, title: "Second new subtask")
            let second = try XCTUnwrap(try storedTask(f).subtasks.first)
            XCTAssertEqual(second.title, "Second new subtask")
            XCTAssertEqual(try storedTask(f).subtasks, [second, first] + originalSubtasks)

            f.model.undo()
            XCTAssertEqual(try storedTask(f).subtasks, [first] + originalSubtasks)
            f.model.undo()
            XCTAssertEqual(try storedTask(f).subtasks, originalSubtasks)
            f.model.redo()
            f.model.redo()
            XCTAssertEqual(try storedTask(f).subtasks, [second, first] + originalSubtasks)
        }
    }

    func testExplicitDeleteWorksAfterClearingTaskTitle() throws {
        try withFixture { f in
            f.model.setText(itemID: f.task.id, field: .title, value: "")
            XCTAssertFalse(f.model.flushPendingEdits())

            f.model.deleteTask(f.task)

            XCTAssertFalse(try f.store.load().projects.flatMap(\.tasks).contains { $0.id == f.task.id })
            XCTAssertTrue(f.model.flushPendingEdits(), "An explicitly deleted task must not leave an unsaveable orphan draft.")
            f.model.undo()
            XCTAssertEqual(try storedTask(f), f.task)
        }
    }

    func testExplicitDeleteWorksAfterClearingSubtaskTitle() throws {
        try withFixture { f in
            let child = f.task.subtasks[0]
            f.model.setText(itemID: child.id, field: .subtaskTitle, value: " \n ")
            XCTAssertFalse(f.model.flushPendingEdits())

            f.model.deleteSubtask(child)

            XCTAssertTrue(try storedTask(f).subtasks.isEmpty)
            XCTAssertTrue(f.model.flushPendingEdits())
            f.model.undo()
            XCTAssertEqual(try storedTask(f).subtasks, [child])
        }
    }

    func testCompletedSectionDefaultsCollapsedAndKeepsAddEntryAtTop() throws {
        try withFixture { f in
            let completedFirst = TaskItem(title: "First completed", completed: true)
            let activeSecond = TaskItem(title: "Second active")
            let completedSecond = TaskItem(title: "Second completed", completed: true)
            _ = try f.external.apply(.batch([
                .addTask(projectID: f.projectID, task: completedFirst, index: nil),
                .addTask(projectID: f.projectID, task: activeSecond, index: nil),
                .addTask(projectID: f.projectID, task: completedSecond, index: nil)
            ]))
            f.model.refresh()
            let beforeDisclosure = try f.store.load()

            XCTAssertFalse(f.model.isCompletedExpanded(projectID: f.projectID))
            XCTAssertEqual(f.model.taskListEntries(projectID: f.projectID), [
                .addTask(projectID: f.projectID), .task(f.task), .task(activeSecond),
                .completedHeader(projectID: f.projectID, count: 2)
            ])
            XCTAssertTrue(f.model.toggleCompleted(projectID: f.projectID))
            XCTAssertEqual(f.model.taskListEntries(projectID: f.projectID), [
                .addTask(projectID: f.projectID), .task(f.task), .task(activeSecond),
                .completedHeader(projectID: f.projectID, count: 2), .task(completedFirst), .task(completedSecond)
            ])
            XCTAssertEqual(try f.store.load(), beforeDisclosure, "Section disclosure is local navigation, not shared task content.")
        }
    }

    func testCompletingAndReopeningPartitionDisplayWithoutReorderingStoredTasks() throws {
        try withFixture { f in
            let completedFirst = TaskItem(title: "Already completed", completed: true)
            let activeSecond = TaskItem(title: "Second active")
            _ = try f.external.apply(.batch([
                .addTask(projectID: f.projectID, task: completedFirst, index: nil),
                .addTask(projectID: f.projectID, task: activeSecond, index: nil)
            ]))
            f.model.refresh()
            XCTAssertTrue(f.model.toggleCompleted(projectID: f.projectID))
            let originalIDs = [f.task.id, completedFirst.id, activeSecond.id]

            f.model.toggleTask(f.task)

            var completedTask = f.task
            completedTask.completed = true
            XCTAssertEqual(f.model.taskListEntries(projectID: f.projectID), [
                .addTask(projectID: f.projectID), .task(activeSecond),
                .completedHeader(projectID: f.projectID, count: 2), .task(completedTask), .task(completedFirst)
            ])
            XCTAssertEqual(try f.store.load().projects.first { $0.id == f.projectID }?.tasks.map(\.id), originalIDs)

            f.model.toggleTask(completedTask)

            XCTAssertEqual(f.model.taskListEntries(projectID: f.projectID), [
                .addTask(projectID: f.projectID), .task(f.task), .task(activeSecond),
                .completedHeader(projectID: f.projectID, count: 1), .task(completedFirst)
            ])
            XCTAssertEqual(try f.store.load().projects.first { $0.id == f.projectID }?.tasks.map(\.id), originalIDs)
        }
    }

    func testCompletedVisibilityIsLocalPerProjectAndSurvivesRelaunch() throws {
        try withFixture { f in
            let other = Project(name: "Other", tasks: [TaskItem(title: "Done elsewhere", completed: true)])
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(completed: FieldChange(expected: false, value: true))))
            _ = try f.external.apply(.addProject(project: other, index: nil))
            f.model.refresh()
            let beforeDisclosure = try f.store.load()
            XCTAssertFalse(f.model.isCompletedExpanded(projectID: f.projectID))
            XCTAssertFalse(f.model.isCompletedExpanded(projectID: other.id))
            XCTAssertTrue(f.model.toggleCompleted(projectID: f.projectID))
            f.model.selectProject(other.id)
            XCTAssertFalse(f.model.isCompletedExpanded(projectID: other.id))

            let reopened = AppModel(store: f.store, preferences: f.preferences, watchChanges: false)

            XCTAssertTrue(reopened.isCompletedExpanded(projectID: f.projectID))
            XCTAssertFalse(reopened.isCompletedExpanded(projectID: other.id))
            XCTAssertTrue(reopened.toggleCompleted(projectID: other.id))
            XCTAssertTrue(reopened.toggleCompleted(projectID: f.projectID))
            let reopenedAgain = AppModel(store: f.store, preferences: f.preferences, watchChanges: false)
            XCTAssertFalse(reopenedAgain.isCompletedExpanded(projectID: f.projectID))
            XCTAssertTrue(reopenedAgain.isCompletedExpanded(projectID: other.id))
            XCTAssertEqual(try f.store.load(), beforeDisclosure)
        }
    }

    func testTaskSelectionEditsBeforeTogglingDetailsAndResetsOnBlankClick() throws {
        try withFixture { f in
            XCTAssertTrue(f.model.selectTaskForEditing(taskID: f.task.id, projectID: f.projectID))
            XCTAssertEqual(f.model.selectedTaskID, f.task.id)
            XCTAssertNil(f.model.expandedTaskID)
            XCTAssertTrue(f.model.clickSelectedTaskTitle(taskID: f.task.id, projectID: f.projectID))
            XCTAssertEqual(f.model.expandedTaskID, f.task.id)
            XCTAssertTrue(f.model.clickSelectedTaskTitle(taskID: f.task.id, projectID: f.projectID))
            XCTAssertNil(f.model.expandedTaskID)
            XCTAssertEqual(f.model.selectedTaskID, f.task.id)
            XCTAssertTrue(f.model.clickSelectedTaskTitle(taskID: f.task.id, projectID: f.projectID))
            f.model.setText(itemID: f.task.id, field: .title, value: "Saved on blank click")

            XCTAssertTrue(f.model.clearTaskSelection())
            XCTAssertNil(f.model.selectedTaskID)
            XCTAssertNil(f.model.expandedTaskID)
            XCTAssertEqual(try storedTask(f).title, "Saved on blank click")
            XCTAssertTrue(f.model.selectTaskForEditing(taskID: f.task.id, projectID: f.projectID))
            XCTAssertNil(f.model.expandedTaskID)

            XCTAssertTrue(f.model.clickSelectedTaskTitle(taskID: f.task.id, projectID: f.projectID))
            let other = TaskItem(title: "Another task")
            _ = try f.external.apply(.addTask(projectID: f.projectID, task: other, index: nil))
            f.model.refresh()
            XCTAssertTrue(f.model.selectTaskForEditing(taskID: other.id, projectID: f.projectID))
            XCTAssertEqual(f.model.selectedTaskID, other.id)
            XCTAssertNil(f.model.expandedTaskID)

            XCTAssertTrue(f.model.toggleDetails(taskID: other.id))
            let restored = AppModel(store: f.store, preferences: f.preferences, watchChanges: false)
            XCTAssertNil(restored.selectedTaskID)
            XCTAssertEqual(restored.expandedTaskID, other.id)
            XCTAssertTrue(restored.selectTaskForEditing(taskID: other.id, projectID: f.projectID))
            XCTAssertEqual(restored.expandedTaskID, other.id, "Focusing a restored open task must keep its details open.")
        }
    }

    func testTaskSelectionKeepsFailedDraftAccessibleOnCollapseOrSwitch() throws {
        try withFixture { f in
            let other = TaskItem(title: "Another task")
            _ = try f.external.apply(.addTask(projectID: f.projectID, task: other, index: nil))
            f.model.refresh()
            XCTAssertTrue(f.model.selectTaskForEditing(taskID: f.task.id, projectID: f.projectID))
            f.model.setText(itemID: f.task.id, field: .title, value: "")
            XCTAssertTrue(f.model.clickSelectedTaskTitle(taskID: f.task.id, projectID: f.projectID),
                          "An invalid title must still allow opening its guidance and conflict controls.")

            XCTAssertFalse(f.model.clearTaskSelection())
            XCTAssertFalse(f.model.clickSelectedTaskTitle(taskID: f.task.id, projectID: f.projectID))
            XCTAssertFalse(f.model.selectTaskForEditing(taskID: other.id, projectID: f.projectID))
            XCTAssertEqual(f.model.selectedTaskID, f.task.id)
            XCTAssertEqual(f.model.expandedTaskID, f.task.id)
            XCTAssertEqual(draft(f), "")
            XCTAssertEqual(try storedTask(f).title, f.task.title)
        }
    }

    func testTaskSelectionRetainsCollapsedEditorAcrossExternalCompletion() throws {
        try withFixture { f in
            XCTAssertTrue(f.model.selectTaskForEditing(taskID: f.task.id, projectID: f.projectID))
            f.model.setText(itemID: f.task.id, field: .title, value: "")
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(completed: FieldChange(expected: false, value: true))))
            f.model.refresh()

            XCTAssertEqual(f.model.selectedTaskID, f.task.id)
            XCTAssertNil(f.model.expandedTaskID)
            XCTAssertTrue(f.model.isCompletedExpanded(projectID: f.projectID))
            XCTAssertTrue(f.model.taskListEntries(projectID: f.projectID).contains(.task(try storedTask(f))))
            XCTAssertFalse(f.model.toggleCompleted(projectID: f.projectID))
            XCTAssertEqual(draft(f), "")
            f.model.setText(itemID: f.task.id, field: .title, value: "Saved before closing Completed")
            XCTAssertTrue(f.model.toggleCompleted(projectID: f.projectID))
            XCTAssertNil(f.model.selectedTaskID)
            XCTAssertFalse(f.model.isCompletedExpanded(projectID: f.projectID))
            XCTAssertEqual(try storedTask(f).title, "Saved before closing Completed")
        }
    }

    func testExternalCompletionRevealsExpandedTaskWithoutDiscardingDirtyDraft() throws {
        try withFixture { f in
            f.model.toggleDetails(taskID: f.task.id)
            f.model.setText(itemID: f.task.id, field: .title, value: "")
            XCTAssertFalse(f.model.isCompletedExpanded(projectID: f.projectID))
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(completed: FieldChange(expected: false, value: true))))

            f.model.refresh()

            XCTAssertTrue(f.model.isCompletedExpanded(projectID: f.projectID))
            XCTAssertEqual(f.model.expandedTaskID, f.task.id)
            XCTAssertEqual(draft(f), "")
            XCTAssertFalse(f.model.flushPendingEdits())
            XCTAssertTrue(f.model.taskListEntries(projectID: f.projectID).contains(.task(try storedTask(f))))
            XCTAssertEqual(try storedTask(f).title, f.task.title)
            XCTAssertFalse(try storedTask(f).subtasks[0].completed)
        }
    }

    func testCompletedCollapseRequiresSavedDraftAndStaysCollapsedOnLaterRefresh() throws {
        try withFixture { f in
            f.model.toggleDetails(taskID: f.task.id)
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(completed: FieldChange(expected: false, value: true))))
            f.model.refresh()
            f.model.setText(itemID: f.task.id, field: .title, value: "")

            XCTAssertFalse(f.model.toggleCompleted(projectID: f.projectID))
            XCTAssertTrue(f.model.isCompletedExpanded(projectID: f.projectID))
            XCTAssertEqual(f.model.expandedTaskID, f.task.id)
            XCTAssertEqual(draft(f), "")

            f.model.setText(itemID: f.task.id, field: .title, value: "Saved before collapsing")
            XCTAssertTrue(f.model.toggleCompleted(projectID: f.projectID))
            XCTAssertFalse(f.model.isCompletedExpanded(projectID: f.projectID))
            XCTAssertNil(f.model.expandedTaskID)
            XCTAssertEqual(try storedTask(f).title, "Saved before collapsing")
            _ = try f.external.apply(.addTask(projectID: f.projectID, task: TaskItem(title: "Unrelated addition"), index: nil))
            f.model.refresh()
            XCTAssertFalse(f.model.isCompletedExpanded(projectID: f.projectID), "Unrelated refresh must respect explicit collapse.")
            XCTAssertNil(f.model.expandedTaskID)
            XCTAssertTrue(f.model.flushPendingEdits())
        }
    }

    func testProjectDropsBeforeAndAfterPreserveCorrectOrderInBothDirections() throws {
        try withFixture { f in
            let group = ProjectGroup(name: "Work")
            let second = Project(name: "Second", groupID: group.id)
            let third = Project(name: "Third", groupID: group.id)
            _ = try f.external.apply(.batch([
                .addGroup(group: group, index: nil),
                .patchProject(id: f.projectID, name: nil, groupID: FieldChange(expected: nil, value: group.id)),
                .addProject(project: second, index: nil), .addProject(project: third, index: nil)
            ]))
            f.model.refresh()
            let first = try XCTUnwrap(f.model.selectedProject)

            XCTAssertTrue(f.model.moveProject(first, to: .after(third.id)))
            XCTAssertEqual(try f.store.load().projects.map(\.id), [second.id, third.id, first.id])
            XCTAssertTrue(f.model.moveProject(first, to: .before(second.id)))
            XCTAssertEqual(try f.store.load().projects.map(\.id), [first.id, second.id, third.id])
            XCTAssertTrue(f.model.moveProject(first, to: .before(third.id)))
            XCTAssertEqual(try f.store.load().projects.map(\.id), [second.id, first.id, third.id])
            XCTAssertTrue(f.model.moveProject(third, to: .after(second.id)))
            XCTAssertEqual(try f.store.load().projects.map(\.id), [second.id, third.id, first.id])
            XCTAssertTrue(try f.store.load().projects.allSatisfy { $0.groupID == group.id })
        }
    }

    func testDropOnCollapsedGroupAppendsAndPreservesSelectedEditingContext() throws {
        try withFixture { f in
            let sourceGroup = ProjectGroup(name: "Source")
            let targetGroup = ProjectGroup(name: "Target")
            let targetFirst = Project(name: "Target first", groupID: targetGroup.id)
            let targetLast = Project(name: "Target last", groupID: targetGroup.id)
            let ungrouped = Project(name: "Ungrouped")
            _ = try f.external.apply(.batch([
                .addGroup(group: sourceGroup, index: nil), .addGroup(group: targetGroup, index: nil),
                .patchProject(id: f.projectID, name: nil, groupID: FieldChange(expected: nil, value: sourceGroup.id)),
                .addProject(project: targetFirst, index: nil), .addProject(project: targetLast, index: nil),
                .addProject(project: ungrouped, index: nil)
            ]))
            f.model.refresh()
            f.model.toggleGroup(targetGroup.id)
            f.model.toggleDetails(taskID: f.task.id)
            f.model.setText(itemID: f.task.id, field: .title, value: "")
            let selected = try XCTUnwrap(f.model.selectedProject)

            XCTAssertTrue(f.model.moveProject(selected, to: .group(targetGroup.id)))

            XCTAssertEqual(try f.store.load().projects.map(\.id), [targetFirst.id, targetLast.id, f.projectID, ungrouped.id])
            XCTAssertEqual(f.model.selectedProject?.groupID, targetGroup.id)
            XCTAssertEqual(f.model.selectedProjectID, f.projectID)
            XCTAssertEqual(f.model.expandedTaskID, f.task.id)
            XCTAssertTrue(f.model.collapsedGroupIDs.contains(targetGroup.id))
            XCTAssertEqual(draft(f), "")
            XCTAssertEqual(try storedTask(f).title, f.task.title)
            XCTAssertFalse(f.model.flushPendingEdits())
        }
    }

    func testDropBeforeOtherGroupTabAdoptsItsGroupAndCanUngroup() throws {
        try withFixture { f in
            let group = ProjectGroup(name: "Work")
            let target = Project(name: "Target", groupID: group.id)
            let ungrouped = Project(name: "Other ungrouped")
            _ = try f.external.apply(.batch([
                .addGroup(group: group, index: nil), .addProject(project: target, index: nil),
                .addProject(project: ungrouped, index: nil)
            ]))
            f.model.refresh()
            let initial = try XCTUnwrap(f.model.selectedProject)

            XCTAssertTrue(f.model.moveProject(initial, to: .before(target.id)))
            XCTAssertEqual(f.model.selectedProject?.groupID, group.id)
            XCTAssertEqual(try f.store.load().projects.map(\.id), [f.projectID, target.id, ungrouped.id])

            let grouped = try XCTUnwrap(f.model.selectedProject)
            XCTAssertTrue(f.model.moveProject(grouped, to: .group(nil)))
            XCTAssertNil(f.model.selectedProject?.groupID)
            XCTAssertEqual(try f.store.load().projects.map(\.id), [target.id, ungrouped.id, f.projectID])
        }
    }

    func testDropIntoEmptyGroupWorksWithoutChangingExistingProjectOrder() throws {
        try withFixture { f in
            let empty = ProjectGroup(name: "Empty group")
            _ = try f.external.apply(.addGroup(group: empty, index: nil))
            f.model.refresh()
            let selected = try XCTUnwrap(f.model.selectedProject)

            XCTAssertTrue(f.model.moveProject(selected, to: .group(empty.id)))

            XCTAssertEqual(f.model.selectedProject?.groupID, empty.id)
            XCTAssertEqual(try f.store.load().projects.map(\.id), [f.projectID])
            XCTAssertEqual(try storedTask(f), f.task)
        }
    }

    func testUndoProjectDropRestoresOrderAndGroupWithoutRevertingExternalTaskEdit() throws {
        try withFixture { f in
            let group = ProjectGroup(name: "Work")
            let target = Project(name: "Target", groupID: group.id)
            _ = try f.external.apply(.batch([
                .addGroup(group: group, index: nil), .addProject(project: target, index: nil)
            ]))
            f.model.refresh()
            let selected = try XCTUnwrap(f.model.selectedProject)
            XCTAssertTrue(f.model.moveProject(selected, to: .after(target.id)))
            _ = try f.external.apply(.patchTask(id: f.task.id, patch: TaskPatch(notes: FieldChange(expected: f.task.notes, value: "Agent notes after drag"))))

            f.model.undo()

            let workspace = try f.store.load()
            XCTAssertEqual(workspace.projects.map(\.id), [f.projectID, target.id])
            XCTAssertNil(workspace.projects.first { $0.id == f.projectID }?.groupID)
            XCTAssertEqual(try storedTask(f).notes, "Agent notes after drag")
            XCTAssertEqual(f.model.selectedProjectID, f.projectID)
        }
    }

    func testDropRejectsDestinationProjectDeletedAfterDragStarted() throws {
        try withFixture { f in
            let target = Project(name: "Destination")
            _ = try f.external.apply(.addProject(project: target, index: nil))
            f.model.refresh()
            let selected = try XCTUnwrap(f.model.selectedProject)
            let dragOrder = f.model.workspace.projects.map(\.id)
            _ = try f.external.apply(.deleteProject(id: target.id, expected: target))
            let afterExternalDeletion = try f.store.load()

            XCTAssertFalse(f.model.moveProject(selected, to: .before(target.id), expectedOrder: dragOrder))

            XCTAssertEqual(try f.store.load(), afterExternalDeletion)
            XCTAssertNotNil(f.model.errorMessage)
            XCTAssertEqual(f.model.selectedProjectID, f.projectID)
            XCTAssertEqual(try storedTask(f), f.task)
        }
    }

    func testDropRejectsDestinationGroupDeletedAfterDragStarted() throws {
        try withFixture { f in
            let target = ProjectGroup(name: "Destination")
            _ = try f.external.apply(.addGroup(group: target, index: nil))
            f.model.refresh()
            let selected = try XCTUnwrap(f.model.selectedProject)
            let dragOrder = f.model.workspace.projects.map(\.id)
            _ = try f.external.apply(.deleteGroup(id: target.id, expected: target))
            let afterExternalDeletion = try f.store.load()

            XCTAssertFalse(f.model.moveProject(selected, to: .group(target.id), expectedOrder: dragOrder))

            XCTAssertEqual(try f.store.load(), afterExternalDeletion)
            XCTAssertNotNil(f.model.errorMessage)
            XCTAssertNil(try f.store.load().projects.first?.groupID)
        }
    }

    func testDragCapturedOrderRejectsConcurrentReorderEvenAfterModelRefresh() throws {
        try withFixture { f in
            let middle = Project(name: "Middle")
            let last = Project(name: "Last")
            _ = try f.external.apply(.batch([
                .addProject(project: middle, index: nil), .addProject(project: last, index: nil)
            ]))
            f.model.refresh()
            let selectedAtDragStart = try XCTUnwrap(f.model.selectedProject)
            let dragOrder = f.model.workspace.projects.map(\.id)
            _ = try f.external.apply(.reorderProjects(change: FieldChange(expected: dragOrder, value: [last.id, middle.id, f.projectID])))
            f.model.refresh()
            let afterConcurrentReorder = try f.store.load()

            XCTAssertFalse(f.model.moveProject(selectedAtDragStart, to: .before(last.id), expectedOrder: dragOrder))

            XCTAssertEqual(try f.store.load(), afterConcurrentReorder)
            XCTAssertNotNil(f.model.errorMessage)
        }
    }
    func testMissingListRetainsDraftAndNavigationAcrossRelaunchWhileHealthyListEdits() throws {
        try withFixture { f in
            let listURL = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            let bytes = try Data(contentsOf: listURL)
            XCTAssertTrue(f.model.createList(name: "Healthy"))
            let healthyID = f.model.selectedProjectID
            f.model.selectProject(f.projectID)
            f.model.toggleDetails(taskID: f.task.id)
            f.model.entryDrafts[f.projectID] = "Unsubmitted task"
            f.model.setScrollAnchor(projectID: f.projectID, taskID: f.task.id)
            f.model.setText(itemID: f.task.id, field: .notes, value: "Retained missing-list notes")
            try FileManager.default.removeItem(at: listURL)
            f.model.refresh()

            XCTAssertTrue(f.model.isStoreAvailable)
            XCTAssertFalse(f.model.isSelectedListAvailable)
            XCTAssertTrue(f.model.selectedListIssue?.isMissing == true)
            XCTAssertTrue(f.model.flushEditsForDismissal())
            XCTAssertTrue(f.model.orphanedDrafts.isEmpty)
            XCTAssertFalse(f.model.flushPendingEdits())
            XCTAssertFalse(FileManager.default.fileExists(atPath: listURL.path))

            let reopened = AppModel(store: TodoStore(url: f.store.url), preferences: f.preferences, watchChanges: false)
            XCTAssertEqual(reopened.selectedProjectID, f.projectID)
            XCTAssertEqual(reopened.expandedTaskID, f.task.id)
            XCTAssertEqual(reopened.entryDrafts[f.projectID], "Unsubmitted task")
            XCTAssertEqual(reopened.scrollAnchor(projectID: f.projectID), f.task.id)
            XCTAssertEqual(reopened.text(itemID: f.task.id, field: .notes, fallback: ""), "Retained missing-list notes")
            XCTAssertTrue(reopened.orphanedDrafts.isEmpty)
            reopened.selectProject(healthyID)
            XCTAssertTrue(reopened.isSelectedListAvailable)
            reopened.addTask("Works while another file is missing")
            XCTAssertTrue(reopened.selectedProject?.tasks.contains { $0.title == "Works while another file is missing" } == true)
            reopened.undo()
            XCTAssertTrue(reopened.selectedProject?.tasks.isEmpty == true)

            try bytes.write(to: listURL)
            reopened.refresh()
            reopened.selectProject(f.projectID)
            XCTAssertTrue(reopened.isSelectedListAvailable)
            XCTAssertTrue(reopened.flushPendingEdits())
            XCTAssertEqual(try storedTask(f).notes, "Retained missing-list notes")
        }
    }

    func testInvalidListRetainsDraftWithoutOverwritingAndHealthyListRemainsAvailable() throws {
        try withFixture { f in
            let listURL = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            XCTAssertTrue(f.model.createList(name: "Healthy"))
            let healthyID = f.model.selectedProjectID
            f.model.selectProject(f.projectID)
            f.model.setText(itemID: f.task.id, field: .title, value: "Unsaved local title")
            let invalid = Data("version: 1\nname: Broken\ntasks: [\n".utf8)
            try invalid.write(to: listURL)
            f.model.refresh()

            XCTAssertTrue(f.model.isStoreAvailable)
            XCTAssertFalse(f.model.isSelectedListAvailable)
            XCTAssertFalse(f.model.selectedListIssue?.isMissing ?? true)
            XCTAssertTrue(f.model.orphanedDrafts.isEmpty)
            XCTAssertFalse(f.model.flushPendingEdits())
            XCTAssertEqual(draft(f), "Unsaved local title")
            // A native IME composition may finish after the file becomes unreadable.
            f.model.setText(itemID: f.task.id, field: .notes, value: "Committed after invalid file", expectedBase: f.task.notes)
            XCTAssertEqual(draft(f, field: .notes), "Committed after invalid file")
            XCTAssertTrue(f.model.flushEditsForDismissal())
            XCTAssertEqual(try Data(contentsOf: listURL), invalid)
            f.model.selectProject(healthyID)
            XCTAssertTrue(f.model.isSelectedListAvailable)
            f.model.addTask("Healthy edit")
            XCTAssertTrue(f.model.selectedProject?.tasks.contains { $0.title == "Healthy edit" } == true)
            XCTAssertEqual(try Data(contentsOf: listURL), invalid)
        }
    }

    func testMoveAndRemovePreservePortableFileAndStableDraftKeys() throws {
        try withFixture { f in
            let original = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            let folder = f.root.appendingPathComponent("repository", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent("todo.yaml")
            f.model.toggleDetails(taskID: f.task.id)
            f.model.entryDrafts[f.projectID] = "Unsubmitted"
            f.model.setText(itemID: f.task.id, field: .title, value: "")
            XCTAssertTrue(f.model.moveList(id: f.projectID, to: destination))
            XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
            XCTAssertEqual(f.model.location(for: f.projectID)?.url, destination.standardizedFileURL.resolvingSymlinksInPath())
            XCTAssertFalse(f.model.location(for: f.projectID)?.isManaged ?? true)
            XCTAssertEqual(f.model.selectedProjectID, f.projectID)
            XCTAssertEqual(f.model.expandedTaskID, f.task.id)
            XCTAssertEqual(draft(f), "")
            let reopened = AppModel(store: f.store, preferences: f.preferences, watchChanges: false)
            XCTAssertEqual(reopened.text(itemID: f.task.id, field: .title, fallback: "missing"), "")
            XCTAssertEqual(reopened.entryDrafts[f.projectID], "Unsubmitted")
            XCTAssertTrue(reopened.removeList(id: f.projectID))
            XCTAssertTrue(reopened.workspace.projects.isEmpty)
            XCTAssertTrue(reopened.isStoreAvailable)
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertTrue(reopened.openList(at: destination))
            XCTAssertEqual(reopened.selectedProjectID, f.projectID)
        }
    }

    func testWatcherDetectsInPlaceAndReplacementSavesAfterMovingList() async throws {
        let f = try makeFixture(watchChanges: true)
        defer { cleanUp(f) }
        let folder = f.root.appendingPathComponent("repository", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("todo.yaml")
        XCTAssertTrue(f.model.moveList(id: f.projectID, to: destination))
        f.model.setText(itemID: f.task.id, field: .title, value: "")
        for (title, options) in [("Editor in-place title", Data.WritingOptions()), ("Editor replacement title", .atomic), ("Reattached file watcher title", Data.WritingOptions())] {
            var document = try ListFileCodec.decode(Data(contentsOf: destination))
            document.tasks[0].title = title
            try ListFileCodec.encode(document).write(to: destination, options: options)
            let deadline = Date().addingTimeInterval(3)
            while f.model.selectedProject?.tasks.first?.title != title, Date() < deadline {
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            XCTAssertEqual(f.model.selectedProject?.tasks.first?.title, title)
            XCTAssertEqual(draft(f), "")
        }
        XCTAssertFalse(f.model.flushPendingEdits())
    }

    func testLegacyDraftWithoutListOwnerIsRetainedUntilMissingFileReturns() throws {
        try withFixture { f in
            let listURL = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            let bytes = try Data(contentsOf: listURL)
            f.model.setText(itemID: f.task.id, field: .notes, value: "Legacy retained notes")
            let key = "workspace." + Data(f.store.url.standardizedFileURL.path.utf8).base64EncodedString()
            var saved = try XCTUnwrap(f.preferences.dictionary(forKey: key))
            let data = try XCTUnwrap(saved["drafts"] as? Data)
            var drafts = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            for index in drafts.indices { drafts[index].removeValue(forKey: "projectID") }
            saved["drafts"] = try JSONSerialization.data(withJSONObject: drafts)
            f.preferences.set(saved, forKey: key)
            try FileManager.default.removeItem(at: listURL)

            let reopened = AppModel(store: TodoStore(url: f.store.url), preferences: f.preferences, watchChanges: false)
            XCTAssertTrue(reopened.orphanedDrafts.isEmpty)
            XCTAssertFalse(reopened.flushPendingEdits())
            XCTAssertEqual(reopened.text(itemID: f.task.id, field: .notes, fallback: ""), "Legacy retained notes")
            XCTAssertFalse(FileManager.default.fileExists(atPath: listURL.path))
            try bytes.write(to: listURL)
            reopened.refresh()
            XCTAssertTrue(reopened.flushPendingEdits())
            XCTAssertEqual(try storedTask(f).notes, "Legacy retained notes")
        }
    }

    func testOpenMovedIdentityOffersRelinkAndPreservesExistingDraft() throws {
        try withFixture { f in
            let original = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            let destination = f.root.appendingPathComponent("relocated.yaml")
            f.model.setText(itemID: f.task.id, field: .notes, value: "Draft follows list identity")
            try FileManager.default.moveItem(at: original, to: destination)
            f.model.refresh()
            XCTAssertTrue(f.model.hasRetainedDrafts(listID: f.projectID))
            XCTAssertFalse(f.model.openList(at: destination))
            let conflict = try XCTUnwrap(f.model.listIdentityConflict)
            XCTAssertEqual(conflict.listID, f.projectID)
            XCTAssertEqual(conflict.candidateURL, destination.standardizedFileURL.resolvingSymlinksInPath())
            XCTAssertTrue(f.model.relinkList(id: conflict.listID, to: conflict.candidateURL))
            XCTAssertNil(f.model.listIdentityConflict)
            XCTAssertEqual(f.model.workspace.projects.count, 1)
            XCTAssertEqual(f.model.selectedProjectID, f.projectID)
            XCTAssertTrue(f.model.isSelectedListAvailable)
            XCTAssertTrue(f.model.flushPendingEdits())
            XCTAssertFalse(f.model.hasRetainedDrafts(listID: f.projectID))
            XCTAssertEqual(try storedTask(f).notes, "Draft follows list identity")
        }
    }

    func testDeleteSavesTaskEditsAndRetainsUnsubmittedEntriesAcrossRestoreAndRestart() throws {
        try withFixture { f in
            let source = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            let recovered = f.root.appendingPathComponent("synthetic-trash.yaml")
            f.model.setText(itemID: f.task.id, field: .title, value: "Saved before Trash")
            f.model.setText(itemID: f.task.id, field: .notes, value: "Saved notes")
            f.model.entryDrafts[f.projectID] = "Unsubmitted task"
            f.model.setSubtaskEntry(parentID: f.task.id, projectID: f.projectID, value: "Unsubmitted child")
            f.store.trashListFile = { url in
                try FileManager.default.moveItem(at: url, to: recovered)
                return recovered
            }
            XCTAssertTrue(f.model.deleteList(id: f.projectID, expectedURL: source))
            let document = try ListFileCodec.decode(Data(contentsOf: recovered))
            XCTAssertEqual(document.tasks[0].title, "Saved before Trash")
            XCTAssertEqual(document.tasks[0].notes, "Saved notes")
            XCTAssertEqual(document.tasks.count, 1, "Unsubmitted entries remain local work.")
            XCTAssertTrue(f.model.workspace.projects.isEmpty)
            XCTAssertTrue(f.model.hasRetainedDrafts(listID: f.projectID))
            XCTAssertEqual(f.model.entryDrafts[f.projectID], "Unsubmitted task")
            let reopened = AppModel(store: f.store, preferences: f.preferences, watchChanges: false)
            try FileManager.default.moveItem(at: recovered, to: source)
            XCTAssertTrue(reopened.openList(at: source))
            XCTAssertEqual(reopened.selectedProject?.tasks[0].title, "Saved before Trash")
            XCTAssertEqual(reopened.entryDrafts[f.projectID], "Unsubmitted task")
            XCTAssertEqual(reopened.subtaskEntry(parentID: f.task.id, projectID: f.projectID), "Unsubmitted child")
        }
    }

    func testDeleteBlocksBlankAndConflictedEditsAndRetainsThemForRetry() throws {
        try withFixture { f in
            let source = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            var calls = 0
            f.store.trashListFile = { url in calls += 1; return url }
            f.model.setText(itemID: f.task.id, field: .title, value: "")
            XCTAssertFalse(f.model.deleteList(id: f.projectID, expectedURL: source))
            XCTAssertEqual(calls, 0)
            XCTAssertEqual(draft(f), "")
            XCTAssertNotNil(f.model.location(for: f.projectID))
            f.model.setText(itemID: f.task.id, field: .title, value: "My edit")
            _ = try f.external.apply(.patchTask(id: f.task.id,
                patch: TaskPatch(title: FieldChange(expected: f.task.title, value: "Other edit"))))
            f.model.refresh()
            XCTAssertFalse(f.model.deleteList(id: f.projectID, expectedURL: source))
            XCTAssertEqual(calls, 0)
            XCTAssertEqual(draft(f), "My edit")
            XCTAssertEqual(try storedTask(f).title, "Other edit")
            XCTAssertFalse(f.model.conflicts(itemID: f.task.id).isEmpty)
        }
    }

    func testDeleteTrashFailureKeepsSavedEditsAndEntriesLinked() throws {
        try withFixture { f in
            let source = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            f.model.setText(itemID: f.task.id, field: .notes, value: "Save this work")
            f.model.entryDrafts[f.projectID] = "Keep entry"
            f.store.trashListFile = { _ in throw StoreError.io("Simulated Trash failure") }
            XCTAssertFalse(f.model.deleteList(id: f.projectID, expectedURL: source))
            XCTAssertEqual(f.model.location(for: f.projectID)?.url, source)
            XCTAssertEqual(f.model.selectedProjectID, f.projectID)
            XCTAssertEqual(try storedTask(f).notes, "Save this work")
            XCTAssertEqual(f.model.entryDrafts[f.projectID], "Keep entry")
            XCTAssertTrue(f.model.errorMessage?.contains("remains linked") == true)
        }
    }

    func testDeleteCatalogFailureRetainsMissingListEntriesAndRestoresCleanly() throws {
        try withFixture { f in
            let source = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            let recovered = f.root.appendingPathComponent("synthetic-trash.yaml")
            f.model.entryDrafts[f.projectID] = "Keep unfinished work"
            f.model.setText(itemID: f.task.id, field: .notes, value: "Saved before catalog failure")
            f.store.trashListFile = { url in
                try FileManager.default.moveItem(at: url, to: recovered)
                return recovered
            }
            f.store.beforeDeleteCatalogPublish = { throw StoreError.io("Simulated catalog failure") }
            XCTAssertFalse(f.model.deleteList(id: f.projectID, expectedURL: source))
            XCTAssertEqual(f.model.selectedProjectID, f.projectID)
            XCTAssertTrue(f.model.selectedListIssue?.isMissing == true)
            XCTAssertEqual(f.model.entryDrafts[f.projectID], "Keep unfinished work")
            XCTAssertTrue(f.model.errorMessage?.contains("Restore it from Trash") == true)
            XCTAssertEqual(f.model.selectedProject?.tasks.first?.notes, "Saved before catalog failure")
            try FileManager.default.moveItem(at: recovered, to: source)
            f.model.refresh()
            XCTAssertTrue(f.model.isSelectedListAvailable)
            XCTAssertEqual(f.model.selectedProject?.tasks.first?.notes, "Saved before catalog failure")
            XCTAssertEqual(f.model.entryDrafts[f.projectID], "Keep unfinished work")
        }
    }

    func testDeleteRejectsCapturedPathAfterRelinkingWithoutTrashing() throws {
        try withFixture { f in
            let source = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            let replacement = f.root.appendingPathComponent("relinked.yaml")
            let bytes = try Data(contentsOf: source)
            try bytes.write(to: replacement)
            XCTAssertTrue(f.model.relinkList(id: f.projectID, to: replacement))
            var called = false
            f.store.trashListFile = { url in called = true; return url }
            XCTAssertFalse(f.model.deleteList(id: f.projectID, expectedURL: source))
            XCTAssertFalse(called)
            XCTAssertEqual(try Data(contentsOf: source), bytes)
            XCTAssertEqual(try Data(contentsOf: replacement), bytes)
            XCTAssertEqual(f.model.location(for: f.projectID)?.url, replacement.standardizedFileURL.resolvingSymlinksInPath())
        }
    }

    func testDeletePreservesUndoForAnUnrelatedList() throws {
        try withFixture { f in
            let source = try XCTUnwrap(f.model.location(for: f.projectID)?.url)
            XCTAssertTrue(f.model.createList(name: "Keep"))
            let survivorID = f.model.selectedProjectID
            f.model.addTask("Undo this task")
            XCTAssertTrue(f.model.canUndo)
            let recovered = f.root.appendingPathComponent("synthetic-trash.yaml")
            f.store.trashListFile = { url in
                try FileManager.default.moveItem(at: url, to: recovered)
                return recovered
            }
            XCTAssertTrue(f.model.deleteList(id: f.projectID, expectedURL: source))
            XCTAssertTrue(f.model.canUndo)
            f.model.undo()
            XCTAssertTrue(f.model.workspace.projects.first { $0.id == survivorID }?.tasks.isEmpty == true)
            XCTAssertNil(f.model.location(for: f.projectID))
            XCTAssertTrue(FileManager.default.fileExists(atPath: recovered.path))
        }
    }

}

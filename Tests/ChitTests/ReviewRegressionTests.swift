import Foundation
import XCTest
import TodoCore
@testable import Chit

@MainActor
final class ReviewRegressionTests: XCTestCase {
    @MainActor private struct Fixture {
        let root: URL
        let state: URL
        let store: TodoStore
        let preferences: UserDefaults
        let model: AppModel
        let firstID: String
        let secondID: String
        let firstURL: URL
        let secondURL: URL
        let firstTask: TaskItem
        let secondTask: TaskItem

        func relaunched() -> AppModel {
            AppModel(store: TodoStore(url: store.url, stateDirectory: state), preferences: preferences, watchChanges: false)
        }

        func writeSecond(_ task: TaskItem? = nil) throws {
            try ListFileCodec.encode(ListDocument(project: Project(id: secondID, name: "Healthy", tasks: [task ?? secondTask])))
                .write(to: secondURL)
        }

        func storedSecond() throws -> TaskItem {
            try XCTUnwrap(ListFileCodec.decode(Data(contentsOf: secondURL)).asProject().tasks.first)
        }
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ChitReviewRegression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "ChitReviewRegression.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let state = root.appendingPathComponent("state", isDirectory: true)
        let store = TodoStore(url: root.appendingPathComponent("workspace.json"), stateDirectory: state)
        let firstID = try XCTUnwrap(store.load().projects.first?.id)
        let child = Subtask(title: "Earlier child")
        let firstTask = TaskItem(title: "Earlier title", notes: "Earlier notes", subtasks: [child])
        _ = try store.apply(.addTask(projectID: firstID, task: firstTask, index: nil))
        let secondID = try store.createList(name: "Healthy").id
        let secondTask = TaskItem(id: firstTask.id, title: "Healthy title", notes: "Healthy notes", completed: true,
                                  subtasks: [Subtask(id: child.id, title: "Healthy child", completed: true)])
        let model = AppModel(store: store, preferences: preferences, watchChanges: false)
        let fixture = Fixture(root: root, state: state, store: store, preferences: preferences, model: model,
                              firstID: firstID, secondID: secondID,
                              firstURL: try XCTUnwrap(model.location(for: firstID)?.url),
                              secondURL: try XCTUnwrap(model.location(for: secondID)?.url),
                              firstTask: firstTask, secondTask: secondTask)
        try body(fixture)
    }

    func testHealthyReusedIDsEditToggleAndUndoAgainstHealthyValues() throws {
        try withFixture { f in
            try FileManager.default.removeItem(at: f.firstURL)
            try f.writeSecond()
            f.model.refresh()
            f.model.selectProject(f.secondID)
            XCTAssertNotNil(f.model.issue(for: f.firstID))
            XCTAssertNil(f.model.issue(for: f.secondID))

            f.model.undoManager.groupsByEvent = false
            f.model.undoManager.beginUndoGrouping()
            f.model.setText(itemID: f.secondTask.id, field: .title, value: "Edited healthy title", projectID: f.secondID)
            f.model.setText(itemID: f.secondTask.id, field: .notes, value: "Edited healthy notes", projectID: f.secondID)
            f.model.setText(itemID: f.secondTask.subtasks[0].id, field: .subtaskTitle, value: "Edited healthy child", projectID: f.secondID)
            XCTAssertTrue(f.model.flushPendingEdits())
            f.model.undoManager.endUndoGrouping()
            let edited = try f.storedSecond()
            XCTAssertEqual(edited.title, "Edited healthy title")
            XCTAssertEqual(edited.notes, "Edited healthy notes")
            XCTAssertEqual(edited.subtasks[0].title, "Edited healthy child")
            XCTAssertTrue(edited.completed)
            XCTAssertTrue(edited.subtasks[0].completed)

            f.model.undo()
            XCTAssertEqual(try f.storedSecond(), f.secondTask)
            f.model.redo()
            XCTAssertEqual(try f.storedSecond(), edited)

            // A callback captured before the first list disappeared keeps its owner.
            f.model.toggleTask(f.firstTask, projectID: f.firstID)
            f.model.toggleSubtask(f.firstTask.subtasks[0], projectID: f.firstID)
            XCTAssertEqual(try f.storedSecond(), edited)

            f.model.undoManager.beginUndoGrouping()
            f.model.toggleTask(edited, projectID: f.secondID)
            f.model.toggleSubtask(edited.subtasks[0], projectID: f.secondID)
            f.model.undoManager.endUndoGrouping()
            XCTAssertFalse(try f.storedSecond().completed)
            XCTAssertFalse(try f.storedSecond().subtasks[0].completed)
            f.model.undo()
            XCTAssertEqual(try f.storedSecond(), edited)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.firstURL.path))
        }
    }

    func testInvalidOwnerDraftsCoexistWithHealthySameIDsAcrossRelaunch() throws {
        try withFixture { f in
            let childID = f.firstTask.subtasks[0].id
            f.model.setText(itemID: f.firstTask.id, field: .title, value: "", projectID: f.firstID)
            // Matching another list's value must not satisfy this retained draft.
            f.model.setText(itemID: f.firstTask.id, field: .notes, value: f.secondTask.notes, projectID: f.firstID)
            f.model.setText(itemID: childID, field: .subtaskTitle, value: "", projectID: f.firstID)
            let invalid = Data("version: 1\nname: Broken\ntasks: [\n".utf8)
            try invalid.write(to: f.firstURL)
            try f.writeSecond()
            f.model.refresh()
            f.model.selectProject(f.secondID)
            f.model.setText(itemID: f.secondTask.id, field: .title, value: "", projectID: f.secondID)
            f.model.setText(itemID: childID, field: .subtaskTitle, value: "", projectID: f.secondID)
            f.model.refresh()

            let reopened = f.relaunched()
            for owner in [f.firstID, f.secondID] {
                XCTAssertEqual(reopened.text(itemID: f.firstTask.id, field: .title, fallback: "absent", projectID: owner), "")
                XCTAssertEqual(reopened.text(itemID: childID, field: .subtaskTitle, fallback: "absent", projectID: owner), "")
            }
            XCTAssertEqual(reopened.text(itemID: f.firstTask.id, field: .notes, fallback: "absent", projectID: f.firstID), f.secondTask.notes)
            XCTAssertTrue(reopened.hasRetainedDrafts(listID: f.firstID))
            XCTAssertTrue(reopened.conflicts(itemID: f.firstTask.id, projectID: f.secondID).isEmpty)

            reopened.setText(itemID: f.secondTask.id, field: .title, value: "Saved healthy title", projectID: f.secondID)
            reopened.setText(itemID: f.secondTask.id, field: .notes, value: "Saved healthy notes", projectID: f.secondID)
            reopened.setText(itemID: childID, field: .subtaskTitle, value: "Saved healthy child", projectID: f.secondID)
            XCTAssertTrue(reopened.flushEditsForDismissal())
            XCTAssertEqual(try f.storedSecond().title, "Saved healthy title")
            XCTAssertEqual(try f.storedSecond().notes, "Saved healthy notes")
            XCTAssertEqual(try f.storedSecond().subtasks[0].title, "Saved healthy child")
            XCTAssertTrue(reopened.hasRetainedDrafts(listID: f.firstID))
            XCTAssertFalse(reopened.flushPendingEdits())
            XCTAssertEqual(try Data(contentsOf: f.firstURL), invalid)
        }
    }

    func testUnlinkedOwnerDraftDiscardAndUndoNeverTargetReplacement() throws {
        try withFixture { f in
            f.model.undoManager.groupsByEvent = false
            f.model.undoManager.beginUndoGrouping()
            f.model.setText(itemID: f.firstTask.id, field: .notes, value: "Saved notes", projectID: f.firstID)
            XCTAssertTrue(f.model.flushPendingEdits())
            f.model.undoManager.endUndoGrouping()
            f.model.setText(itemID: f.firstTask.id, field: .title, value: f.secondTask.title, projectID: f.firstID)
            f.model.setText(itemID: f.firstTask.id, field: .notes, value: "Unlinked local notes", projectID: f.firstID)
            let firstBytes = try Data(contentsOf: f.firstURL)
            XCTAssertTrue(f.model.removeList(id: f.firstID))
            var replacement = f.secondTask
            replacement.notes = "Saved notes"
            try f.writeSecond(replacement)
            f.model.refresh()
            f.model.selectProject(f.secondID)

            XCTAssertEqual(f.model.text(itemID: f.firstTask.id, field: .title, fallback: "absent", projectID: f.firstID), replacement.title)
            let orphan = try XCTUnwrap(f.model.orphanedDrafts.first)
            XCTAssertEqual(orphan.notes, "Unlinked local notes")
            f.model.setText(itemID: replacement.id, field: .title, value: "", projectID: f.secondID)
            f.model.discardOrphanedDraft(id: orphan.id)
            XCTAssertEqual(f.model.text(itemID: replacement.id, field: .title, fallback: "absent", projectID: f.secondID), "")
            f.model.setText(itemID: replacement.id, field: .title, value: replacement.title, projectID: f.secondID)

            XCTAssertTrue(f.model.canUndo)
            f.model.undo()
            XCTAssertEqual(try f.storedSecond(), replacement)
            XCTAssertEqual(try Data(contentsOf: f.firstURL), firstBytes)
        }
    }

    func testRemoveRetainsUnsubmittedTaskAndSubtaskEntriesAcrossRelaunchAndReopen() throws {
        try withFixture { f in
            f.model.entryDrafts[f.firstID] = "Unsubmitted task"
            f.model.setSubtaskEntry(parentID: f.firstTask.id, projectID: f.firstID, value: "Unsubmitted child")
            let bytes = try Data(contentsOf: f.firstURL)
            XCTAssertFalse(f.model.canUndo)
            XCTAssertTrue(f.model.removeList(id: f.firstID))
            XCTAssertFalse(f.model.canUndo)
            XCTAssertEqual(f.model.entryDrafts[f.firstID], "Unsubmitted task")
            XCTAssertEqual(f.model.subtaskEntry(parentID: f.firstTask.id, projectID: f.firstID), "Unsubmitted child")

            let reopened = f.relaunched()
            XCTAssertEqual(reopened.entryDrafts[f.firstID], "Unsubmitted task")
            XCTAssertEqual(reopened.subtaskEntry(parentID: f.firstTask.id, projectID: f.firstID), "Unsubmitted child")
            XCTAssertTrue(reopened.openList(at: f.firstURL))
            XCTAssertEqual(reopened.selectedProjectID, f.firstID)
            XCTAssertEqual(reopened.entryDrafts[f.firstID], "Unsubmitted task")
            XCTAssertEqual(reopened.subtaskEntry(parentID: f.firstTask.id, projectID: f.firstID), "Unsubmitted child")
            XCTAssertEqual(try Data(contentsOf: f.firstURL), bytes)
        }
    }

    func testAmbiguousOwnerlessLegacyDraftSurvivesUntilOriginalListIsAvailable() throws {
        try withFixture { f in
            let firstBytes = try Data(contentsOf: f.firstURL)
            let preferenceKey = "workspace." + Data(f.store.url.standardizedFileURL.path.utf8).base64EncodedString()
            let legacyDraft: [String: Any] = ["itemID": f.firstTask.id, "field": "notes",
                                               "base": f.firstTask.notes, "value": f.secondTask.notes]
            f.preferences.set(["selectedProjectID": f.secondID,
                               "drafts": try JSONSerialization.data(withJSONObject: [legacyDraft])], forKey: preferenceKey)
            try FileManager.default.removeItem(at: f.firstURL)
            try f.writeSecond()

            func retainedLegacyDraft() throws -> [String: Any] {
                let saved = try XCTUnwrap(f.preferences.dictionary(forKey: preferenceKey))
                let data = try XCTUnwrap(saved["drafts"] as? Data)
                let drafts = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
                return try XCTUnwrap(drafts.first { $0["value"] as? String == f.secondTask.notes })
            }

            // A fresh model has never seen A's cached task, so B cannot establish
            // ownership of this older preference merely by reusing its ID.
            let model = f.relaunched()
            model.refresh()
            XCTAssertEqual(try retainedLegacyDraft()["base"] as? String, f.firstTask.notes)
            XCTAssertNil(try retainedLegacyDraft()["projectID"])
            XCTAssertEqual(model.text(itemID: f.secondTask.id, field: .notes, fallback: "Healthy editor fallback", projectID: f.secondID), "Healthy editor fallback")
            model.setText(itemID: f.secondTask.id, field: .notes, value: "New healthy notes", projectID: f.secondID)
            XCTAssertTrue(model.flushEditsForDismissal())
            XCTAssertEqual(try f.storedSecond().notes, "New healthy notes")
            XCTAssertFalse(model.flushPendingEdits())
            XCTAssertNil(try retainedLegacyDraft()["projectID"])

            let reopened = f.relaunched()
            reopened.refresh()
            XCTAssertEqual(try retainedLegacyDraft()["value"] as? String, f.secondTask.notes)
            XCTAssertNil(try retainedLegacyDraft()["projectID"])
            XCTAssertEqual(reopened.text(itemID: f.secondTask.id, field: .notes, fallback: "New healthy notes", projectID: f.secondID), "New healthy notes")
            XCTAssertEqual(try f.storedSecond().notes, "New healthy notes")

            // With every file readable and the original task uniquely owned by
            // A, a new load can migrate the legacy preference safely.
            try ListFileCodec.encode(ListDocument(project: Project(id: f.secondID, name: "Healthy"))).write(to: f.secondURL)
            try firstBytes.write(to: f.firstURL)
            let recovered = f.relaunched()
            XCTAssertEqual(recovered.text(itemID: f.firstTask.id, field: .notes, fallback: "absent", projectID: f.firstID), f.secondTask.notes)
            XCTAssertTrue(recovered.flushPendingEdits())
            XCTAssertEqual(try ListFileCodec.decode(Data(contentsOf: f.firstURL)).tasks[0].notes, f.secondTask.notes)
            XCTAssertTrue(try ListFileCodec.decode(Data(contentsOf: f.secondURL)).tasks.isEmpty)
        }
    }
}

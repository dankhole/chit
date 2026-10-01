import Foundation
import XCTest
@testable import TodoCore
@testable import Chit

@MainActor
final class TaskReorderModelTests: XCTestCase {
    private struct Fixture {
        let store: TodoStore
        let external: TodoStore
        let model: AppModel
        let project: Project
        var openTasks: [TaskItem] { project.tasks.filter { !$0.completed } }
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ChitReorderModel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "ChitReorderModel.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let state = root.appendingPathComponent("state")
        let store = TodoStore(url: root.appendingPathComponent("workspace.json"), stateDirectory: state)
        let id = try XCTUnwrap(store.load().projects.first?.id)
        let tasks = [TaskItem(title: "First", notes: "Keep notes", subtasks: [Subtask(title: "Child")]),
                     TaskItem(title: "Done", completed: true), TaskItem(title: "Middle"), TaskItem(title: "Last")]
        _ = try store.apply(.batch(tasks.map { .addTask(projectID: id, task: $0, index: nil) }))
        let project = try XCTUnwrap(store.load().projects.first)
        let model = AppModel(store: store, preferences: preferences, watchChanges: false)
        try body(Fixture(store: store, external: TodoStore(url: store.url, stateDirectory: state), model: model, project: project))
    }

    func testPlacementPersistsAndUndoRetainsSelectionAndConcurrentNotes() throws {
        try withFixture { f in
            let first = f.openTasks[0]
            XCTAssertTrue(f.model.selectTaskForEditing(taskID: first.id, projectID: f.project.id))
            XCTAssertTrue(f.model.toggleDetails(taskID: first.id))
            let order = f.openTasks.map(\.id)
            f.model.setText(itemID: first.id, field: .title, value: "Local draft", projectID: f.project.id)
            _ = try f.external.apply(.patchTask(id: first.id, patch: TaskPatch(notes: .init(expected: first.notes, value: "Concurrent notes"))))
            XCTAssertTrue(f.model.moveTask(first, projectID: f.project.id, to: .after(f.openTasks[2].id), expectedOrder: order))
            XCTAssertEqual(try f.store.load().projects[0].tasks.filter { !$0.completed }.map(\.id), [order[1], order[2], order[0]])
            XCTAssertEqual(f.model.expandedTaskID, first.id)
            XCTAssertEqual(f.model.selectedTaskID, first.id)
            f.model.undo()
            let restored = try f.store.load().projects[0]
            XCTAssertEqual(restored.tasks.map(\.id), f.project.tasks.map(\.id))
            XCTAssertEqual(restored.tasks[0].title, "Local draft")
            XCTAssertEqual(restored.tasks[0].notes, "Concurrent notes")
            XCTAssertEqual(restored.tasks[0].subtasks, first.subtasks)
            XCTAssertEqual(f.model.expandedTaskID, first.id)
            XCTAssertEqual(f.model.selectedTaskID, first.id)
            f.model.redo()
            let redone = try f.store.load().projects[0]
            XCTAssertEqual(redone.tasks.filter { !$0.completed }.map(\.id), [order[1], order[2], order[0]])
            XCTAssertEqual(redone.tasks.first { $0.id == first.id }?.title, "Local draft")
            XCTAssertEqual(redone.tasks.first { $0.id == first.id }?.notes, "Concurrent notes")
        }
    }

    func testCapturedOrderRejectsConcurrentReorderAfterRefresh() throws {
        try withFixture { f in
            let order = f.openTasks.map(\.id)
            _ = try f.external.apply(.reorderTasks(projectID: f.project.id, completed: false,
                change: .init(expected: order, value: Array(order.reversed()))))
            f.model.refresh()
            let afterExternal = try f.store.load()
            XCTAssertFalse(f.model.moveTask(f.openTasks[0], projectID: f.project.id, to: .after(f.openTasks[2].id), expectedOrder: order))
            XCTAssertEqual(try f.store.load(), afterExternal)
            XCTAssertNotNil(f.model.errorMessage)
        }
    }

    func testPlacementRejectsOtherSectionOtherListAndDeletedDestination() throws {
        try withFixture { f in
            let first = f.openTasks[0]
            let other = Project(name: "Other list", tasks: [TaskItem(title: "Other task")])
            _ = try f.external.apply(.addProject(project: other, index: nil))
            f.model.refresh()
            let before = try f.store.load()
            XCTAssertFalse(f.model.moveTask(first, projectID: f.project.id, to: .before(f.project.tasks[1].id)))
            XCTAssertFalse(f.model.moveTask(first, projectID: f.project.id, to: .before(other.tasks[0].id)))
            XCTAssertEqual(try f.store.load(), before)
            let captured = f.openTasks.map(\.id)
            let destination = f.openTasks[2]
            _ = try f.external.apply(.deleteTask(id: destination.id, expected: destination))
            let afterDeletion = try f.store.load()
            XCTAssertFalse(f.model.moveTask(first, projectID: f.project.id, to: .before(destination.id), expectedOrder: captured))
            XCTAssertEqual(try f.store.load(), afterDeletion)
        }
    }

    func testKeyboardMovesStayInSectionAndRespectBounds() throws {
        try withFixture { f in
            let first = f.openTasks[0]
            XCTAssertFalse(f.model.canMoveTask(first, projectID: f.project.id, offset: -1))
            XCTAssertTrue(f.model.canMoveTask(first, projectID: f.project.id, offset: 1))
            XCTAssertTrue(f.model.moveTask(first, projectID: f.project.id, offset: 1))
            let tasks = try f.store.load().projects[0].tasks
            XCTAssertEqual(tasks.filter { !$0.completed }.map(\.id), [f.openTasks[1].id, first.id, f.openTasks[2].id])
            XCTAssertEqual(tasks.filter(\.completed), [f.project.tasks[1]])
            XCTAssertFalse(f.model.moveTask(f.project.tasks[1], projectID: f.project.id, offset: 1))
        }
    }
}

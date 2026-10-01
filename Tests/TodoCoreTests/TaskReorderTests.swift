import Foundation
import XCTest
@testable import TodoCore

final class TaskReorderTests: XCTestCase {
    private struct Fixture {
        let store: TodoStore
        let external: TodoStore
        let project: Project
        var openIDs: [String] { project.tasks.filter { !$0.completed }.map(\.id) }
        var completedIDs: [String] { project.tasks.filter(\.completed).map(\.id) }
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ChitReorderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appendingPathComponent("state")
        let store = TodoStore(url: root.appendingPathComponent("workspace.json"), stateDirectory: state)
        let id = try XCTUnwrap(store.load().projects.first?.id)
        let tasks = [
            TaskItem(title: "First", notes: "Keep notes", deadline: Date(timeIntervalSince1970: 1_800_000_000), subtasks: [Subtask(title: "Child")]),
            TaskItem(title: "Done first", completed: true),
            TaskItem(title: "Middle"), TaskItem(title: "Done last", completed: true), TaskItem(title: "Last")
        ]
        _ = try store.apply(.batch(tasks.map { .addTask(projectID: id, task: $0, index: nil) }))
        let project = try XCTUnwrap(store.load().projects.first)
        try body(Fixture(store: store, external: TodoStore(url: store.url, stateDirectory: state), project: project))
    }

    private func reorder(_ f: Fixture, completed: Bool = false, expected: [String]? = nil, value: [String]) -> StoreOperation {
        .reorderTasks(projectID: f.project.id, completed: completed,
            change: FieldChange(expected: expected ?? (completed ? f.completedIDs : f.openIDs), value: value))
    }

    private func listBytes(_ f: Fixture) throws -> Data {
        try Data(contentsOf: XCTUnwrap(f.store.listLocations[f.project.id]?.url))
    }

    func testSectionReorderPersistsFullTasksWithoutChangingOtherSection() throws {
        try withFixture { f in
            let ids = f.openIDs
            let result = try f.store.apply(reorder(f, value: [ids[2], ids[0], ids[1]]), owningListID: f.project.id)
            let original = f.project.tasks
            XCTAssertEqual(result.workspace.projects[0].tasks, [original[4], original[1], original[0], original[3], original[2]])
            XCTAssertEqual(try f.external.load(), result.workspace)
            let before = try listBytes(f)
            let noop = try f.store.apply(reorder(f, expected: [ids[2], ids[0], ids[1]], value: [ids[2], ids[0], ids[1]]))
            XCTAssertNil(noop.undo)
            XCTAssertEqual(noop.workspace.revision, result.workspace.revision)
            XCTAssertEqual(try listBytes(f), before)
        }
    }

    func testReorderUndoAndRedoPreserveConcurrentContentEdits() throws {
        try withFixture { f in
            let task = f.project.tasks[0]
            let deadline = Date(timeIntervalSince1970: 1_900_000_000)
            _ = try f.external.apply(.batch([
                .patchTask(id: task.id, patch: TaskPatch(title: .init(expected: task.title, value: "Agent title"), deadline: .init(expected: task.deadline, value: deadline))),
                .patchSubtask(id: task.subtasks[0].id, patch: SubtaskPatch(completed: .init(expected: false, value: true)))
            ]))
            let desired = Array(f.openIDs.reversed())
            let moved = try f.store.apply(reorder(f, value: desired))
            _ = try f.external.apply(.patchTask(id: task.id, patch: TaskPatch(notes: .init(expected: task.notes, value: "Agent notes after drag"))))
            let undone = try f.store.apply(XCTUnwrap(moved.undo))
            XCTAssertEqual(undone.workspace.projects[0].tasks.map(\.id), f.project.tasks.map(\.id))
            let latest = try XCTUnwrap(undone.workspace.projects[0].tasks.first { $0.id == task.id })
            XCTAssertEqual(latest.title, "Agent title")
            XCTAssertEqual(latest.notes, "Agent notes after drag")
            XCTAssertEqual(latest.deadline, deadline)
            XCTAssertTrue(latest.subtasks[0].completed)
            let redone = try f.store.apply(XCTUnwrap(undone.undo))
            XCTAssertEqual(redone.workspace.projects[0].tasks.filter { !$0.completed }.map(\.id), desired)
            XCTAssertEqual(redone.workspace.projects[0].tasks.first { $0.id == task.id }, latest)
        }
    }

    func testMalformedPermutationsAreRejectedWithoutWriting() throws {
        try withFixture { f in
            let ids = f.openIDs
            let before = try listBytes(f)
            for invalid in [[ids[0], ids[1]], [ids[0], ids[0], ids[2]], [ids[0], f.completedIDs[0], ids[2]], [ids[0], ids[1], UUID().uuidString]] {
                XCTAssertThrowsError(try f.store.apply(reorder(f, value: invalid))) { error in
                    guard case StoreError.invalid = error else { return XCTFail("\(error)") }
                }
                XCTAssertEqual(try listBytes(f), before)
            }
        }
    }

    func testStaleAdditionDeletionAndCompletionRejectPlacement() throws {
        for change in 0..<3 {
            try withFixture { f in
                let task = f.project.tasks[0]
                switch change {
                case 0: _ = try f.external.apply(.addTask(projectID: f.project.id, task: TaskItem(title: "Agent addition"), index: nil))
                case 1: _ = try f.external.apply(.deleteTask(id: task.id, expected: task))
                default: _ = try f.external.apply(.patchTask(id: task.id, patch: TaskPatch(completed: .init(expected: false, value: true))))
                }
                let before = try listBytes(f)
                XCTAssertThrowsError(try f.store.apply(reorder(f, value: Array(f.openIDs.reversed())))) { error in
                    guard case StoreError.conflict = error else { return XCTFail("\(error)") }
                }
                XCTAssertEqual(try listBytes(f), before)
            }
        }
    }

    func testStaleReorderAndUndoCannotReplaceNewerOrder() throws {
        try withFixture { f in
            let ids = f.openIDs
            let firstOrder = [ids[2], ids[0], ids[1]]
            let first = try f.store.apply(reorder(f, value: firstOrder))
            let latestOrder = [ids[1], ids[2], ids[0]]
            _ = try f.external.apply(reorder(f, expected: firstOrder, value: latestOrder))
            let before = try listBytes(f)
            XCTAssertThrowsError(try f.store.apply(reorder(f, value: latestOrder)))
            XCTAssertThrowsError(try f.store.apply(XCTUnwrap(first.undo)))
            XCTAssertEqual(try listBytes(f), before)
            XCTAssertEqual(try f.store.load().projects[0].tasks.filter { !$0.completed }.map(\.id), latestOrder)
        }
    }

    func testOtherSectionReorderDoesNotInvalidatePlacement() throws {
        try withFixture { f in
            _ = try f.external.apply(reorder(f, completed: true, value: Array(f.completedIDs.reversed())))
            let result = try f.store.apply(reorder(f, value: Array(f.openIDs.reversed())))
            XCTAssertEqual(result.workspace.projects[0].tasks.filter(\.completed).map(\.id), Array(f.completedIDs.reversed()))
            XCTAssertEqual(result.workspace.projects[0].tasks.filter { !$0.completed }.map(\.id), Array(f.openIDs.reversed()))
        }
    }

    func testDirectListFileReorderRoutesIdentityAndLeavesOtherListsUntouched() throws {
        try withFixture { f in
            let other = Project(name: "Unchanged", tasks: [TaskItem(title: "Other task")])
            _ = try f.store.apply(.addProject(project: other, index: nil))
            let otherURL = try XCTUnwrap(f.store.listLocations[other.id]?.url)
            let otherBytes = try Data(contentsOf: otherURL)
            let file = ListFileStore(url: try XCTUnwrap(f.store.listLocations[f.project.id]?.url))
            let moved = try file.apply(reorder(f, value: Array(f.openIDs.reversed())))
            XCTAssertEqual(try file.load().asProject().tasks.filter { !$0.completed }.map(\.id), Array(f.openIDs.reversed()))
            _ = try file.apply(XCTUnwrap(moved.undo))
            XCTAssertEqual(try file.load().asProject(), f.project)
            XCTAssertEqual(try Data(contentsOf: otherURL), otherBytes)
            XCTAssertThrowsError(try file.apply(.reorderTasks(projectID: other.id, completed: false,
                change: .init(expected: [other.tasks[0].id], value: [other.tasks[0].id]))))
        }
    }
}

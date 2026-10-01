import Foundation
import XCTest
@testable import TodoCore

final class DeadlineTests: XCTestCase {
    private var directory: URL!
    private var store: ListFileStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("chit-deadline-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ListFileStore(url: directory.appendingPathComponent("todo.yaml"), stateDirectory: directory.appendingPathComponent("state"))
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testOldYAMLAndJSONLoadWithoutDeadlineAndNilIsOmitted() throws {
        let oldYAML = Data("version: 1\nname: Old list\ntasks:\n  - title: Existing task\n".utf8)
        let document = try ListFileCodec.decode(oldYAML)
        XCTAssertNil(document.tasks[0].deadline)
        XCTAssertFalse(String(decoding: try ListFileCodec.encode(document), as: UTF8.self).contains("deadline:"))
        let oldJSON = Data("{\"id\":\"old-task\",\"title\":\"Existing\",\"notes\":\"\",\"completed\":false,\"subtasks\":[]}".utf8)
        let task = try JSONDecoder().decode(TaskItem.self, from: oldJSON)
        XCTAssertNil(task.deadline)
        let taskJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
        XCTAssertNil(taskJSON["deadline"])
        let listJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document.tasks[0])) as? [String: Any])
        XCTAssertNil(listJSON["deadline"])
        XCTAssertEqual(try JSONDecoder().decode(ListTask.self, from: JSONEncoder().encode(document.tasks[0])), document.tasks[0])
    }

    func testTimestampOffsetsNormalizeAndFractionalDatesRoundTripExactly() throws {
        let offset = try XCTUnwrap(DeadlineTimestamp.parse("2026-10-01T17:30:00.123456789-04:00"))
        XCTAssertEqual(offset, DeadlineTimestamp.parse("2026-10-01T21:30:00.123456789Z"))
        XCTAssertEqual(DeadlineTimestamp.parse("2026-10-02T03:00:00+05:30"), DeadlineTimestamp.parse("2026-10-01T21:30:00Z"))
        let dates = [offset, Date(), Date(timeIntervalSinceReferenceDate: 812_345_678.1234567), Date(timeIntervalSinceReferenceDate: -30_000_000.98765)]
        for date in dates {
            XCTAssertEqual(DeadlineTimestamp.parse(try DeadlineTimestamp.format(date)), date)
            let task = TaskItem(title: "Keep precision", deadline: date, subtasks: [Subtask(title: "Child")])
            let project = Project(name: "Dates", tasks: [task])
            let document = ListDocument(project: project)
            let encoded = try ListFileCodec.encode(document)
            XCTAssertEqual(try ListFileCodec.decode(encoded), document)
            XCTAssertEqual(try document.asProject(), project)
            XCTAssertEqual(try document.normalized().asProject(), project)
            XCTAssertEqual(try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task)), task)
            XCTAssertEqual(try JSONDecoder().decode(ListTask.self, from: JSONEncoder().encode(document.tasks[0])), document.tasks[0])
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
            XCTAssertEqual(json["deadline"] as? String, try DeadlineTimestamp.format(date))
        }
        XCTAssertEqual(try DeadlineTimestamp.format(XCTUnwrap(DeadlineTimestamp.parse("2026-10-01T17:30:00-04:00"))), "2026-10-01T21:30:00Z")
    }

    func testMalformedDeadlineIsRejectedWithFieldLocation() throws {
        let values = ["null", "123", "true", "2026-10-01", "2026-10-01T17:30:00", "2026-02-30T17:30:00Z", "2026-10-01T24:00:00Z", "2026-10-01T17:30:60Z", "2026-10-01T17:30:00+24:00", "2026-10-01T17:30:00-04:60", "0000-10-01T17:30:00Z", "nonsense"]
        for value in values {
            let yaml = "version: 1\nname: Invalid\ntasks:\n  - title: Task\n    deadline: \(value)\n"
            XCTAssertThrowsError(try ListFileCodec.decode(Data(yaml.utf8)), value) { error in
                let invalid = error as? ListFileError
                XCTAssertEqual(invalid?.path, "tasks[0].deadline")
                XCTAssertEqual(invalid?.line, 5)
                XCTAssertTrue(invalid?.message.contains("explicit timezone") == true)
            }
        }
        XCTAssertThrowsError(try ListFileCodec.decode(Data("version: 1\nname: Invalid\ntasks: [{title: Parent, subtasks: [{title: Child, deadline: 2026-10-01T17:30:00Z}]}]\n".utf8)))
        XCTAssertThrowsError(try ListFileCodec.encode(ListDocument(name: "Invalid", tasks: [ListTask(title: "Invalid", deadline: Date(timeIntervalSinceReferenceDate: .nan))])))
    }

    func testOverdueStartsAfterDeadlineAndCompletedTasksAreExcluded() throws {
        let deadline = try XCTUnwrap(DeadlineTimestamp.parse("2026-10-01T17:30:00Z"))
        var task = TaskItem(title: "Timed task", deadline: deadline)
        XCTAssertFalse(task.isOverdue(at: deadline.addingTimeInterval(-1)))
        XCTAssertFalse(task.isOverdue(at: deadline))
        XCTAssertTrue(task.isOverdue(at: deadline.addingTimeInterval(0.001)))
        task.completed = true
        XCTAssertFalse(task.isOverdue(at: deadline.addingTimeInterval(86400)))
        task.completed = false
        XCTAssertTrue(task.isOverdue(at: deadline.addingTimeInterval(86400)))
        task.deadline = nil
        XCTAssertFalse(task.isOverdue(at: deadline.addingTimeInterval(86400)))
    }

    func testSetClearUndoAndRedoPersistAndPreserveUnrelatedEdits() throws {
        let deadline = Date(timeIntervalSinceReferenceDate: 812_345_678.1234567)
        let task = TaskItem(title: "Original", subtasks: [Subtask(title: "Child")])
        _ = try store.create(ListDocument(project: Project(name: "List", tasks: [task])))
        let edit = try store.apply(.patchTask(id: task.id, patch: .init(deadline: .init(expected: nil, value: deadline))))
        XCTAssertEqual(edit.workspace.projects[0].tasks[0].deadline, deadline)
        let repeated = try store.apply(.patchTask(id: task.id, patch: .init(deadline: .init(expected: nil, value: deadline))))
        XCTAssertNil(repeated.undo)
        _ = try store.apply(.patchTask(id: task.id, patch: .init(title: .init(expected: "Original", value: "Agent title"), notes: .init(expected: "", value: "Agent notes"))))
        _ = try store.apply(.patchSubtask(id: task.subtasks[0].id, patch: .init(completed: .init(expected: false, value: true))))
        let undo = try store.apply(XCTUnwrap(edit.undo))
        let restored = try store.load().tasks[0]
        XCTAssertNil(restored.deadline)
        XCTAssertEqual(restored.title, "Agent title")
        XCTAssertEqual(restored.notes, "Agent notes")
        XCTAssertTrue(restored.subtasks[0].completed)
        _ = try store.apply(XCTUnwrap(undo.undo))
        XCTAssertEqual(try store.load().tasks[0].deadline, deadline)
        let clear = try store.apply(.patchTask(id: task.id, patch: .init(deadline: .init(expected: deadline, value: nil))))
        XCTAssertNil(try store.load().tasks[0].deadline)
        XCTAssertFalse(String(decoding: try Data(contentsOf: store.url), as: UTF8.self).contains("deadline:"))
        _ = try store.apply(XCTUnwrap(clear.undo))
        let reopened = ListFileStore(url: store.url, stateDirectory: directory.appendingPathComponent("state"))
        XCTAssertEqual(try reopened.load().tasks[0].deadline, deadline)
    }

    func testStaleDeadlineEditAndUndoConflictPreserveLatestBytes() throws {
        let first = try XCTUnwrap(DeadlineTimestamp.parse("2026-10-01T17:30:00Z"))
        let second = first.addingTimeInterval(3600)
        let third = second.addingTimeInterval(3600)
        let task = TaskItem(title: "Original", deadline: first)
        _ = try store.create(ListDocument(project: Project(name: "List", tasks: [task])))
        let edit = try store.apply(.patchTask(id: task.id, patch: .init(deadline: .init(expected: first, value: second))))
        let before = try Data(contentsOf: store.url)
        XCTAssertThrowsError(try store.apply(.patchTask(id: task.id, patch: .init(title: .init(expected: "Original", value: "Must not save"), deadline: .init(expected: first, value: third))))) { error in
            guard case StoreError.conflict(let message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("deadline"))
        }
        XCTAssertEqual(try Data(contentsOf: store.url), before)
        _ = try store.apply(.patchTask(id: task.id, patch: .init(deadline: .init(expected: second, value: third))))
        let latest = try Data(contentsOf: store.url)
        XCTAssertThrowsError(try store.apply(XCTUnwrap(edit.undo)))
        XCTAssertEqual(try Data(contentsOf: store.url), latest)
        XCTAssertEqual(try store.load().tasks[0].deadline, third)
    }
}

import XCTest
import Foundation
import Darwin
@testable import TodoCore

final class TodoStoreTests: XCTestCase {
    private var directory: URL!
    private var store: TodoStore!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = TodoStore(url: directory.appendingPathComponent("workspace.json"), stateDirectory: directory.appendingPathComponent("file-state"))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testConcurrentFirstLaunchCreatesOneInbox() throws {
        let results = ConcurrentResults<Workspace>()
        let url = store.url
        DispatchQueue.concurrentPerform(iterations: 24) { _ in
            results.capture { try TodoStore(url: url, stateDirectory: url.deletingLastPathComponent().appendingPathComponent("file-state")).load() }
        }
        XCTAssertTrue(results.errors.isEmpty, "\(results.errors)")
        XCTAssertEqual(results.values.count, 24)
        XCTAssertEqual(Set(results.values.flatMap { $0.projects.map(\.id) }).count, 1)
        XCTAssertEqual(try store.load().projects.first?.name, "Inbox")
    }

    func testConcurrentAdditionsAndUnrelatedPatchesSurvive() throws {
        let project = try XCTUnwrap(store.load().projects.first)
        let task = TaskItem(title: "Original")
        _ = try store.apply(.addTask(projectID: project.id, task: task, index: nil))
        let results = ConcurrentResults<Workspace>()
        let url = store.url
        DispatchQueue.concurrentPerform(iterations: 32) { i in
            results.capture {
                try TodoStore(url: url, stateDirectory: url.deletingLastPathComponent().appendingPathComponent("file-state")).apply(.addTask(projectID: project.id, task: TaskItem(title: "Task \(i)"), index: nil)).workspace
            }
        }
        DispatchQueue.concurrentPerform(iterations: 2) { i in
            results.capture {
                let patch = i == 0 ? TaskPatch(notes: .init(expected: "", value: "Agent notes")) : TaskPatch(completed: .init(expected: false, value: true))
                return try TodoStore(url: url, stateDirectory: url.deletingLastPathComponent().appendingPathComponent("file-state")).apply(.patchTask(id: task.id, patch: patch)).workspace
            }
        }
        XCTAssertTrue(results.errors.isEmpty, "\(results.errors)")
        let workspace = try store.load()
        XCTAssertEqual(workspace.projects[0].tasks.count, 33)
        XCTAssertEqual(workspace.projects[0].tasks[0].notes, "Agent notes")
        XCTAssertTrue(workspace.projects[0].tasks[0].completed)
        XCTAssertEqual(workspace.revision, 35)
    }

    func testSameFieldConflictPreservesBytesAndReturnsCurrentValue() throws {
        let task = try addTask()
        _ = try store.apply(.patchTask(id: task.id, patch: .init(title: .init(expected: task.title, value: "Remote title"))))
        let before = try authoritativeBytes()
        XCTAssertThrowsError(try store.apply(.patchTask(id: task.id, patch: .init(title: .init(expected: task.title, value: "Local title"))))) { error in
            guard case StoreError.conflict(let message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("Remote title"))
        }
        XCTAssertEqual(try authoritativeBytes(), before)
    }

    func testAlreadyDesiredValueIsNoopEvenWithStaleExpectedValue() throws {
        let task = try addTask()
        let operation = StoreOperation.patchTask(id: task.id, patch: .init(completed: .init(expected: false, value: true)))
        let first = try store.apply(operation)
        let repeated = try store.apply(operation)
        XCTAssertEqual(repeated.workspace, first.workspace)
        XCTAssertNil(repeated.undo)
    }

    func testAtomicPatchAndBatchRejectAllOnConflictOrInvalidTitle() throws {
        let task = try addTask()
        let before = try authoritativeBytes()
        XCTAssertThrowsError(try store.apply(.patchTask(id: task.id, patch: .init(title: .init(expected: task.title, value: "Changed"), notes: .init(expected: "wrong", value: "notes")))))
        XCTAssertEqual(try authoritativeBytes(), before)
        XCTAssertThrowsError(try store.apply(.batch([
            .patchTask(id: task.id, patch: .init(completed: .init(expected: false, value: true))),
            .patchTask(id: task.id, patch: .init(title: .init(expected: task.title, value: " \n\t")))
        ])))
        XCTAssertEqual(try authoritativeBytes(), before)
    }

    func testGranularUndoAndRedoPreserveAgentChanges() throws {
        let task = try addTask()
        let edit = try store.apply(.patchTask(id: task.id, patch: .init(title: .init(expected: task.title, value: "My title"))))
        _ = try store.apply(.patchTask(id: task.id, patch: .init(notes: .init(expected: "", value: "Agent notes"))))
        let added = try addTask(title: "Agent addition")
        let undo = try store.apply(XCTUnwrap(edit.undo))
        XCTAssertEqual(undo.workspace.projects[0].tasks.first?.title, task.title)
        XCTAssertEqual(undo.workspace.projects[0].tasks.first?.notes, "Agent notes")
        XCTAssertTrue(undo.workspace.projects[0].tasks.contains { $0.id == added.id })
        let redo = try store.apply(XCTUnwrap(undo.undo))
        XCTAssertEqual(redo.workspace.projects[0].tasks.first?.title, "My title")
        XCTAssertEqual(redo.workspace.projects[0].tasks.first?.notes, "Agent notes")
    }

    func testUndoConflictsWithInterveningSameFieldEdit() throws {
        let task = try addTask()
        let edit = try store.apply(.patchTask(id: task.id, patch: .init(title: .init(expected: task.title, value: "Mine"))))
        _ = try store.apply(.patchTask(id: task.id, patch: .init(title: .init(expected: "Mine", value: "Theirs"))))
        XCTAssertThrowsError(try store.apply(XCTUnwrap(edit.undo)))
        XCTAssertEqual(try store.load().projects[0].tasks[0].title, "Theirs")
    }

    func testDeleteUndoRestoresChildrenWithoutRemovingAgentAddition() throws {
        let project = try XCTUnwrap(store.load().projects.first)
        let child = Subtask(title: "Child", completed: true)
        let task = TaskItem(title: "Parent", notes: "Keep notes", subtasks: [child])
        _ = try store.apply(.addTask(projectID: project.id, task: task, index: nil))
        let deleted = try store.apply(.deleteTask(id: task.id, expected: task))
        let added = try addTask(title: "Agent addition")
        let restored = try store.apply(XCTUnwrap(deleted.undo)).workspace
        XCTAssertEqual(restored.projects[0].tasks, [task, added])
    }

    func testStaleDeleteCannotEraseChangedChildren() throws {
        let task = try addTask()
        _ = try store.apply(.addSubtask(parentID: task.id, subtask: Subtask(title: "New child"), index: nil))
        XCTAssertThrowsError(try store.apply(.deleteTask(id: task.id, expected: task)))
        XCTAssertEqual(try store.load().projects[0].tasks[0].subtasks.count, 1)
    }

    func testParentAndChildCompletionAreIndependent() throws {
        let task = try addTask()
        let child = Subtask(title: "Child")
        _ = try store.apply(.addSubtask(parentID: task.id, subtask: child, index: nil))
        _ = try store.apply(.patchTask(id: task.id, patch: .init(completed: .init(expected: false, value: true))))
        XCTAssertFalse(try store.load().projects[0].tasks[0].subtasks[0].completed)
        _ = try store.apply(.patchSubtask(id: child.id, patch: .init(completed: .init(expected: false, value: true))))
        _ = try store.apply(.patchTask(id: task.id, patch: .init(completed: .init(expected: true, value: false))))
        XCTAssertTrue(try store.load().projects[0].tasks[0].subtasks[0].completed)
    }

    func testGroupDeletionUndoAndConflictAreAtomic() throws {
        let project = try XCTUnwrap(store.load().projects.first)
        let group = ProjectGroup(name: "Work")
        let other = ProjectGroup(name: "Other")
        _ = try store.apply(.batch([
            .addGroup(group: group, index: nil), .addGroup(group: other, index: nil),
            .patchProject(id: project.id, name: nil, groupID: .init(expected: nil, value: group.id))
        ]))
        let removal = try store.apply(.deleteGroup(id: group.id, expected: group))
        XCTAssertNil(removal.workspace.projects[0].groupID)
        let restoration = try store.apply(XCTUnwrap(removal.undo))
        XCTAssertEqual(restoration.workspace.projects[0].groupID, group.id)
        let secondRemoval = try store.apply(XCTUnwrap(restoration.undo))
        _ = try store.apply(.patchProject(id: project.id, name: nil, groupID: .init(expected: nil, value: other.id)))
        XCTAssertThrowsError(try store.apply(XCTUnwrap(secondRemoval.undo)))
        let final = try store.load()
        XCTAssertEqual(final.groups, [other])
        XCTAssertEqual(final.projects[0].groupID, other.id)
    }

    func testUndoGroupCreationCannotRemoveLaterProjectAssignments() throws {
        let project = try XCTUnwrap(store.load().projects.first)
        let group = ProjectGroup(name: "Work")
        let creation = try store.apply(.addGroup(group: group, index: nil))
        _ = try store.apply(.patchProject(id: project.id, name: nil, groupID: .init(expected: nil, value: group.id)))
        let before = try authoritativeBytes()
        XCTAssertThrowsError(try store.apply(XCTUnwrap(creation.undo)))
        XCTAssertEqual(try authoritativeBytes(), before)
    }

    func testProjectReorderPersistsAndRepeatedDesiredOrderIsNoop() throws {
        let original = try addProjectsForReordering()
        let reordered = [original[2], original[0], original[1]]
        let operation = StoreOperation.reorderProjects(change: .init(expected: original, value: reordered))
        let result = try store.apply(operation)
        XCTAssertEqual(result.workspace.projects.map(\.id), reordered)
        XCTAssertEqual(try TodoStore(url: store.url, stateDirectory: directory.appendingPathComponent("file-state")).load().projects.map(\.id), reordered)
        let before = try authoritativeBytes()
        let repeated = try store.apply(operation)
        XCTAssertEqual(repeated.workspace.revision, result.workspace.revision)
        XCTAssertNil(repeated.undo)
        XCTAssertEqual(try authoritativeBytes(), before)
    }

    func testProjectReorderAndUndoPreserveLatestTaskAndProjectEdits() throws {
        let original = try addProjectsForReordering()
        let task = TaskItem(title: "Task")
        _ = try store.apply(.addTask(projectID: original[0], task: task, index: nil))
        let reordered = [original[2], original[0], original[1]]
        // The reorder's expected value predates these content changes, which must still merge.
        _ = try store.apply(.patchTask(id: task.id, patch: .init(notes: .init(expected: "", value: "Agent notes"))))
        let result = try store.apply(.reorderProjects(change: .init(expected: original, value: reordered)))
        _ = try store.apply(.patchTask(id: task.id, patch: .init(completed: .init(expected: false, value: true))))
        _ = try store.apply(.patchProject(id: original[0], name: .init(expected: "Inbox", value: "Renamed Inbox"), groupID: nil))
        let added = TaskItem(title: "Agent addition")
        _ = try store.apply(.addTask(projectID: original[0], task: added, index: nil))
        let undone = try store.apply(XCTUnwrap(result.undo))
        XCTAssertEqual(undone.workspace.projects.map(\.id), original)
        XCTAssertEqual(undone.workspace.projects[0].name, "Renamed Inbox")
        XCTAssertEqual(undone.workspace.projects[0].tasks[0].notes, "Agent notes")
        XCTAssertTrue(undone.workspace.projects[0].tasks[0].completed)
        XCTAssertEqual(undone.workspace.projects[0].tasks[1], added)
        let redone = try store.apply(XCTUnwrap(undone.undo))
        XCTAssertEqual(redone.workspace.projects.map(\.id), reordered)
        XCTAssertEqual(redone.workspace.projects[1], undone.workspace.projects[0])
    }

    func testProjectReorderRejectsInvalidPermutationsWithoutChangingBytes() throws {
        let original = try addProjectsForReordering()
        let invalidOrders = [
            Array(original.dropLast()),
            original + [original[0]],
            [original[0], original[0], original[2]],
            [original[0], UUID().uuidString, original[2]]
        ]
        let before = try authoritativeBytes()
        for invalid in invalidOrders {
            XCTAssertThrowsError(try store.apply(.reorderProjects(change: .init(expected: original, value: invalid)))) { error in
                guard case StoreError.invalid = error else { return XCTFail("Expected invalid permutation, got \(error)") }
            }
            XCTAssertEqual(try authoritativeBytes(), before)
        }
    }

    func testProjectReorderRejectsStaleAdditionAndRollsBackGroupMove() throws {
        let original = try addProjectsForReordering()
        let group = ProjectGroup(name: "Work")
        let added = Project(name: "Agent project")
        _ = try store.apply(.batch([.addGroup(group: group, index: nil), .addProject(project: added, index: nil)]))
        let before = try authoritativeBytes()
        XCTAssertThrowsError(try store.apply(.batch([
            .patchProject(id: original[0], name: nil, groupID: .init(expected: nil, value: group.id)),
            .reorderProjects(change: .init(expected: original, value: Array(original.reversed())))
        ]))) { error in
            guard case StoreError.conflict = error else { return XCTFail("Expected stale order conflict, got \(error)") }
        }
        XCTAssertEqual(try authoritativeBytes(), before)
        XCTAssertEqual(try store.load().projects.last, added)
        XCTAssertNil(try store.load().projects[0].groupID)
    }

    func testProjectReorderAndUndoRejectInterveningOrderChanges() throws {
        let original = try addProjectsForReordering()
        let firstOrder = [original[1], original[0], original[2]]
        let first = try store.apply(.reorderProjects(change: .init(expected: original, value: firstOrder)))
        let secondOrder = [original[2], original[1], original[0]]
        _ = try store.apply(.reorderProjects(change: .init(expected: firstOrder, value: secondOrder)))
        let before = try authoritativeBytes()
        for operation in [
            StoreOperation.reorderProjects(change: .init(expected: original, value: firstOrder)),
            try XCTUnwrap(first.undo)
        ] {
            XCTAssertThrowsError(try store.apply(operation)) { error in
                guard case StoreError.conflict = error else { return XCTFail("Expected stale order conflict, got \(error)") }
            }
            XCTAssertEqual(try authoritativeBytes(), before)
        }
    }

    func testProjectGroupMoveAndReorderUndoTogetherWithoutLosingContent() throws {
        let original = try addProjectsForReordering()
        let group = ProjectGroup(name: "Work")
        _ = try store.apply(.addGroup(group: group, index: nil))
        let moved = try store.apply(.batch([
            .patchProject(id: original[0], name: nil, groupID: .init(expected: nil, value: group.id)),
            .reorderProjects(change: .init(expected: original, value: [original[1], original[2], original[0]]))
        ]))
        XCTAssertEqual(moved.workspace.projects.last?.groupID, group.id)
        let task = TaskItem(title: "Added after drag")
        _ = try store.apply(.addTask(projectID: original[0], task: task, index: nil))
        let undone = try store.apply(XCTUnwrap(moved.undo))
        XCTAssertEqual(undone.workspace.projects.map(\.id), original)
        XCTAssertNil(undone.workspace.projects[0].groupID)
        XCTAssertEqual(undone.workspace.projects[0].tasks, [task])
    }

    func testValidationAllowsZeroListsAndRejectsDuplicateIDsAndMissingParents() throws {
        let project = try XCTUnwrap(store.load().projects.first)
        XCTAssertThrowsError(try store.apply(.addProject(project: project, index: nil)))
        XCTAssertThrowsError(try store.apply(.addTask(projectID: UUID().uuidString, task: TaskItem(title: "Lost"), index: nil)))
        XCTAssertThrowsError(try store.apply(.patchProject(id: project.id, name: nil, groupID: .init(expected: nil, value: UUID().uuidString))))
        XCTAssertThrowsError(try store.apply(.addTask(projectID: project.id, task: TaskItem(id: project.id, title: "Duplicate"), index: nil)))
        XCTAssertEqual(try store.load().projects, [project])
        _ = try store.apply(.deleteProject(id: project.id, expected: project))
        XCTAssertTrue(try store.load().projects.isEmpty)
    }

    func testMalformedAndUnsupportedDataIsNeverReinitialized() throws {
        for bytes in [Data("{bad json".utf8), try JSONEncoder().encode(Workspace(schemaVersion: 99, projects: [Project(name: "Future")]))] {
            try bytes.write(to: store.url)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.apply(.addGroup(group: ProjectGroup(name: "Work"), index: nil)))
            XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        }
    }

    func testNestedChildrenAreRejectedRatherThanSilentlyLost() throws {
        let task = TaskItem(title: "Parent", subtasks: [Subtask(title: "Child")])
        let workspace = Workspace(projects: [Project(name: "Inbox", tasks: [task])])
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        var projects = try XCTUnwrap(root["projects"] as? [[String: Any]])
        var tasks = try XCTUnwrap(projects[0]["tasks"] as? [[String: Any]])
        var children = try XCTUnwrap(tasks[0]["subtasks"] as? [[String: Any]])
        children[0]["subtasks"] = [["id": UUID().uuidString, "title": "Grandchild", "completed": false]]
        tasks[0]["subtasks"] = children; projects[0]["tasks"] = tasks; root["projects"] = projects
        let bytes = try JSONSerialization.data(withJSONObject: root)
        try bytes.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
    }

    func testBoundedValidBackupsAndRecoveryPreserveCorruptBytes() throws {
        store = TodoStore(url: store.url, backupLimit: 3, backupInterval: 0, stateDirectory: directory.appendingPathComponent("file-state"))
        for i in 0..<7 { _ = try addTask(title: "Task \(i)") }
        let backups = try store.backups()
        XCTAssertEqual(backups.count, 3)
        let selected = try XCTUnwrap(backups.first)
        let backedUp = try ListFileCodec.decode(Data(contentsOf: selected.url)).asProject()
        let projectID = try XCTUnwrap(store.load().projects.first?.id)
        let fileURL = try XCTUnwrap(store.listLocations[projectID]?.url)
        let corrupted = Data("accidentally damaged task file".utf8)
        try corrupted.write(to: fileURL)
        let restored = try store.restoreBackup(at: selected.url, listID: projectID)
        XCTAssertEqual(restored.projects, [backedUp])
        let recovery = historyDirectory(projectID).appendingPathComponent("recovery")
        let files = try FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.first)), corrupted)
        XCTAssertEqual(try store.load(), restored)
        try Data("invalid backup".utf8).write(to: selected.url)
        XCTAssertEqual(try store.backups().count, 2)
        XCTAssertThrowsError(try store.restoreBackup(at: selected.url, listID: projectID))
        XCTAssertEqual(try store.load(), restored)
    }

    func testFailedBackupOrRecoveryDoesNotReplaceCurrentDocument() throws {
        let project = try XCTUnwrap(store.load().projects.first)
        let file = try XCTUnwrap(store.listLocations[project.id]?.url)
        let before = try Data(contentsOf: file)
        let history = historyDirectory(project.id)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        try Data("blocked directory".utf8).write(to: history.appendingPathComponent("backups"))
        XCTAssertThrowsError(try store.apply(.addTask(projectID: project.id, task: TaskItem(title: "Must not appear"), index: nil)))
        XCTAssertEqual(try Data(contentsOf: file), before)
        let candidate = directory.appendingPathComponent("candidate.yaml")
        try before.write(to: candidate)
        try Data("blocked recovery".utf8).write(to: history.appendingPathComponent("recovery"))
        XCTAssertThrowsError(try store.restoreBackup(at: candidate, listID: project.id))
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    private func authoritativeBytes() throws -> [String: Data] {
        var bytes = [store.catalogURL.path: try Data(contentsOf: store.catalogURL)]
        for location in store.listLocations.values { bytes[location.url.path] = try Data(contentsOf: location.url) }
        return bytes
    }

    private func historyDirectory(_ id: String) -> URL {
        directory.appendingPathComponent("file-state/documents")
            .appendingPathComponent(FilePersistence.fingerprint("list:" + (UUID(uuidString: id)?.uuidString ?? id)))
    }

    func testLockTimeoutIsFiniteAndLeavesDataIntact() throws {
        _ = try store.load()
        let before = try authoritativeBytes()
        let descriptor = open(store.url.path + ".lock", O_RDWR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try store.load())
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 3)
        XCTAssertEqual(try authoritativeBytes(), before)
    }

    private func addTask(title: String = "Original") throws -> TaskItem {
        let projectID = try XCTUnwrap(store.load().projects.first?.id)
        let task = TaskItem(title: title)
        _ = try store.apply(.addTask(projectID: projectID, task: task, index: nil))
        return task
    }

    private func addProjectsForReordering() throws -> [String] {
        let result = try store.apply(.batch([
            .addProject(project: Project(name: "Second"), index: nil),
            .addProject(project: Project(name: "Third"), index: nil)
        ]))
        return result.workspace.projects.map(\.id)
    }
}

private final class ConcurrentResults<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [Value] = []
    private(set) var errors: [Error] = []
    func capture(_ body: () throws -> Value) {
        do { let value = try body(); lock.lock(); values.append(value); lock.unlock() }
        catch { lock.lock(); errors.append(error); lock.unlock() }
    }
}

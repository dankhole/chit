import XCTest
import Foundation
@testable import TodoCore

final class CatalogMigrationTests: XCTestCase {
    private var directory: URL!
    private var store: TodoStore!
    private var state: URL { directory.appendingPathComponent("file-state", isDirectory: true) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChitCatalogTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = newStore()
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func newStore() -> TodoStore {
        TodoStore(url: directory.appendingPathComponent("workspace.json"), backupInterval: 0, stateDirectory: state)
    }
    private func linkedURL(_ id: String) throws -> URL { try XCTUnwrap(store.listLocations[id]?.url) }
    private func file(_ url: URL, id: String? = nil) -> ListFileStore { ListFileStore(url: url, listID: id, stateDirectory: state, backupInterval: 0) }
    private func legacyFixture() throws -> (Workspace, Data) {
        let group = ProjectGroup(name: "Work")
        let parent = TaskItem(title: "Keep Unicode 📝", notes: "Line one\nLine two\n", completed: true,
                              subtasks: [Subtask(title: "Child", completed: true), Subtask(title: "Second")])
        let workspace = Workspace(revision: 17, groups: [group], projects: [
            Project(name: "First", groupID: group.id, tasks: [parent, TaskItem(title: "Next")]),
            Project(name: "Second", tasks: [])
        ])
        let bytes = try JSONEncoder().encode(workspace) + Data("\n  \n".utf8)
        try bytes.write(to: store.url)
        return (workspace, bytes)
    }

    func testMigrationPreservesOriginalBytesIDsOrderGroupsAndLegacyBackups() throws {
        let (legacy, bytes) = try legacyFixture()
        let backups = directory.appendingPathComponent("workspace.json.backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try bytes.write(to: backups.appendingPathComponent("original.json"))
        XCTAssertEqual(try store.load(), legacy)
        XCTAssertEqual(store.url, directory.appendingPathComponent("workspace.json").standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        XCTAssertEqual(try Data(contentsOf: backups.appendingPathComponent("original.json")), bytes)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("workspace.migration/original-workspace.json")), bytes)
        for project in legacy.projects {
            let location = try XCTUnwrap(store.listLocations[project.id])
            XCTAssertTrue(location.isManaged)
            XCTAssertEqual(try file(location.url).load().asProject().tasks, project.tasks)
        }
        let task = legacy.projects[0].tasks[0]
        _ = try store.apply(.patchTask(id: task.id, patch: .init(notes: .init(expected: task.notes, value: "YAML only"))))
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        XCTAssertEqual(try file(linkedURL(legacy.projects[0].id)).load().tasks[0].notes, "YAML only")
    }

    func testMigrationResumesBeforeCommitWithoutChangingStableIDs() throws {
        let (legacy, bytes) = try legacyFixture()
        store.migrationCheckpoint = { step in if step == "beforeCommit" { throw StoreError.io("Simulated interruption") } }
        XCTAssertThrowsError(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.catalogURL.path))
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        store = newStore()
        XCTAssertEqual(try store.load(), legacy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.catalogURL.path))
    }

    func testCatalogCommitRemainsAuthoritativeAfterInterruptedFinalization() throws {
        let (legacy, _) = try legacyFixture()
        store.migrationCheckpoint = { step in if step == "afterCommit" { throw StoreError.io("Simulated interruption") } }
        XCTAssertThrowsError(try store.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.catalogURL.path))
        let target = store.managedDirectory.appendingPathComponent(legacy.projects[0].id + ".yaml")
        _ = try file(target).apply(.addTask(projectID: legacy.projects[0].id, task: TaskItem(title: "After commit"), index: nil))
        store = newStore()
        let current = try store.load()
        XCTAssertEqual(current.projects[0].tasks.last?.title, "After commit")
        let manifest = try JSONDecoder().decode(MigrationManifest.self, from: Data(contentsOf: directory.appendingPathComponent("workspace.migration/manifest.json")))
        XCTAssertTrue(manifest.completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace.cutover.json").path))
    }

    func testMigrationNeverOverwritesChangedStagedListOnRestart() throws {
        let (legacy, _) = try legacyFixture()
        store.migrationCheckpoint = { step in if step == "beforeCommit" { throw StoreError.io("Stop") } }
        XCTAssertThrowsError(try store.load())
        let target = store.managedDirectory.appendingPathComponent(legacy.projects[0].id + ".yaml")
        _ = try file(target).apply(.addTask(projectID: legacy.projects[0].id, task: TaskItem(title: "Retain staged edits"), index: nil))
        let changed = try Data(contentsOf: target)
        store = newStore()
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: target), changed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.catalogURL.path))
    }

    func testOlderBinaryWriteIsPreservedAndCannotOverwriteYAML() throws {
        let (legacy, original) = try legacyFixture()
        _ = try store.load()
        let task = legacy.projects[0].tasks[0]
        _ = try store.apply(.patchTask(id: task.id, patch: .init(title: .init(expected: task.title, value: "New YAML title"))))
        var oldWrite = legacy
        oldWrite.projects[0].tasks[0].title = "Old JSON title"
        let laterBytes = try JSONEncoder().encode(oldWrite)
        try laterBytes.write(to: store.url)
        XCTAssertEqual(try store.load().projects[0].tasks[0].title, "New YAML title")
        XCTAssertNotNil(store.migrationWarning)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("workspace.migration/original-workspace.json")), original)
        let recovery = directory.appendingPathComponent("workspace.migration/legacy-writes")
        let files = try FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.first)), laterBytes)
    }

    func testMissingAndInvalidLinkedFilesAreIsolatedAndCannotBeEdited() throws {
        let healthy = try XCTUnwrap(store.load().projects.first)
        let broken = try store.createList(name: "Broken")
        let goodTask = TaskItem(title: "Healthy task")
        let brokenTask = TaskItem(title: "Last good")
        _ = try store.apply(.addTask(projectID: healthy.id, task: goodTask, index: nil))
        _ = try store.apply(.addTask(projectID: broken.id, task: brokenTask, index: nil))
        let brokenURL = try linkedURL(broken.id)
        try FileManager.default.removeItem(at: brokenURL)
        let loaded = try store.load()
        XCTAssertTrue(try XCTUnwrap(store.listIssues[broken.id]).isMissing)
        XCTAssertEqual(loaded.projects.first { $0.id == broken.id }?.tasks, [brokenTask])
        XCTAssertThrowsError(try store.apply(.patchTask(id: brokenTask.id, patch: .init(title: .init(expected: "Last good", value: "Stale edit")))))
        _ = try store.apply(.patchTask(id: goodTask.id, patch: .init(completed: .init(expected: false, value: true))))
        XCTAssertFalse(FileManager.default.fileExists(atPath: brokenURL.path))
        try Data("tasks: [invalid".utf8).write(to: brokenURL)
        _ = try store.load()
        XCTAssertFalse(try XCTUnwrap(store.listIssues[broken.id]).isMissing)
        let bytes = try Data(contentsOf: brokenURL)
        XCTAssertThrowsError(try store.apply(.patchProject(id: broken.id, name: .init(expected: "Broken", value: "No"), groupID: nil)))
        XCTAssertEqual(try Data(contentsOf: brokenURL), bytes)
        XCTAssertTrue(try store.load().projects.first { $0.id == healthy.id }?.tasks[0].completed == true)
    }

    func testOpenPathDuplicateSelectsAndIdentityCopyRequiresExplicitRelink() throws {
        _ = try store.load()
        let external = directory.appendingPathComponent("folder/todo.yaml")
        let created = try store.createList(name: "Folder list", at: external)
        let alias = external.deletingLastPathComponent().appendingPathComponent("./todo.yaml")
        XCTAssertEqual(try store.openList(at: alias).id, created.id)
        XCTAssertEqual(try store.load().projects.count, 2)
        let copy = directory.appendingPathComponent("copy.yaml")
        try Data(contentsOf: external).write(to: copy)
        XCTAssertThrowsError(try store.openList(at: copy)) { error in
            guard let conflict = error as? ListIdentityConflict else { return XCTFail("Expected identity conflict, got \(error)") }
            XCTAssertEqual(conflict.listID, created.id)
        }
        try store.relinkList(id: created.id, to: copy)
        XCTAssertEqual(try linkedURL(created.id), copy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
        XCTAssertEqual(try store.load().projects.count, 2)
    }

    func testContentEditsIgnoreEarlierMissingListRecoveryWithReusedIDs() throws {
        try checkContentEditsIgnoreRecoveryWithReusedIDs(missing: true)
    }

    func testContentEditsIgnoreEarlierInvalidListRecoveryWithReusedIDs() throws {
        try checkContentEditsIgnoreRecoveryWithReusedIDs(missing: false)
    }

    private func checkContentEditsIgnoreRecoveryWithReusedIDs(missing: Bool) throws {
        let cached = try XCTUnwrap(store.load().projects.first)
        let cachedChild = Subtask(title: "Cached child")
        let cachedTask = TaskItem(title: "Cached task", subtasks: [cachedChild])
        _ = try store.apply(.addTask(projectID: cached.id, task: cachedTask, index: nil))
        let healthy = try store.createList(name: "Healthy")
        let cachedURL = try linkedURL(cached.id)
        let invalidBytes = Data("tasks: [invalid".utf8)
        if missing { try FileManager.default.removeItem(at: cachedURL) }
        else { try invalidBytes.write(to: cachedURL) }
        let healthyChild = Subtask(id: cachedChild.id, title: "Healthy child", completed: true)
        let healthyTask = TaskItem(id: cachedTask.id, title: "Healthy task", completed: true, subtasks: [healthyChild])
        let healthyURL = try linkedURL(healthy.id)
        try ListFileCodec.encode(ListDocument(project: Project(id: healthy.id, name: healthy.name, tasks: [healthyTask]))).write(to: healthyURL)
        _ = try store.load()
        XCTAssertNotNil(store.listIssues[cached.id])
        XCTAssertNil(store.listIssues[healthy.id])

        let originalBytes = try Data(contentsOf: healthyURL)
        let noChange = try store.apply(.patchTask(id: healthyTask.id, patch: .init(completed: .init(expected: true, value: true))))
        XCTAssertNil(noChange.undo)
        XCTAssertEqual(try Data(contentsOf: healthyURL), originalBytes)
        let edit = try store.apply(.batch([
            .patchTask(id: healthyTask.id, patch: .init(title: .init(expected: healthyTask.title, value: "Edited task"), completed: .init(expected: true, value: false))),
            .patchSubtask(id: healthyChild.id, patch: .init(title: .init(expected: healthyChild.title, value: "Edited child"), completed: .init(expected: true, value: false)))
        ]))
        let edited = try file(healthyURL).load().asProject().tasks[0]
        XCTAssertEqual(edited.title, "Edited task")
        XCTAssertFalse(edited.completed)
        XCTAssertEqual(edited.subtasks[0].title, "Edited child")
        XCTAssertFalse(edited.subtasks[0].completed)
        _ = try store.apply(try XCTUnwrap(edit.undo))
        XCTAssertEqual(try file(healthyURL).load().asProject().tasks, [healthyTask])

        let removedChild = try store.apply(.deleteSubtask(id: healthyChild.id, expected: healthyChild))
        XCTAssertTrue(try file(healthyURL).load().tasks[0].subtasks.isEmpty)
        _ = try store.apply(try XCTUnwrap(removedChild.undo))
        let removedTask = try store.apply(.deleteTask(id: healthyTask.id, expected: healthyTask))
        XCTAssertTrue(try file(healthyURL).load().tasks.isEmpty)
        _ = try store.apply(try XCTUnwrap(removedTask.undo))
        let final = try store.load()
        XCTAssertEqual(final.projects.first { $0.id == cached.id }?.tasks, [cachedTask])
        XCTAssertEqual(final.projects.first { $0.id == healthy.id }?.tasks, [healthyTask])
        if missing { XCTAssertFalse(FileManager.default.fileExists(atPath: cachedURL.path)) }
        else { XCTAssertEqual(try Data(contentsOf: cachedURL), invalidBytes) }
    }

    func testRemoveOnlyUnlinksIncludingFinalListAndOpenRetainsTasks() throws {
        let project = try XCTUnwrap(store.load().projects.first)
        let task = TaskItem(title: "Retain")
        _ = try store.apply(.addTask(projectID: project.id, task: task, index: nil))
        let location = try linkedURL(project.id)
        let bytes = try Data(contentsOf: location)
        try store.removeList(id: project.id)
        XCTAssertTrue(try store.load().projects.isEmpty)
        XCTAssertEqual(try Data(contentsOf: location), bytes)
        XCTAssertEqual(try newStore().load().projects, [])
        XCTAssertEqual(try store.openList(at: location).tasks, [task])
    }

    func testGroupingAndOrderingNeverMoveOrRewriteListFiles() throws {
        let first = try XCTUnwrap(store.load().projects.first)
        let external = directory.appendingPathComponent("todo.yaml")
        let second = try store.createList(name: "Second", at: external)
        let locations = store.listLocations
        let before = try locations.mapValues { try Data(contentsOf: $0.url) }
        let group = ProjectGroup(name: "Grouped")
        _ = try store.apply(.batch([
            .addGroup(group: group, index: nil),
            .patchProject(id: second.id, name: nil, groupID: .init(expected: nil, value: group.id)),
            .reorderProjects(change: .init(expected: [first.id, second.id], value: [second.id, first.id]))
        ]))
        XCTAssertEqual(store.listLocations, locations)
        XCTAssertEqual(try store.listLocations.mapValues { try Data(contentsOf: $0.url) }, before)
        _ = try store.apply(.deleteGroup(id: group.id, expected: group))
        XCTAssertNil(try store.load().projects.first?.groupID)
        XCTAssertEqual(store.listLocations, locations)
    }

    func testMovePreservesBytesIdentityGroupsAndHistoryWithoutOverwrite() throws {
        let project = try XCTUnwrap(store.load().projects.first)
        let task = TaskItem(title: "Before move")
        _ = try store.apply(.addTask(projectID: project.id, task: task, index: nil))
        let group = ProjectGroup(name: "Work")
        _ = try store.apply(.batch([.addGroup(group: group, index: nil), .patchProject(id: project.id, name: nil, groupID: .init(expected: nil, value: group.id))]))
        let old = try linkedURL(project.id)
        let before = try Data(contentsOf: old)
        let history = try store.backups(listID: project.id)
        let destination = directory.appendingPathComponent("repository/todo.yaml")
        try store.moveList(id: project.id, to: destination)
        XCTAssertEqual(try linkedURL(project.id), destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try Data(contentsOf: destination), before)
        XCTAssertEqual(try store.load().projects[0].groupID, group.id)
        XCTAssertEqual(try store.backups(listID: project.id), history)
        XCTAssertFalse(try XCTUnwrap(store.listLocations[project.id]).isManaged)
        let occupied = directory.appendingPathComponent("occupied.yaml")
        let sentinel = Data("do not replace".utf8)
        try sentinel.write(to: occupied)
        XCTAssertThrowsError(try store.moveList(id: project.id, to: occupied))
        XCTAssertEqual(try Data(contentsOf: occupied), sentinel)
        XCTAssertEqual(try linkedURL(project.id), destination)
    }

    func testInterruptedMoveResumesFromDestinationBeforeCatalogCommit() throws {
        let project = try XCTUnwrap(store.load().projects.first)
        let old = try linkedURL(project.id)
        let destination = directory.appendingPathComponent("moved.yaml")
        store.moveCheckpoint = { step in if step == "beforeCommit" { throw StoreError.io("Interrupted move") } }
        XCTAssertThrowsError(try store.moveList(id: project.id, to: destination))
        XCTAssertEqual(try linkedURL(project.id), old)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        store = newStore()
        XCTAssertEqual(try store.load().projects[0].id, project.id)
        XCTAssertEqual(try linkedURL(project.id), destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }

    func testMoveRetainsEditedOriginalAfterCatalogCommit() throws {
        let project = try XCTUnwrap(store.load().projects.first)
        let old = try linkedURL(project.id)
        let destination = directory.appendingPathComponent("moved.yaml")
        let edited = Project(id: project.id, name: "Edited old file", tasks: [TaskItem(title: "Retained")])
        let changed = try ListFileCodec.encode(ListDocument(project: edited))
        store.moveCheckpoint = { step in if step == "afterCommit" { try changed.write(to: old) } }
        try store.moveList(id: project.id, to: destination)
        XCTAssertEqual(try linkedURL(project.id), destination)
        XCTAssertEqual(try Data(contentsOf: old), changed)
        XCTAssertNotNil(store.migrationWarning)
        store = newStore()
        _ = try store.load()
        XCTAssertEqual(try linkedURL(project.id), destination)
        XCTAssertEqual(try Data(contentsOf: old), changed)
    }

    func testSelectedBackupRestoreCannotChangeOtherListAndCanRecoverMissingFile() throws {
        let first = try XCTUnwrap(store.load().projects.first)
        let second = try store.createList(name: "Second")
        let firstTask = TaskItem(title: "First")
        _ = try store.apply(.addTask(projectID: first.id, task: firstTask, index: nil))
        let secondTask = TaskItem(title: "Second")
        _ = try store.apply(.addTask(projectID: second.id, task: secondTask, index: nil))
        let backup = try XCTUnwrap(store.backups(listID: first.id).first)
        let secondURL = try linkedURL(second.id)
        let secondBytes = try Data(contentsOf: secondURL)
        XCTAssertThrowsError(try store.restoreBackup(at: backup.url, listID: second.id))
        let firstURL = try linkedURL(first.id)
        try FileManager.default.removeItem(at: firstURL)
        let restored = try store.restoreBackup(at: backup.url, listID: first.id)
        XCTAssertTrue(try XCTUnwrap(restored.projects.first { $0.id == first.id }).tasks.isEmpty)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondBytes)
    }

    func testReadAndTargetedMutationDoNotNormalizeUnrelatedFiles() throws {
        let first = try XCTUnwrap(store.load().projects.first)
        let external = directory.appendingPathComponent("manual.yaml")
        let second = try store.createList(name: "Manual", at: external)
        let manual = Data("version: 1\nid: \(second.id)\nname: Manual\ntasks:\n  - title: Missing identity\n".utf8)
        try manual.write(to: external)
        _ = try store.load(normalizeMissingIDs: false)
        XCTAssertEqual(try Data(contentsOf: external), manual)
        _ = try store.apply(.addTask(projectID: first.id, task: TaskItem(title: "Unrelated"), index: nil))
        XCTAssertEqual(try Data(contentsOf: external), manual)
        _ = try store.apply(.addTask(projectID: second.id, task: TaskItem(title: "Normalize together"), index: nil))
        XCTAssertFalse(try file(external).load().hasMissingIDs)
        XCTAssertEqual(try file(external).load().tasks.count, 2)
    }

    func testCrossListTaskBatchIsRejectedBeforeAnyFileChanges() throws {
        let first = try XCTUnwrap(store.load().projects.first)
        let second = try store.createList(name: "Second")
        let before = try store.listLocations.mapValues { try Data(contentsOf: $0.url) }
        XCTAssertThrowsError(try store.apply(.batch([
            .addTask(projectID: first.id, task: TaskItem(title: "First"), index: nil),
            .addTask(projectID: second.id, task: TaskItem(title: "Second"), index: nil)
        ])))
        XCTAssertEqual(try store.listLocations.mapValues { try Data(contentsOf: $0.url) }, before)
    }

    func testDuplicateTaskIdentityIsRejectedOnOpenAndIsolatedOnExternalEdit() throws {
        let first = try XCTUnwrap(store.load().projects.first)
        let shared = TaskItem(title: "Existing")
        _ = try store.apply(.addTask(projectID: first.id, task: shared, index: nil))
        let candidate = directory.appendingPathComponent("duplicate.yaml")
        let duplicate = Project(name: "Duplicate", tasks: [shared])
        _ = try file(candidate).create(ListDocument(project: duplicate))
        XCTAssertThrowsError(try store.openList(at: candidate))
        let second = try store.createList(name: "Second")
        let secondURL = try linkedURL(second.id)
        try ListFileCodec.encode(ListDocument(project: Project(id: second.id, name: second.name, tasks: [shared]))).write(to: secondURL)
        _ = try store.load()
        XCTAssertNotNil(store.listIssues[second.id])
        XCTAssertNil(store.listIssues[first.id])
        _ = try store.apply(.patchTask(id: shared.id, patch: .init(completed: .init(expected: false, value: true))))
        XCTAssertTrue(try store.load().projects[0].tasks[0].completed)
    }
}

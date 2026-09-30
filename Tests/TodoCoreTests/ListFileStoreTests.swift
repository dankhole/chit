import XCTest
import Darwin
@testable import TodoCore

final class ListFileStoreTests: XCTestCase {
    private var directory: URL!
    private var state: URL!
    private var store: ListFileStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("chit-file-tests-\(UUID().uuidString)", isDirectory: true)
        state = directory.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ListFileStore(url: directory.appendingPathComponent("todo.yaml"), stateDirectory: state, backupInterval: 0)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testReadIsStrictlyReadOnlyAndMissingFileIsNeverInitialized() throws {
        let bytes = Data("version: 1\nname: Manual\ntasks:\n  - title: Hand written\n".utf8)
        try bytes.write(to: store.url)
        let document = try store.load()
        XCTAssertNil(document.id)
        XCTAssertNil(document.tasks[0].id)
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.path))
        try FileManager.default.removeItem(at: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.normalize())
        XCTAssertThrowsError(try store.apply(.addTask(projectID: "", task: TaskItem(title: "No recreation"), index: nil)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testCreationDoesNotOverwriteAnyExistingFile() throws {
        let document = try store.create(ListDocument(name: "Created"))
        XCTAssertNotNil(document.id)
        let original = try Data(contentsOf: store.url)
        XCTAssertThrowsError(try store.create(ListDocument(name: "Replacement")))
        XCTAssertEqual(try Data(contentsOf: store.url), original)
        let malformed = Data("user-owned unrelated bytes".utf8)
        try malformed.write(to: store.url)
        XCTAssertThrowsError(try store.create(ListDocument(name: "Replacement")))
        XCTAssertEqual(try Data(contentsOf: store.url), malformed)
    }

    func testNormalizeAndAddRunTogetherAndRetainExistingIDs() throws {
        let existingID = UUID().uuidString
        let childID = UUID().uuidString
        let document = ListDocument(name: "Manual", tasks: [
            ListTask(id: existingID, title: "Existing", subtasks: [ListSubtask(id: childID, title: "Existing child")]),
            ListTask(title: "New manual task", subtasks: [ListSubtask(title: "New manual child")])
        ])
        try ListFileCodec.encode(document).write(to: store.url)
        let added = TaskItem(title: "CLI addition")
        let result = try store.apply(.addTask(projectID: "", task: added, index: nil))
        let saved = try store.load()
        XCTAssertFalse(saved.hasMissingIDs)
        XCTAssertEqual(saved.tasks[0].id, existingID)
        XCTAssertEqual(saved.tasks[0].subtasks[0].id, childID)
        XCTAssertEqual(saved.tasks.last?.id, added.id)
        XCTAssertEqual(result.workspace.projects[0].tasks.count, 3)
        let before = try Data(contentsOf: store.url)
        XCTAssertEqual(try store.normalize(), saved)
        XCTAssertEqual(try Data(contentsOf: store.url), before)
        XCTAssertEqual(try ListFileStore(url: store.url, stateDirectory: state).load(), saved)
    }

    func testConflictDuringMissingIDNormalizationPreservesSourceBytes() throws {
        let projectID = UUID().uuidString
        let taskID = UUID().uuidString
        let document = ListDocument(id: projectID, name: "Manual", tasks: [ListTask(id: taskID, title: "Current"), ListTask(title: "No ID")])
        let bytes = try ListFileCodec.encode(document)
        try bytes.write(to: store.url)
        XCTAssertThrowsError(try store.apply(.patchTask(id: taskID, patch: .init(title: .init(expected: "Stale", value: "Mine"))))) { error in
            guard case StoreError.conflict = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        XCTAssertTrue(try store.load().hasMissingIDs)
    }

    func testEditorAtomicReplacementIsReadBeforePatchAndUnrelatedEditSurvives() throws {
        let task = TaskItem(title: "Original")
        let created = try store.create(ListDocument(project: Project(name: "List", tasks: [task])))
        var external = created
        external.tasks[0].notes = "Editor notes"
        // An ordinary editor saves a new inode at the same path.
        try FilePersistence.atomicWrite(ListFileCodec.encode(external), to: store.url)
        _ = try store.apply(.patchTask(id: task.id, patch: .init(title: .init(expected: "Original", value: "App title"))))
        let saved = try store.load()
        XCTAssertEqual(saved.tasks[0].title, "App title")
        XCTAssertEqual(saved.tasks[0].notes, "Editor notes")
    }

    func testEditorReplacementBetweenReadAndCommitIsDetectedAndPreserved() throws {
        let task = TaskItem(title: "Original")
        let created = try store.create(ListDocument(project: Project(name: "List", tasks: [task])))
        var external = created
        external.tasks[0].title = "Editor title"
        let externalBytes = try ListFileCodec.encode(external)
        store.beforeCommit = { try FilePersistence.atomicWrite(externalBytes, to: self.store.url) }
        XCTAssertThrowsError(try store.apply(.patchTask(id: task.id, patch: .init(title: .init(expected: "Original", value: "App title"))))) { error in
            guard case StoreError.conflict = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: store.url), externalBytes)
        let backups = try store.backups()
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try ListFileCodec.decode(Data(contentsOf: backups[0].url)), created)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["state", "todo.yaml"])
    }

    func testEditorDeletionBeforeCommitDoesNotRecreateLinkedFile() throws {
        let created = try store.create(ListDocument(name: "List"))
        store.beforeCommit = { try FileManager.default.removeItem(at: self.store.url) }
        XCTAssertThrowsError(try store.apply(.addTask(projectID: try XCTUnwrap(created.id), task: TaskItem(title: "Mine"), index: nil)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testCooperativeConcurrentWritersMergeAddsAndFieldEdits() throws {
        let task = TaskItem(title: "Original")
        let document = try store.create(ListDocument(project: Project(name: "List", tasks: [task])))
        let listID = try XCTUnwrap(document.id)
        let sourceURL = store.url
        let stateRoot = state!
        let results = FileStoreConcurrentResults()
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            results.capture {
                let other = ListFileStore(url: sourceURL, stateDirectory: stateRoot, backupInterval: 60)
                _ = try other.apply(.addTask(projectID: listID, task: TaskItem(title: "Concurrent \(index)"), index: nil))
            }
        }
        XCTAssertTrue(results.errors.isEmpty, "\(results.errors)")
        XCTAssertEqual(try store.load().tasks.count, 13)
        let edits: [StoreOperation] = [
            .patchTask(id: task.id, patch: .init(notes: .init(expected: "", value: "Notes"))),
            .patchTask(id: task.id, patch: .init(completed: .init(expected: false, value: true)))
        ]
        DispatchQueue.concurrentPerform(iterations: edits.count) { index in
            results.capture { _ = try ListFileStore(url: sourceURL, stateDirectory: stateRoot).apply(edits[index]) }
        }
        XCTAssertTrue(results.errors.isEmpty, "\(results.errors)")
        let saved = try store.load()
        XCTAssertEqual(saved.tasks[0].notes, "Notes")
        XCTAssertTrue(saved.tasks[0].completed)
    }

    func testCanonicalPathAliasesShareLockAndLockTimeoutIsFinite() throws {
        _ = try store.create(ListDocument(name: "List"))
        let aliasParent = directory.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: aliasParent, withDestinationURL: directory)
        let alias = ListFileStore(url: aliasParent.appendingPathComponent("./todo.yaml"), stateDirectory: state)
        XCTAssertEqual(alias.url, store.url)
        XCTAssertEqual(alias.lockURL, store.lockURL)
        let descriptor = open(store.lockURL.path, O_RDWR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        let before = try Data(contentsOf: store.url)
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try alias.normalize())
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 3)
        // A read does not need a write lock.
        XCTAssertNoThrow(try alias.load())
        XCTAssertEqual(try Data(contentsOf: store.url), before)
    }

    func testMalformedAndUnknownInputPreservesOriginalBytes() throws {
        let inputs = ["version: 1\nname: Bad\ntasks: [", "version: 1\nname: Future\nextra: 42\ntasks: []\n"]
        for input in inputs {
            let bytes = Data(input.utf8)
            try bytes.write(to: store.url)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.normalize())
            XCTAssertThrowsError(try store.apply(.addTask(projectID: "", task: TaskItem(title: "Must not save"), index: nil)))
            XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        }
    }

    func testBackupsRemainBoundedAndRestorePreservesCorruptBytesWithoutRepositoryNoise() throws {
        store = ListFileStore(url: store.url, stateDirectory: state, backupLimit: 2, backupInterval: 0)
        let created = try store.create(ListDocument(name: "List"))
        for index in 0..<4 {
            _ = try store.apply(.addTask(projectID: try XCTUnwrap(created.id), task: TaskItem(title: "Task \(index)"), index: nil))
        }
        let backups = try store.backups()
        XCTAssertEqual(backups.count, 2)
        let original = try Data(contentsOf: backups[0].url)
        let corrupt = Data("damaged original YAML".utf8)
        try corrupt.write(to: store.url)
        XCTAssertEqual(try store.backups().count, 2)
        let restored = try store.restoreBackup(at: backups[0].url)
        XCTAssertEqual(restored, try ListFileCodec.decode(original))
        let history = backups[0].url.deletingLastPathComponent().deletingLastPathComponent()
        let recovery = try FileManager.default.contentsOfDirectory(at: history.appendingPathComponent("recovery"), includingPropertiesForKeys: nil)
        XCTAssertEqual(recovery.count, 1)
        XCTAssertEqual(try Data(contentsOf: recovery[0]), corrupt)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["state", "todo.yaml"])
    }

    func testKnownListIdentityProtectsLinkedDocumentAndRecoveryHistoryAcrossMove() throws {
        let created = try store.create(ListDocument(name: "List"))
        let id = try XCTUnwrap(created.id)
        _ = try store.apply(.addTask(projectID: id, task: TaskItem(title: "First"), index: nil))
        let backup = try XCTUnwrap(store.backups().first)
        let movedURL = directory.appendingPathComponent("moved.yaml")
        try FileManager.default.moveItem(at: store.url, to: movedURL)
        let moved = ListFileStore(url: movedURL, listID: id, stateDirectory: state)
        XCTAssertEqual(try moved.backups(), [backup])
        var changedIdentity = try moved.load()
        changedIdentity.id = UUID().uuidString
        let changedBytes = try ListFileCodec.encode(changedIdentity)
        try changedBytes.write(to: movedURL)
        XCTAssertThrowsError(try moved.load())
        XCTAssertThrowsError(try moved.apply(.addTask(projectID: id, task: TaskItem(title: "Wrong list"), index: nil)))
        XCTAssertEqual(try Data(contentsOf: movedURL), changedBytes)
    }

    func testWrongIdentityBackupRestorePreservesBytesAndCreatesNoRecoveryCopy() throws {
        let created = try store.create(ListDocument(name: "List"))
        let id = try XCTUnwrap(created.id)
        _ = try store.apply(.addTask(projectID: id, task: TaskItem(title: "Current task"), index: nil))
        let backup = try XCTUnwrap(store.backups().first)
        let linked = ListFileStore(url: store.url, listID: id, stateDirectory: state)
        let wrongBackup = directory.appendingPathComponent("wrong-backup.yaml")
        try ListFileCodec.encode(ListDocument(project: Project(name: "Other list"))).write(to: wrongBackup)
        let before = try Data(contentsOf: store.url)
        let identityURL = linked.lockURL.deletingLastPathComponent().appendingPathComponent("identity")
        let identityBytes = try Data(contentsOf: identityURL)
        let recovery = backup.url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("recovery")
        XCTAssertThrowsError(try linked.restoreBackup(at: wrongBackup))
        XCTAssertEqual(try Data(contentsOf: store.url), before)
        XCTAssertEqual(try Data(contentsOf: identityURL), identityBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recovery.path))

        let corrupt = Data("damaged current YAML".utf8)
        try corrupt.write(to: store.url)
        XCTAssertThrowsError(try linked.restoreBackup(at: wrongBackup))
        XCTAssertEqual(try Data(contentsOf: store.url), corrupt)
        XCTAssertEqual(try Data(contentsOf: identityURL), identityBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recovery.path))
    }

    func testUUIDCaseDifferencesDoNotRegenerateOrBreakLinkedListIdentity() throws {
        let id = UUID().uuidString.lowercased()
        let document = ListDocument(id: id, name: "List")
        try ListFileCodec.encode(document).write(to: store.url)
        let linked = ListFileStore(url: store.url, listID: id.uppercased(), stateDirectory: state)
        XCTAssertEqual(try linked.load().id, id)
        _ = try linked.apply(.addTask(projectID: id.uppercased(), task: TaskItem(title: "Added"), index: nil))
        XCTAssertEqual(try linked.load().id, id)
        let edit = try linked.apply(.patchProject(id: id.uppercased(), name: .init(expected: "List", value: "Renamed"), groupID: nil))
        XCTAssertEqual(try linked.load().name, "Renamed")
        XCTAssertEqual(try linked.load().id, id)
        XCTAssertEqual(edit.workspace.projects[0].id, id.uppercased())
        guard case .patchProject(let undoID, _, _) = try XCTUnwrap(edit.undo) else { return XCTFail("Expected name Undo") }
        XCTAssertEqual(undoID, id.uppercased())
        _ = try linked.apply(try XCTUnwrap(edit.undo))
        XCTAssertEqual(try linked.load().name, "List")
        XCTAssertEqual(try linked.load().id, id)
    }

    func testExplicitMissingRecoveryIsExclusiveAndChecksIdentity() throws {
        let created = try store.create(ListDocument(name: "List"))
        let id = try XCTUnwrap(created.id)
        _ = try store.apply(.addTask(projectID: id, task: TaskItem(title: "First"), index: nil))
        let backup = try XCTUnwrap(store.backups().first)
        try FileManager.default.removeItem(at: store.url)
        let linked = ListFileStore(url: store.url, listID: id, stateDirectory: state)
        XCTAssertThrowsError(try linked.restoreBackup(at: backup.url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
        let restored = try linked.restoreMissingFromBackup(at: backup.url)
        XCTAssertEqual(restored.id, id)
        let before = try Data(contentsOf: store.url)
        XCTAssertThrowsError(try linked.restoreMissingFromBackup(at: backup.url))
        XCTAssertEqual(try Data(contentsOf: store.url), before)
    }
}

private final class FileStoreConcurrentResults: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var errors: [Error] = []
    func capture(_ body: () throws -> Void) {
        do { try body() }
        catch { lock.lock(); errors.append(error); lock.unlock() }
    }
}

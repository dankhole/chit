import Foundation
import XCTest
@testable import TodoCore

final class CatalogRecoveryTests: XCTestCase {
    private var directory: URL!
    private var store: TodoStore!
    private var state: URL { directory.appendingPathComponent("file-state", isDirectory: true) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent("ChitCatalogRecovery-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = newStore()
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func newStore() -> TodoStore {
        TodoStore(url: directory.appendingPathComponent("workspace.json"), backupInterval: 0, stateDirectory: state)
    }

    @discardableResult
    private func write(_ project: Project, at url: URL) throws -> Data {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = try ListFileCodec.encode(ListDocument(project: project)) + Data("\n# exact recovery bytes 📝\n".utf8)
        try bytes.write(to: url)
        return bytes
    }

    private func damage(_ bytes: Data = Data("{ damaged catalog\n".utf8)) throws {
        try bytes.write(to: store.catalogURL)
    }

    func testNoBackupRecoveryPreservesDamagedCatalogAndAllYAMLBytes() throws {
        let project = Project(name: "Recovered", tasks: [TaskItem(title: "Keep tasks", notes: "Keep notes\n", subtasks: [Subtask(title: "Child")])])
        let target = store.managedDirectory.appendingPathComponent("kept.yaml")
        let yaml = try write(project, at: target)
        let damaged = Data("{\"version\":1, broken\n\n".utf8)
        try damage(damaged)
        let plan = try store.prepareCatalogRecovery()
        XCTAssertEqual(plan.candidates.map(\.id), [project.id])
        XCTAssertTrue(plan.issues.isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.catalogURL), damaged)
        let result = try store.rebuildCatalog(using: plan, selectedURLs: [target])
        XCTAssertEqual(result.workspace.projects, [project])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(result.preservedCatalogURL)), damaged)
        XCTAssertEqual(try Data(contentsOf: target), yaml)
        XCTAssertEqual(try newStore().load(normalizeMissingIDs: false).projects, [project])
        XCTAssertEqual(try Data(contentsOf: target), yaml)
    }

    func testMissingCatalogAfterCutoverRefusesLegacyRemigrationAndRecoversLatestYAML() throws {
        let legacy = Workspace(projects: [Project(name: "Legacy", tasks: [TaskItem(title: "Old title")])])
        let legacyBytes = try JSONEncoder().encode(legacy)
        try legacyBytes.write(to: store.url)
        let migrated = try XCTUnwrap(store.load().projects.first)
        let target = try XCTUnwrap(store.listLocations[migrated.id]?.url)
        let latest = Project(id: migrated.id, name: "Current YAML", tasks: [TaskItem(title: "Latest task")])
        let yaml = try write(latest, at: target)
        let marker = directory.appendingPathComponent("workspace.cutover.json")
        let markerBytes = try Data(contentsOf: marker)
        let manifest = directory.appendingPathComponent("workspace.migration/manifest.json")
        let manifestBytes = try Data(contentsOf: manifest)
        try FileManager.default.removeItem(at: store.catalogURL)
        store = newStore()
        XCTAssertThrowsError(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.catalogURL.path))
        let plan = try store.prepareCatalogRecovery()
        let result = try store.rebuildCatalog(using: plan, selectedURLs: plan.candidates.map(\.url))
        XCTAssertNil(result.preservedCatalogURL)
        XCTAssertEqual(result.workspace.projects, [latest])
        XCTAssertEqual(try Data(contentsOf: target), yaml)
        XCTAssertEqual(try Data(contentsOf: store.url), legacyBytes)
        XCTAssertEqual(try Data(contentsOf: marker), markerBytes)
        XCTAssertEqual(try Data(contentsOf: manifest), manifestBytes)
        let restarted = newStore()
        XCTAssertEqual(try restarted.load().projects, [latest])
        XCTAssertNil(restarted.migrationWarning)
    }

    func testDamagedCatalogLinksRememberedLinksAndExplicitFilesAreRecoveredWithoutDiskScan() throws {
        _ = try store.load()
        let rememberedURL = directory.appendingPathComponent("external/remembered.yaml")
        let remembered = try store.createList(name: "Remembered", at: rememberedURL)
        let linkedURL = directory.appendingPathComponent("external/linked.yaml")
        let linked = Project(name: "Damaged catalog link")
        try write(linked, at: linkedURL)
        let explicitURL = directory.appendingPathComponent("external/explicit.yml")
        let explicit = Project(name: "Explicit")
        try write(explicit, at: explicitURL)
        try write(Project(name: "Do not scan"), at: directory.appendingPathComponent("external/unrelated.yaml"))
        let encodedPath = String(decoding: try JSONEncoder().encode(linkedURL.path), as: UTF8.self)
        try damage(Data("{\"version\":1,\"lists\":[{\"path\":\(encodedPath)},".utf8))
        let plan = try store.prepareCatalogRecovery(additionalURLs: [explicitURL])
        XCTAssertTrue(Set(plan.candidates.map(\.id)).isSuperset(of: [remembered.id, linked.id, explicit.id]))
        XCTAssertFalse(plan.candidates.contains { $0.name == "Do not scan" })
        XCTAssertTrue(plan.candidates.filter { $0.url.deletingLastPathComponent().lastPathComponent == "external" }.allSatisfy { !$0.isManaged })
    }

    func testMalformedMissingAndConflictingIdentitiesAreAllSkippedWithoutNormalization() throws {
        let healthy = Project(name: "Healthy")
        try write(healthy, at: store.managedDirectory.appendingPathComponent("healthy.yaml"))
        let duplicate = Project(name: "Copy")
        let copyA = store.managedDirectory.appendingPathComponent("copy-a.yaml")
        let copyB = store.managedDirectory.appendingPathComponent("copy-b.yaml")
        let copyBytes = try write(duplicate, at: copyA)
        try write(duplicate, at: copyB)
        let shared = TaskItem(title: "Shared identity")
        try write(Project(name: "Task A", tasks: [shared]), at: store.managedDirectory.appendingPathComponent("task-a.yaml"))
        try write(Project(name: "Task B", tasks: [shared]), at: store.managedDirectory.appendingPathComponent("task-b.yaml"))
        let incompleteURL = store.managedDirectory.appendingPathComponent("incomplete.yaml")
        let incomplete = try ListFileCodec.encode(ListDocument(name: "Incomplete", tasks: [ListTask(title: "Missing IDs")]))
        try incomplete.write(to: incompleteURL)
        let malformedURL = store.managedDirectory.appendingPathComponent("malformed.yaml")
        let malformed = Data("tasks: [broken".utf8)
        try malformed.write(to: malformedURL)
        try damage()
        let plan = try store.prepareCatalogRecovery()
        XCTAssertEqual(plan.candidates.map(\.id), [healthy.id])
        XCTAssertEqual(plan.issues.count, 6)
        XCTAssertTrue(plan.issues.contains { $0.url == copyA && $0.message.contains("Duplicate list ID") })
        XCTAssertTrue(plan.issues.contains { $0.url == copyB && $0.message.contains("Duplicate list ID") })
        _ = try store.rebuildCatalog(using: plan, selectedURLs: plan.candidates.map(\.url))
        XCTAssertEqual(try Data(contentsOf: copyA), copyBytes)
        XCTAssertEqual(try Data(contentsOf: incompleteURL), incomplete)
        XCTAssertEqual(try Data(contentsOf: malformedURL), malformed)
    }

    func testExplicitEmptyRebuildPreservesFilesAndAllowsCreateAndReopen() throws {
        let kept = Project(name: "Intentionally hidden")
        let target = store.managedDirectory.appendingPathComponent("kept.yaml")
        let yaml = try write(kept, at: target)
        let legacy = Data("legacy bytes retained".utf8)
        try legacy.write(to: store.url)
        try damage()
        let result = try store.rebuildCatalog(using: store.prepareCatalogRecovery(), selectedURLs: [])
        XCTAssertTrue(result.workspace.projects.isEmpty)
        XCTAssertEqual(try Data(contentsOf: target), yaml)
        XCTAssertEqual(try Data(contentsOf: store.url), legacy)
        store = newStore()
        XCTAssertTrue(try store.load().projects.isEmpty)
        XCTAssertNil(store.migrationWarning)
        _ = try store.createList(name: "New list")
        XCTAssertEqual(try store.openList(at: target).id, kept.id)
        XCTAssertEqual(try Data(contentsOf: target), yaml)
    }

    func testNoValidFilesCanExplicitlyRebuildEmpty() throws {
        try FileManager.default.createDirectory(at: store.managedDirectory, withIntermediateDirectories: true)
        let brokenURL = store.managedDirectory.appendingPathComponent("broken.yaml")
        let bytes = Data("broken".utf8)
        try bytes.write(to: brokenURL)
        try damage()
        let plan = try store.prepareCatalogRecovery()
        XCTAssertTrue(plan.candidates.isEmpty)
        XCTAssertEqual(plan.issues.count, 1)
        _ = try store.rebuildCatalog(using: plan, selectedURLs: [])
        XCTAssertTrue(try newStore().load().projects.isEmpty)
        XCTAssertEqual(try Data(contentsOf: brokenURL), bytes)
    }

    func testCommitRejectsOtherStoreChangedCatalogChangedCandidateAndHealthyRepair() throws {
        let project = Project(name: "Keep")
        let target = store.managedDirectory.appendingPathComponent("keep.yaml")
        let original = try write(project, at: target)
        try damage()
        let plan = try store.prepareCatalogRecovery()
        XCTAssertThrowsError(try newStore().rebuildCatalog(using: plan, selectedURLs: [target]))
        let changed = original + Data("# changed after preview\n".utf8)
        try changed.write(to: target)
        XCTAssertThrowsError(try store.rebuildCatalog(using: plan, selectedURLs: [target]))
        XCTAssertEqual(try Data(contentsOf: target), changed)
        let fresh = try store.prepareCatalogRecovery()
        try damage(Data("different damaged catalog".utf8))
        XCTAssertThrowsError(try store.rebuildCatalog(using: fresh, selectedURLs: []))
        let repairedPlan = try store.prepareCatalogRecovery()
        let healthy = ListCatalog(revision: 0, groups: [], lists: [],
                                  migration: CatalogMigration(sourceFingerprint: nil, originalPath: nil, manifestPath: ""))
        let healthyBytes = try catalogJSON(healthy)
        try healthyBytes.write(to: store.catalogURL)
        XCTAssertThrowsError(try store.rebuildCatalog(using: repairedPlan, selectedURLs: []))
        XCTAssertThrowsError(try store.prepareCatalogRecovery())
        XCTAssertEqual(try Data(contentsOf: store.catalogURL), healthyBytes)
    }

    func testFutureVersionSymlinkAndNonDirectoryPathsRefuseRecovery() throws {
        let future = Data("{\"version\":2,\"lists\":[]}".utf8)
        try damage(future)
        XCTAssertThrowsError(try store.prepareCatalogRecovery())
        XCTAssertEqual(try Data(contentsOf: store.catalogURL), future)
        try FileManager.default.removeItem(at: store.catalogURL)
        let original = directory.appendingPathComponent("original.json")
        try future.write(to: original)
        try FileManager.default.createSymbolicLink(at: store.catalogURL, withDestinationURL: original)
        XCTAssertThrowsError(try store.prepareCatalogRecovery())
        XCTAssertEqual(try Data(contentsOf: original), future)
        try FileManager.default.removeItem(at: store.catalogURL)
        try damage()
        try Data("not a directory".utf8).write(to: store.managedDirectory)
        XCTAssertThrowsError(try store.prepareCatalogRecovery())
    }

    func testLastPublicationCheckRefusesChangedSelectedBytesAndKeepsRecoveryCopy() throws {
        let project = Project(name: "Keep")
        let target = store.managedDirectory.appendingPathComponent("keep.yaml")
        let yaml = try write(project, at: target)
        let damaged = Data("damaged catalog".utf8)
        try damage(damaged)
        let plan = try store.prepareCatalogRecovery()
        store.beforeCatalogRecoveryPublish = { try (yaml + Data("# concurrent edit\n".utf8)).write(to: target) }
        XCTAssertThrowsError(try store.rebuildCatalog(using: plan, selectedURLs: [target]))
        XCTAssertEqual(try Data(contentsOf: store.catalogURL), damaged)
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".recovery-") }
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preserved.first)), damaged)
    }

    func testRestartDoesNotReplayOldMoveRecordAfterCatalogRebuild() throws {
        let project = try XCTUnwrap(store.load().projects.first)
        let source = try XCTUnwrap(store.listLocations[project.id]?.url)
        let destination = directory.appendingPathComponent("external/moved.yaml")
        store.moveCheckpoint = { if $0 == "beforeCommit" { throw StoreError.io("Interrupted") } }
        XCTAssertThrowsError(try store.moveList(id: project.id, to: destination))
        let sourceBytes = try Data(contentsOf: source)
        let destinationBytes = try Data(contentsOf: destination)
        try damage()
        store = newStore()
        let plan = try store.prepareCatalogRecovery()
        XCTAssertEqual(plan.candidates.map(\.url), [source])
        _ = try store.rebuildCatalog(using: plan, selectedURLs: [source])
        let restarted = newStore()
        XCTAssertEqual(try restarted.load().projects.first?.id, project.id)
        XCTAssertEqual(restarted.listLocations[project.id]?.url, source)
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: destination), destinationBytes)
    }
}

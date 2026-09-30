import Foundation
import XCTest
@testable import TodoCore
@testable import Chit

@MainActor
final class CatalogRecoveryModelTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let store: TodoStore
        let preferences: UserDefaults
        let suite: String
        let model: AppModel
        let listID: String
        let listURL: URL
        let task: TaskItem
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogRecoveryModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "CatalogRecoveryModelTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = TodoStore(url: root.appendingPathComponent("workspace.json"))
        let listID = try XCTUnwrap(store.load().projects.first?.id)
        let task = TaskItem(title: "Original task", notes: "Original notes", subtasks: [Subtask(title: "Child")])
        _ = try store.apply(.addTask(projectID: listID, task: task, index: nil))
        let model = AppModel(store: store, preferences: preferences, watchChanges: false)
        let listURL = try XCTUnwrap(model.location(for: listID)?.url)
        try body(Fixture(root: root, store: store, preferences: preferences, suite: suite,
                         model: model, listID: listID, listURL: listURL, task: task))
    }

    private func makeUnavailable(_ fixture: Fixture) throws -> Data {
        let damaged = Data("{ unreadable list index".utf8)
        try damaged.write(to: fixture.store.catalogURL)
        fixture.model.refresh()
        XCTAssertFalse(fixture.model.isStoreAvailable)
        return damaged
    }

    func testRebuildRestoresAvailabilityWithoutSavingListFilesAndClearsStaleUndo() throws {
        try withFixture { f in
            f.model.addTask("Undo belongs to the old index")
            XCTAssertTrue(f.model.canUndo)
            let listBytes = try Data(contentsOf: f.listURL)
            let damaged = try makeUnavailable(f)
            let diagnostic = f.model.errorMessage
            XCTAssertTrue(f.model.availableBackups().isEmpty)
            XCTAssertEqual(f.model.errorMessage, diagnostic, "Unavailable catalogs must not recurse through backup lookup.")
            XCTAssertTrue(f.model.beginCatalogRecovery())
            XCTAssertTrue(f.model.catalogRecoverySelectedURLs.contains(f.listURL))
            XCTAssertTrue(f.model.rebuildCatalog())

            XCTAssertTrue(f.model.isStoreAvailable)
            XCTAssertTrue(f.model.isSelectedListAvailable)
            XCTAssertEqual(f.model.selectedProjectID, f.listID)
            XCTAssertFalse(f.model.canUndo)
            XCTAssertFalse(f.model.isCatalogRecoveryPresented)
            XCTAssertNil(f.model.catalogRecoveryPlan)
            XCTAssertNil(f.model.catalogRecoveryErrorMessage)
            XCTAssertEqual(try Data(contentsOf: f.listURL), listBytes)
            let preserved = try XCTUnwrap(f.model.catalogRecoveryNotice?.preservedCatalogURL)
            XCTAssertEqual(try Data(contentsOf: preserved), damaged)
            XCTAssertFalse(f.model.beginCatalogRecovery(), "A healthy index cannot enter the rebuild flow.")
        }
    }

    func testExplicitEmptyRebuildCanCreateAndOpenListsLater() throws {
        try withFixture { f in
            let listBytes = try Data(contentsOf: f.listURL)
            _ = try makeUnavailable(f)
            XCTAssertTrue(f.model.beginCatalogRecovery())
            let plan = try XCTUnwrap(f.model.catalogRecoveryPlan)
            for candidate in plan.candidates {
                f.model.setCatalogRecoverySelection(candidate.url, isSelected: false)
            }
            XCTAssertTrue(f.model.catalogRecoverySelectedURLs.isEmpty)
            XCTAssertTrue(f.model.rebuildCatalog())
            XCTAssertTrue(f.model.isStoreAvailable)
            XCTAssertTrue(f.model.workspace.projects.isEmpty)
            XCTAssertEqual(try Data(contentsOf: f.listURL), listBytes)
            XCTAssertTrue(f.model.createList(name: "New list"))
            XCTAssertTrue(f.model.openList(at: f.listURL))
            XCTAssertEqual(f.model.selectedProjectID, f.listID)
            XCTAssertEqual(f.model.workspace.projects.count, 2)
            XCTAssertEqual(try Data(contentsOf: f.listURL), listBytes)
        }
    }

    func testStalePreviewRetainsSelectionsAndOwnerDraftsThroughRetryAndSuccess() throws {
        try withFixture { f in
            f.model.setText(itemID: f.task.id, field: .notes, value: "Retained local notes", projectID: f.listID)
            f.model.entryDrafts[f.listID] = "Unsubmitted task"
            f.model.setSubtaskEntry(parentID: f.task.id, projectID: f.listID, value: "Unsubmitted child")
            f.model.expandedTaskIDs[f.listID] = f.task.id
            f.model.collapsedGroupIDs = ["retained-group"]
            f.model.setScrollAnchor(projectID: f.listID, taskID: f.task.id)
            _ = try makeUnavailable(f)
            let preferenceKey = "workspace." + Data(f.store.url.standardizedFileURL.path.utf8).base64EncodedString()
            let savedDrafts = try XCTUnwrap(f.preferences.dictionary(forKey: preferenceKey)?["drafts"] as? Data)
            XCTAssertTrue(f.model.flushEditsForDismissal(), "Persisted drafts must not trap Hide or Quit while the index is unavailable.")
            XCTAssertEqual(f.preferences.dictionary(forKey: preferenceKey)?["drafts"] as? Data, savedDrafts)
            XCTAssertTrue(f.model.beginCatalogRecovery())
            let selected = f.model.catalogRecoverySelectedURLs
            var changed = try Data(contentsOf: f.listURL)
            changed.append(Data("\n# An external edit after the preview\n".utf8))
            try changed.write(to: f.listURL)
            XCTAssertFalse(f.model.rebuildCatalog())
            XCTAssertFalse(f.model.isStoreAvailable)
            XCTAssertTrue(f.model.isCatalogRecoveryPresented)
            XCTAssertEqual(f.model.catalogRecoverySelectedURLs, selected)
            XCTAssertNotNil(f.model.catalogRecoveryErrorMessage)
            XCTAssertEqual(f.model.text(itemID: f.task.id, field: .notes, fallback: "", projectID: f.listID), "Retained local notes")
            XCTAssertEqual(f.model.entryDrafts[f.listID], "Unsubmitted task")
            XCTAssertTrue(f.model.refreshCatalogRecovery())
            XCTAssertEqual(f.model.catalogRecoverySelectedURLs, selected)
            XCTAssertTrue(f.model.rebuildCatalog())
            XCTAssertEqual(try Data(contentsOf: f.listURL), changed, "Index recovery must not autosave retained edits.")
            XCTAssertEqual(f.model.text(itemID: f.task.id, field: .notes, fallback: "", projectID: f.listID), "Retained local notes")
            XCTAssertEqual(f.model.entryDrafts[f.listID], "Unsubmitted task")
            XCTAssertEqual(f.model.subtaskEntry(parentID: f.task.id, projectID: f.listID), "Unsubmitted child")
            XCTAssertEqual(f.model.expandedTaskID, f.task.id)
            XCTAssertEqual(f.model.collapsedGroupIDs, ["retained-group"])
            XCTAssertEqual(f.model.scrollAnchor(projectID: f.listID), f.task.id)
            let reopened = AppModel(store: TodoStore(url: f.store.url), preferences: f.preferences, watchChanges: false)
            XCTAssertEqual(reopened.text(itemID: f.task.id, field: .notes, fallback: "", projectID: f.listID), "Retained local notes")
            XCTAssertEqual(reopened.entryDrafts[f.listID], "Unsubmitted task")
            XCTAssertEqual(reopened.subtaskEntry(parentID: f.task.id, projectID: f.listID), "Unsubmitted child")
            XCTAssertEqual(try Data(contentsOf: f.listURL), changed)
        }
    }
}

import Foundation
import XCTest
@testable import TodoCore
@testable import Chit

@MainActor
final class SidebarPreferencesTests: XCTestCase {
    private func withFixture(_ body: (TodoStore, UserDefaults, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ChitSidebarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "ChitSidebarTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = TodoStore(url: root.appendingPathComponent("workspace.json"))
        _ = try store.load()
        try body(store, preferences, root)
    }

    private func preferenceKey(_ store: TodoStore) -> String {
        "workspace." + Data(store.url.standardizedFileURL.path.utf8).base64EncodedString()
    }

    func testNewWorkspaceStartsWithCompactNavigation() throws {
        try withFixture { store, preferences, _ in
            let model = AppModel(store: store, preferences: preferences, watchChanges: false)
            XCTAssertFalse(model.sidebarExpanded)
            XCTAssertEqual(model.sidebarExpandedWidth, 176)
            model.toggleSidebar()
            XCTAssertTrue(model.sidebarExpanded)
            model.toggleSidebar()
            XCTAssertFalse(model.sidebarExpanded)
        }
    }

    func testRelaunchPersistsExplicitExpansionAndCollapse() throws {
        try withFixture { store, preferences, _ in
            let model = AppModel(store: store, preferences: preferences, watchChanges: false)
            model.entryDrafts = ["add:retained-list": "Unfinished task"]
            model.setSidebarExpandedWidth(232)
            model.toggleSidebar()

            let reopened = AppModel(store: store, preferences: preferences, watchChanges: false)
            XCTAssertTrue(reopened.sidebarExpanded)
            XCTAssertEqual(reopened.sidebarExpandedWidth, 232)
            XCTAssertEqual(reopened.entryDrafts, model.entryDrafts)
            reopened.toggleSidebar()
            let collapsed = AppModel(store: store, preferences: preferences, watchChanges: false)
            XCTAssertFalse(collapsed.sidebarExpanded)
            XCTAssertEqual(collapsed.sidebarExpandedWidth, 232)
            XCTAssertEqual(collapsed.entryDrafts, model.entryDrafts)
        }
    }

    func testObsoleteDrawerAndWidthPreferencesDoNotExpandRail() throws {
        try withFixture { store, preferences, _ in
            let key = preferenceKey(store)
            preferences.set(["sidebarDockedOpen": true, "sidebarWidth": 295,
                             "sidebarDrawerOpen": true, "entryDrafts": ["add:retained-list": "Keep this"]], forKey: key)
            let model = AppModel(store: store, preferences: preferences, watchChanges: false)
            XCTAssertFalse(model.sidebarExpanded)
            XCTAssertEqual(model.sidebarExpandedWidth, 176)
            XCTAssertEqual(model.entryDrafts["add:retained-list"], "Keep this")
            model.toggleSidebar()
            let saved = try XCTUnwrap(preferences.dictionary(forKey: key))
            XCTAssertEqual(saved["sidebarExpanded"] as? Bool, true)
            XCTAssertEqual(saved["sidebarExpandedWidth"] as? Double, 176)
            XCTAssertNil(saved["sidebarDockedOpen"])
            XCTAssertNil(saved["sidebarWidth"])
            XCTAssertNil(saved["sidebarDrawerOpen"])
        }
    }

    func testInvalidExpansionPreferenceFallsBackToCompactRail() throws {
        try withFixture { store, preferences, _ in
            preferences.set(["sidebarExpanded": "invalid", "sidebarExpandedWidth": "invalid"], forKey: preferenceKey(store))
            let model = AppModel(store: store, preferences: preferences, watchChanges: false)
            XCTAssertFalse(model.sidebarExpanded)
            XCTAssertEqual(model.sidebarExpandedWidth, 176)
        }
    }

    func testExpandedWidthClampsAndRejectsNonFiniteValues() throws {
        try withFixture { store, preferences, _ in
            let model = AppModel(store: store, preferences: preferences, watchChanges: false)
            model.setSidebarExpandedWidth(40)
            XCTAssertEqual(model.sidebarExpandedWidth, 160)
            model.setSidebarExpandedWidth(700)
            XCTAssertEqual(model.sidebarExpandedWidth, 280)
            model.setSidebarExpandedWidth(.nan)
            model.setSidebarExpandedWidth(.infinity)
            XCTAssertEqual(model.sidebarExpandedWidth, 280)
            let reopened = AppModel(store: store, preferences: preferences, watchChanges: false)
            XCTAssertEqual(reopened.sidebarExpandedWidth, 280)
            XCTAssertFalse(reopened.sidebarExpanded)
        }
    }

    func testRestoredExpandedWidthIsClamped() throws {
        try withFixture { store, preferences, _ in
            let key = preferenceKey(store)
            preferences.set(["sidebarExpandedWidth": -20], forKey: key)
            XCTAssertEqual(AppModel(store: store, preferences: preferences, watchChanges: false).sidebarExpandedWidth, 160)
            preferences.set(["sidebarExpandedWidth": 800], forKey: key)
            XCTAssertEqual(AppModel(store: store, preferences: preferences, watchChanges: false).sidebarExpandedWidth, 280)
        }
    }

    func testWorkspaceAndInjectedDefaultsStayIsolatedWithoutCatalogChanges() throws {
        try withFixture { store, preferences, root in
            let model = AppModel(store: store, preferences: preferences, watchChanges: false)
            let catalog = try Data(contentsOf: store.catalogURL)
            model.toggleSidebar()
            model.setSidebarExpandedWidth(220)
            XCTAssertTrue(model.sidebarExpanded)
            XCTAssertEqual(try Data(contentsOf: store.catalogURL), catalog)

            let otherStore = TodoStore(url: root.appendingPathComponent("other/workspace.json"))
            let otherWorkspace = AppModel(store: otherStore, preferences: preferences, watchChanges: false)
            XCTAssertFalse(otherWorkspace.sidebarExpanded)
            XCTAssertEqual(otherWorkspace.sidebarExpandedWidth, 176)

            let separateSuite = "ChitSidebarTests.Isolated.\(UUID().uuidString)"
            let separatePreferences = try XCTUnwrap(UserDefaults(suiteName: separateSuite))
            defer { separatePreferences.removePersistentDomain(forName: separateSuite) }
            let separateSession = AppModel(store: store, preferences: separatePreferences, watchChanges: false)
            XCTAssertFalse(separateSession.sidebarExpanded)
            XCTAssertEqual(separateSession.sidebarExpandedWidth, 176)
        }
    }
}

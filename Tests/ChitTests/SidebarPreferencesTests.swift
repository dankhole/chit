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

    func testDefaultsAndBreakpointKeepDockedPreferenceIndependent() throws {
        try withFixture { store, preferences, _ in
            let model = AppModel(store: store, preferences: preferences, watchChanges: false)
            XCTAssertTrue(model.sidebarDockedOpen)
            XCTAssertEqual(model.sidebarWidth, 240)
            XCTAssertFalse(model.sidebarDrawerOpen)
            model.updateSidebarLayout(availableWidth: 640)
            XCTAssertTrue(model.sidebarIsDocked)
            XCTAssertTrue(model.sidebarVisible)
            XCTAssertTrue(model.toggleSidebar())
            XCTAssertFalse(model.sidebarDockedOpen)

            model.updateSidebarLayout(availableWidth: 639)
            XCTAssertFalse(model.sidebarIsDocked)
            XCTAssertFalse(model.sidebarVisible)
            XCTAssertTrue(model.showSidebarDrawer())
            XCTAssertTrue(model.sidebarDrawerOpen)
            XCTAssertFalse(model.sidebarDockedOpen)
            model.updateSidebarLayout(availableWidth: 900)
            XCTAssertFalse(model.sidebarDrawerOpen)
            XCTAssertFalse(model.sidebarVisible)
            model.updateSidebarLayout(availableWidth: 400)
            XCTAssertFalse(model.sidebarDrawerOpen, "Entering narrow mode always starts with a closed drawer.")
        }
    }

    func testRelaunchPersistsDockedVisibilityAndWidthButNeverDrawerState() throws {
        try withFixture { store, preferences, _ in
            let model = AppModel(store: store, preferences: preferences, watchChanges: false)
            model.updateSidebarLayout(availableWidth: 900)
            XCTAssertTrue(model.toggleSidebar())
            model.setSidebarWidth(295)
            model.updateSidebarLayout(availableWidth: 400)
            XCTAssertTrue(model.toggleSidebar())
            XCTAssertTrue(model.sidebarDrawerOpen)

            let reopened = AppModel(store: store, preferences: preferences, watchChanges: false)
            XCTAssertFalse(reopened.sidebarDockedOpen)
            XCTAssertEqual(reopened.sidebarWidth, 295)
            XCTAssertFalse(reopened.sidebarDrawerOpen)
            XCTAssertFalse(reopened.sidebarIsDocked)
            reopened.updateSidebarLayout(availableWidth: 900)
            XCTAssertFalse(reopened.sidebarVisible)
        }
    }

    func testWidthClampsAndRejectsNonFiniteValues() throws {
        try withFixture { store, preferences, _ in
            let model = AppModel(store: store, preferences: preferences, watchChanges: false)
            model.setSidebarWidth(100)
            XCTAssertEqual(model.sidebarWidth, 200)
            model.setSidebarWidth(700)
            XCTAssertEqual(model.sidebarWidth, 320)
            model.setSidebarWidth(.nan)
            model.setSidebarWidth(.infinity)
            XCTAssertEqual(model.sidebarWidth, 320)
            let reopened = AppModel(store: store, preferences: preferences, watchChanges: false)
            XCTAssertEqual(reopened.sidebarWidth, 320)
        }
    }

    func testRestoredWidthIsValidatedAndClamped() throws {
        try withFixture { store, preferences, _ in
            let key = "workspace." + Data(store.url.standardizedFileURL.path.utf8).base64EncodedString()
            preferences.set(["sidebarWidth": -20, "sidebarDockedOpen": false], forKey: key)
            let clamped = AppModel(store: store, preferences: preferences, watchChanges: false)
            XCTAssertEqual(clamped.sidebarWidth, 200)
            XCTAssertFalse(clamped.sidebarDockedOpen)
            preferences.set(["sidebarWidth": "invalid"], forKey: key)
            let fallback = AppModel(store: store, preferences: preferences, watchChanges: false)
            XCTAssertEqual(fallback.sidebarWidth, 240)
            XCTAssertTrue(fallback.sidebarDockedOpen)
        }
    }

    func testWorkspaceAndInjectedDefaultsStayIsolatedWithoutCatalogChanges() throws {
        try withFixture { store, preferences, root in
            let model = AppModel(store: store, preferences: preferences, watchChanges: false)
            let catalog = try Data(contentsOf: store.catalogURL)
            model.updateSidebarLayout(availableWidth: 900)
            XCTAssertTrue(model.toggleSidebar())
            model.setSidebarWidth(270)
            XCTAssertEqual(try Data(contentsOf: store.catalogURL), catalog)

            let otherStore = TodoStore(url: root.appendingPathComponent("other/workspace.json"))
            let otherWorkspace = AppModel(store: otherStore, preferences: preferences, watchChanges: false)
            XCTAssertTrue(otherWorkspace.sidebarDockedOpen)
            XCTAssertEqual(otherWorkspace.sidebarWidth, 240)

            let separateSuite = "ChitSidebarTests.Isolated.\(UUID().uuidString)"
            let separatePreferences = try XCTUnwrap(UserDefaults(suiteName: separateSuite))
            defer { separatePreferences.removePersistentDomain(forName: separateSuite) }
            let separateSession = AppModel(store: store, preferences: separatePreferences, watchChanges: false)
            XCTAssertTrue(separateSession.sidebarDockedOpen)
            XCTAssertEqual(separateSession.sidebarWidth, 240)
        }
    }
}

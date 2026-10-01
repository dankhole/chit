import AppKit
import XCTest
@testable import Chit

#if CHIT_DISTRIBUTION
import Sparkle
#endif

@MainActor
final class SoftwareUpdateControllerTests: XCTestCase {
    func testAvailableUpdateRefreshesExistingAndNewMenuItemsWithoutChangingAction() {
        let reminder = SoftwareUpdateReminder()
        let target = UpdateMenuTarget()
        let action = #selector(UpdateMenuTarget.checkForUpdates(_:))
        let existing = reminder.makeMenuItem(target: target, action: action)
        XCTAssertEqual(existing.title, "Check for Updates…")
        XCTAssertNil(existing.toolTip)

        reminder.showUpdate(version: "1.4.0")
        let newItem = reminder.makeMenuItem(target: target, action: action)
        XCTAssertTrue(reminder.isUpdateAvailable)
        XCTAssertEqual(reminder.availableVersion, "1.4.0")
        for item in [existing, newItem] {
            XCTAssertEqual(item.title, "Update Available…")
            XCTAssertTrue(item.toolTip?.contains("1.4.0") == true)
            XCTAssertTrue(item.target === target)
            XCTAssertEqual(item.action, action)
        }
    }

    func testSessionEndClearsReminderAndMenusAndNotifiesOnlyOnChanges() {
        let reminder = SoftwareUpdateReminder()
        let target = UpdateMenuTarget()
        let item = reminder.makeMenuItem(target: target, action: #selector(UpdateMenuTarget.checkForUpdates(_:)))
        var versions: [String?] = []
        reminder.onAvailabilityChange = { versions.append($0) }

        reminder.showUpdate(version: "1.4.0")
        reminder.showUpdate(version: "1.4.0")
        reminder.showUpdate(version: "1.4.1")
        XCTAssertTrue(item.toolTip?.contains("1.4.1") == true)
        #if CHIT_DISTRIBUTION
        reminder.standardUserDriverWillFinishUpdateSession()
        #else
        reminder.finishSession()
        #endif
        reminder.finishSession()

        XCTAssertFalse(reminder.isUpdateAvailable)
        XCTAssertNil(reminder.availableVersion)
        XCTAssertEqual(item.title, "Check for Updates…")
        XCTAssertNil(item.toolTip)
        XCTAssertEqual(versions, ["1.4.0", "1.4.1", nil])
        XCTAssertEqual(
            reminder.makeMenuItem(target: target, action: #selector(UpdateMenuTarget.checkForUpdates(_:))).title,
            "Check for Updates…"
        )
    }

    #if CHIT_DISTRIBUTION
    func testScheduledRemindersPreserveSparkleAlertsForCriticalUpdates() throws {
        let reminder = SoftwareUpdateReminder()
        XCTAssertTrue(reminder.supportsGentleScheduledUpdateReminders)
        for isCritical in [false, true] {
            let update = try appcastItem(isCritical: isCritical)
            XCTAssertEqual(update.isCriticalUpdate, isCritical)
            for immediateFocus in [false, true] {
                XCTAssertEqual(reminder.standardUserDriverShouldHandleShowingScheduledUpdate(
                    update, andInImmediateFocus: immediateFocus
                ), isCritical)
            }
        }
        XCTAssertFalse(reminder.isUpdateAvailable)
    }

    func testSparkleUserDriverCallbacksShowAndFinishReminderForScheduledAndManualChecks() throws {
        let reminder = SoftwareUpdateReminder()
        let update = try appcastItem()
        for userInitiated in [false, true] {
            let archive = NSKeyedArchiver(requiringSecureCoding: true)
            // Sparkle 2.10's public NSSecureCoding initializer is the available
            // way to construct this state without starting a real updater.
            archive.encode(SPUUserUpdateStage.notDownloaded.rawValue, forKey: "SPUUserUpdateStateStage")
            archive.encode(userInitiated, forKey: "SPUUserUpdateStateUserInitiated")
            archive.finishEncoding()
            let decoder = try NSKeyedUnarchiver(forReadingFrom: archive.encodedData)
            let state = try XCTUnwrap(SPUUserUpdateState(coder: decoder))
            decoder.finishDecoding()
            XCTAssertEqual(state.userInitiated, userInitiated)

            reminder.standardUserDriverWillHandleShowingUpdate(userInitiated, forUpdate: update, state: state)
            XCTAssertEqual(reminder.availableVersion, "1.4.0")
            reminder.standardUserDriverWillFinishUpdateSession()
            XCTAssertFalse(reminder.isUpdateAvailable)
        }
    }

    private func appcastItem(isCritical: Bool = false) throws -> SUAppcastItem {
        var item: [String: Any] = [
            "sparkle:version": "140", "sparkle:shortVersionString": "1.4.0",
            "enclosure": ["url": "https://updates.example.test/Chit_1.4.0.zip"]
        ]
        if isCritical { item["sparkle:criticalUpdate"] = [String: String]() }
        // The deprecated dictionary initializer remains public and is confined
        // to synthetic test fixtures; production appcast items come from Sparkle.
        return try XCTUnwrap(SUAppcastItem(dictionary: item))
    }
    #endif

    func testIsolatedLaunchesNeverAllowUpdates() {
        XCTAssertTrue(SoftwareUpdateController.allowsUpdates(isLab: false, isIsolated: false, environment: [:]))
        XCTAssertFalse(SoftwareUpdateController.allowsUpdates(isLab: true, isIsolated: false, environment: [:]))
        XCTAssertFalse(SoftwareUpdateController.allowsUpdates(isLab: false, isIsolated: true, environment: [:]))
        for key in ["CHIT_STORE", "TOT_TODO_STORE", "CHIT_FILE_STATE_DIRECTORY"] {
            XCTAssertFalse(SoftwareUpdateController.allowsUpdates(
                isLab: false, isIsolated: false, environment: [key: "/synthetic/store"]
            ), key)
        }
    }

    func testIsolatedLaunchesNeverCreateUpdaterOrCallRelaunchGuard() throws {
        let launches: [(isLab: Bool, isIsolated: Bool, environment: [String: String])] = [
            (true, false, [:]),
            (false, true, [:])
        ] + ["CHIT_STORE", "TOT_TODO_STORE", "CHIT_FILE_STATE_DIRECTORY"].map {
            (false, false, [$0: "/synthetic/store"])
        }
        var calledGuard = false
        for launch in launches {
            let updater = try SoftwareUpdateController.startIfAllowed(
                isLab: launch.isLab, isIsolated: launch.isIsolated, environment: launch.environment
            ) {
                calledGuard = true
                return true
            }
            XCTAssertNil(updater)
        }
        XCTAssertFalse(calledGuard)
    }

    func testReleaseConfigurationRequiresHTTPSAndExactPublicKey() throws {
        // An RFC 8032 Ed25519 test-vector public key; never used by the app.
        let bytes: [UInt8] = [
            0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7,
            0xd5, 0x4b, 0xfe, 0xd3, 0xc9, 0x64, 0x07, 0x3a,
            0x0e, 0xe1, 0x72, 0xf3, 0xda, 0xa6, 0x23, 0x25,
            0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a
        ]
        let key = Data(bytes).base64EncodedString()
        let valid: [String: Any] = ["SUFeedURL": "https://updates.example.test/appcast.xml", "SUPublicEDKey": key]
        XCTAssertNoThrow(try SoftwareUpdateController.validateReleaseConfiguration(valid))
        XCTAssertThrowsError(try SoftwareUpdateController.validateReleaseConfiguration([:]))
        for feed in ["http://updates.example.test/appcast.xml", "file:///tmp/appcast.xml", "https://", "https://user:password@updates.example.test/appcast.xml"] {
            XCTAssertThrowsError(try SoftwareUpdateController.validateReleaseConfiguration([
                "SUFeedURL": feed, "SUPublicEDKey": key
            ]), feed)
        }
        for invalidKey in ["", "placeholder", Data(bytes.dropLast()).base64EncodedString(), key + "\n"] {
            XCTAssertThrowsError(try SoftwareUpdateController.validateReleaseConfiguration([
                "SUFeedURL": valid["SUFeedURL"]!, "SUPublicEDKey": invalidKey
            ]))
        }
    }

    #if !CHIT_DISTRIBUTION
    func testLocalBuildNeverCreatesUpdaterOrCallsRelaunchGuard() throws {
        var calledGuard = false
        let updater = try SoftwareUpdateController.startIfAllowed(isLab: false, isIsolated: false, environment: [:]) {
            calledGuard = true
            return true
        }
        XCTAssertNil(updater)
        XCTAssertFalse(calledGuard)
    }
    #endif
}

@MainActor
private final class UpdateMenuTarget: NSObject {
    @objc func checkForUpdates(_ sender: Any?) {}
}

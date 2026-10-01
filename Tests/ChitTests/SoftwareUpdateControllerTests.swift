import Foundation
import XCTest
@testable import Chit

@MainActor
final class SoftwareUpdateControllerTests: XCTestCase {
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

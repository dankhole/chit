import Foundation
import ServiceManagement
import XCTest
@testable import Chit

@MainActor
final class LoginItemControllerTests: XCTestCase {
    private func withPreferences(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "ChitLoginItemTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        try body(preferences)
    }

    func testFirstLaunchEnablesLoginAndOptOutSurvivesRelaunch() throws {
        try withPreferences { preferences in
            let service = FakeLoginItemService()
            let first = LoginItemController(preferences: preferences, service: service)
            XCTAssertTrue(first.isOn)
            XCTAssertEqual(service.registrations, 1)
            first.setEnabled(false)
            XCTAssertFalse(first.isOn)
            XCTAssertEqual(service.unregistrations, 1)

            let reopened = LoginItemController(preferences: preferences, service: service)
            XCTAssertFalse(reopened.isOn)
            XCTAssertEqual(service.registrations, 1)
            reopened.setEnabled(true)
            XCTAssertTrue(reopened.isOn)
            XCTAssertEqual(service.registrations, 2)
        }
    }

    func testMissingServiceAttemptsDefaultRegistration() throws {
        try withPreferences { preferences in
            let service = FakeLoginItemService()
            service.status = .notFound
            let controller = LoginItemController(preferences: preferences, service: service)
            XCTAssertTrue(controller.isOn)
            XCTAssertEqual(service.registrations, 1)
        }
    }

    func testExternalSystemSettingsChangesAreRespectedAfterInitialization() throws {
        try withPreferences { preferences in
            let service = FakeLoginItemService()
            let first = LoginItemController(preferences: preferences, service: service)
            service.status = .notRegistered
            first.refresh()
            XCTAssertFalse(first.isOn)
            let reopened = LoginItemController(preferences: preferences, service: service)
            XCTAssertFalse(reopened.isOn)
            XCTAssertEqual(service.registrations, 1)
            service.status = .enabled
            reopened.refresh()
            XCTAssertTrue(reopened.isOn)
        }
    }

    func testExistingRegistrationsAndDeniedApprovalAreNotOverridden() throws {
        for status in [SMAppService.Status.enabled, .requiresApproval] {
            try withPreferences { preferences in
                let service = FakeLoginItemService()
                service.status = status
                let controller = LoginItemController(preferences: preferences, service: service)
                XCTAssertTrue(controller.isOn)
                XCTAssertEqual(controller.requiresApproval, status == .requiresApproval)
                XCTAssertEqual(service.registrations, 0)
                controller.openSystemSettings()
                XCTAssertEqual(service.settingsOpens, 1)
                controller.setEnabled(false)
                XCTAssertFalse(controller.isOn)
                XCTAssertEqual(service.unregistrations, 1)
            }
        }
    }

    func testNewRegistrationRequiringApprovalShowsPendingState() throws {
        try withPreferences { preferences in
            let service = FakeLoginItemService()
            service.registeredStatus = .requiresApproval
            let controller = LoginItemController(preferences: preferences, service: service)
            XCTAssertTrue(controller.requiresApproval)
            XCTAssertTrue(controller.isOn)
            _ = LoginItemController(preferences: preferences, service: service)
            XCTAssertEqual(service.registrations, 1)
        }
    }

    func testFailedRegistrationReportsActualStateAndCanRetry() throws {
        try withPreferences { preferences in
            let service = FakeLoginItemService()
            service.failure = NSError(domain: "SyntheticLoginItem", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Synthetic failure."])
            let controller = LoginItemController(preferences: preferences, service: service)
            XCTAssertFalse(controller.isOn)
            XCTAssertTrue(controller.errorMessage?.contains("Synthetic failure.") == true)
            service.failure = nil
            let reopened = LoginItemController(preferences: preferences, service: service)
            XCTAssertTrue(reopened.isOn)
            XCTAssertNil(reopened.errorMessage)
            XCTAssertEqual(service.registrations, 2)
        }
    }

    func testFailedUnregisterKeepsEnabledStateUntilSuccessfulRetry() throws {
        try withPreferences { preferences in
            let service = FakeLoginItemService()
            let controller = LoginItemController(preferences: preferences, service: service)
            service.failure = NSError(domain: "SyntheticLoginItem", code: 2)
            controller.setEnabled(false)
            XCTAssertTrue(controller.isOn)
            XCTAssertNotNil(controller.errorMessage)
            service.failure = nil
            controller.setEnabled(false)
            XCTAssertFalse(controller.isOn)
            XCTAssertNil(controller.errorMessage)
        }
    }

    func testOptOutAfterFailedDefaultDoesNotRetryOnRelaunch() throws {
        try withPreferences { preferences in
            let service = FakeLoginItemService()
            service.failure = NSError(domain: "SyntheticLoginItem", code: 1)
            let controller = LoginItemController(preferences: preferences, service: service)
            controller.setEnabled(false)
            service.failure = nil
            let reopened = LoginItemController(preferences: preferences, service: service)
            XCTAssertFalse(reopened.isOn)
            XCTAssertEqual(service.registrations, 1)
            XCTAssertEqual(service.unregistrations, 0)
        }
    }

    func testLabAndIsolatedLaunchesNeverConfigureSystemServiceOrPreferences() throws {
        let launches: [(Bool, Bool, [String: String])] = [(true, false, [:]), (false, true, [:])]
            + ["CHIT_STORE", "TOT_TODO_STORE", "CHIT_FILE_STATE_DIRECTORY"].map { (false, false, [$0: "/synthetic"]) }
        for (isLab, isIsolated, environment) in launches {
            try withPreferences { preferences in
                let before = preferences.dictionaryRepresentation()
                let controller = LoginItemController.start(preferences: preferences, isLab: isLab,
                                                          isIsolated: isIsolated, environment: environment)
                XCTAssertFalse(controller.isAvailable)
                controller.setEnabled(true)
                controller.setEnabled(false)
                controller.openSystemSettings()
                XCTAssertFalse(controller.isOn)
                XCTAssertEqual(preferences.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
            }
        }
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registeredStatus: SMAppService.Status = .enabled
    var registrations = 0
    var unregistrations = 0
    var settingsOpens = 0
    var failure: Error?

    func register() throws {
        registrations += 1
        if let failure { throw failure }
        status = registeredStatus
    }

    func unregister() throws {
        unregistrations += 1
        if let failure { throw failure }
        status = .notRegistered
    }

    func openSystemSettings() { settingsOpens += 1 }
}

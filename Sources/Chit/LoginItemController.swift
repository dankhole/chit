import Combine
import Foundation
import ServiceManagement

@MainActor
protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
private final class MainAppLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// macOS owns the current setting; the preference only records that the initial
/// default has been applied, so later System Settings changes are respected.
@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?
    private let service: LoginItemService?
    private let preferences: UserDefaults
    private static let initializedKey = "startup.loginItemInitialized"

    var isAvailable: Bool { service != nil }
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    static func start(
        preferences: UserDefaults,
        isLab: Bool,
        isIsolated: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LoginItemController {
        let overrides = ["CHIT_STORE", "TOT_TODO_STORE", "CHIT_FILE_STATE_DIRECTORY"]
        let allowed = !isLab && !isIsolated && !overrides.contains { environment[$0]?.isEmpty == false }
        // Never even construct a system service for Lab, previews, or tests.
        return LoginItemController(preferences: preferences, service: allowed ? MainAppLoginItemService() : nil)
    }

    init(preferences: UserDefaults, service: LoginItemService?) {
        self.preferences = preferences
        self.service = service
        guard service != nil else { return }
        refresh()
        guard !preferences.bool(forKey: Self.initializedKey) else { return }
        if status == .notRegistered || status == .notFound {
            setEnabled(true)
        } else {
            // Existing registration (including denied approval) is a user choice.
            preferences.set(true, forKey: Self.initializedKey)
        }
    }

    func refresh() {
        guard let service else { return }
        status = service.status
    }

    func setEnabled(_ enabled: Bool) {
        guard let service else { return }
        errorMessage = nil
        refresh()
        do {
            if enabled {
                if !isOn { try service.register() }
            } else if status != .notRegistered {
                try service.unregister()
            }
            preferences.set(true, forKey: Self.initializedKey)
        } catch {
            errorMessage = "Couldn’t \(enabled ? "enable" : "disable") launch at login. \(error.localizedDescription)"
        }
        refresh()
    }

    func openSystemSettings() { service?.openSystemSettings() }
}

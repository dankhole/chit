import AppKit

#if CHIT_DISTRIBUTION
import Sparkle
#endif

/// Only configured distribution builds may create Sparkle's standard updater.
@MainActor
final class SoftwareUpdateController: NSObject {
    #if CHIT_DISTRIBUTION
    private var updaterController: SPUStandardUpdaterController!
    private let shouldRelaunch: () -> Bool

    private init(shouldRelaunch: @escaping () -> Bool) {
        self.shouldRelaunch = shouldRelaunch
        super.init()
    }
    #endif

    static func startIfAllowed(
        isLab: Bool,
        isIsolated: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        shouldRelaunch: @escaping () -> Bool
    ) throws -> SoftwareUpdateController? {
        #if CHIT_DISTRIBUTION
        guard allowsUpdates(isLab: isLab, isIsolated: isIsolated, environment: environment) else { return nil }
        try validateReleaseConfiguration(Bundle.main.infoDictionary ?? [:])
        let updates = SoftwareUpdateController(shouldRelaunch: shouldRelaunch)
        updates.updaterController = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: updates, userDriverDelegate: nil
        )
        // Leave automatic-check consent and scheduling to Sparkle's standard UI.
        try updates.updaterController.updater.start()
        return updates
        #else
        return nil
        #endif
    }

    static func allowsUpdates(isLab: Bool, isIsolated: Bool, environment: [String: String]) -> Bool {
        let storageOverrides = ["CHIT_STORE", "TOT_TODO_STORE", "CHIT_FILE_STATE_DIRECTORY"]
        return !isLab && !isIsolated && !storageOverrides.contains { environment[$0]?.isEmpty == false }
    }

    static func validateReleaseConfiguration(_ info: [String: Any]) throws {
        guard let feed = info["SUFeedURL"] as? String,
              let components = URLComponents(string: feed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.fragment == nil,
              components.url != nil else {
            throw configurationError("This release is missing a valid HTTPS update feed.")
        }
        guard let key = info["SUPublicEDKey"] as? String,
              let decoded = Data(base64Encoded: key), decoded.count == 32,
              decoded.base64EncodedString() == key else {
            throw configurationError("This release is missing a valid update signing public key.")
        }
    }

    func makeMenuItem() -> NSMenuItem? {
        #if CHIT_DISTRIBUTION
        let item = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        // Sparkle validates this action using updater.canCheckForUpdates.
        item.target = updaterController
        return item
        #else
        return nil
        #endif
    }

    private static func configurationError(_ message: String) -> NSError {
        NSError(domain: "Chit.SoftwareUpdates", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

#if CHIT_DISTRIBUTION
extension SoftwareUpdateController: SPUUpdaterDelegate {
    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        // Sparkle 2.10 checks this before committing installation and requesting
        // termination. Reuse ordinary quit's IME and draft-save refusal.
        shouldRelaunch()
    }
}
#endif

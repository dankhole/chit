import AppKit

#if CHIT_DISTRIBUTION
import Sparkle
#endif

/// Only configured distribution builds may create Sparkle's standard updater.
@MainActor
final class SoftwareUpdateController: NSObject {
    let reminder = SoftwareUpdateReminder()

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
            startingUpdater: false, updaterDelegate: updates, userDriverDelegate: updates.reminder
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
        // Keep Sparkle's target/action so it validates canCheckForUpdates and
        // brings an existing update session into focus instead of starting another.
        return reminder.makeMenuItem(
            target: updaterController,
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        )
        #else
        return nil
        #endif
    }

    private static func configurationError(_ message: String) -> NSError {
        NSError(domain: "Chit.SoftwareUpdates", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Presentation state only; Sparkle owns checking, downloading, and installation.
@MainActor
final class SoftwareUpdateReminder: NSObject {
    private(set) var availableVersion: String?
    var onAvailabilityChange: ((String?) -> Void)?
    private let menuItems = NSHashTable<NSMenuItem>.weakObjects()

    var isUpdateAvailable: Bool { availableVersion != nil }

    func makeMenuItem(target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        item.target = target
        menuItems.add(item)
        refresh(item)
        return item
    }

    func showUpdate(version: String) {
        setAvailableVersion(version)
    }

    func finishSession() {
        setAvailableVersion(nil)
    }

    private func setAvailableVersion(_ version: String?) {
        guard availableVersion != version else { return }
        availableVersion = version
        for item in menuItems.allObjects { refresh(item) }
        onAvailabilityChange?(version)
    }

    private func refresh(_ item: NSMenuItem) {
        item.title = isUpdateAvailable ? "Update Available…" : "Check for Updates…"
        item.toolTip = availableVersion.map { "Version \($0) is available. Review and install the update." }
    }
}

#if CHIT_DISTRIBUTION
extension SoftwareUpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        reminder.finishSession()
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        // Sparkle 2.10 checks this before committing installation and requesting
        // termination. Reuse ordinary quit's IME and draft-save refusal.
        shouldRelaunch()
    }
}

// Sparkle's standard UI calls its delegate on the main thread, but its Objective-C
// protocol does not carry Swift actor annotations.
extension SoftwareUpdateReminder: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Ordinary scheduled updates get a persistent menu-bar reminder without
        // interrupting work. Preserve Sparkle's standard alerts for critical updates.
        update.isCriticalUpdate
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        showUpdate(version: update.displayVersionString)
    }

    func standardUserDriverWillFinishUpdateSession() {
        // Dismiss, Skip This Version, cancellation, and errors finish the session.
        // Don't keep a reminder for an update the user has already dealt with.
        finishSession()
    }
}
#endif

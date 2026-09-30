import AppKit

/// File panels are independent windows: a sheet cannot fit over Chit's small floating panel.
@MainActor
enum FilePanelPresenter {
    @MainActor
    private final class Presentation {
        let panel: NSSavePanel
        let screen: NSScreen?
        var observers: [NSObjectProtocol] = []
        var hasCentered = false
        var isCancelled = false
        var isPositioning = false

        init(panel: NSSavePanel, screen: NSScreen?) {
            self.panel = panel
            self.screen = screen
        }
    }

    private static var presentation: Presentation?
    private static var cancellationGeneration = 0
    static var isPresenting: Bool { presentation != nil }
    static var activePanel: NSSavePanel? {
        guard let presentation, !presentation.isCancelled else { return nil }
        return presentation.panel
    }

    static func present(_ panel: NSSavePanel, relativeTo window: NSWindow?,
                        completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard presentation == nil, window?.attachedSheet == nil else {
            _ = focusActivePanel()
            completion(.cancel)
            return
        }
        let current = Presentation(panel: panel, screen: window?.screen ?? NSScreen.main)
        let generation = cancellationGeneration
        presentation = current
        panel.level = .modalPanel
        // The native UI arrives from AppKit's panel service. Position again when
        // it becomes key or changes size, rather than guessing its final dimensions.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification] {
            current.observers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { _ in
                MainActor.assumeIsolated {
                    guard !current.isCancelled else { return }
                    position(current, center: !current.hasCentered)
                    if name == NSWindow.didBecomeKeyNotification { current.hasCentered = true }
                }
            })
        }
        position(current, center: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            for observer in current.observers { NotificationCenter.default.removeObserver(observer) }
            current.observers.removeAll()
            panel.orderOut(nil)
            if presentation === current { presentation = nil }
            // A chained folder/save picker or alert starts after the old native
            // window has left. Hide/Quit also invalidates a queued successful choice.
            DispatchQueue.main.async {
                completion(current.isCancelled || generation != cancellationGeneration ? .cancel : response)
            }
        }
        position(current, center: true)
    }

    @discardableResult
    static func focusActivePanel() -> Bool {
        guard let panel = activePanel else { return false }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    @discardableResult
    static func cancelActivePanel() -> Bool {
        cancellationGeneration += 1
        guard let current = presentation else { return false }
        current.isCancelled = true
        current.panel.cancel(nil)
        current.panel.orderOut(nil)
        return true
    }

    static func keepActivePanelOnScreen() {
        if let current = presentation { position(current, center: false) }
    }

    private static func position(_ current: Presentation, center: Bool) {
        guard !current.isPositioning, !current.isCancelled else { return }
        let preferred = current.hasCentered ? current.panel.screen : current.screen
        let screenID = preferred?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == screenID
        }) ?? NSScreen.main else { return }
        current.isPositioning = true
        defer { current.isPositioning = false }
        let visible = screen.visibleFrame
        var frame = current.panel.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        if center {
            frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
        }
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        if current.panel.frame != frame { current.panel.setFrame(frame, display: true) }
    }
}

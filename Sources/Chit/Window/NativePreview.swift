import AppKit
import ScreenCaptureKit

/// Explicit --snapshot-backdrop mode only. Uses an app-owned backdrop and the
/// current-process capture API, never requesting access to another app or desktop.
@MainActor
enum NativePreview {
    /// A controlled material preview for captures that flatten behind-window effects.
    /// This changes blending only in an explicitly requested, isolated snapshot.
    static func containBackdrop(in panel: NSWindow) {
        guard let surface = panel.contentView as? PanelSurface else { return }
        let root = NSView(frame: surface.frame)
        let backdrop = PreviewBackdrop(frame: root.bounds.insetBy(dx: -64, dy: -48))
        backdrop.autoresizingMask = [.width, .height]
        root.addSubview(backdrop)
        panel.contentView = root
        surface.frame = root.bounds
        surface.autoresizingMask = [.width, .height]
        surface.blendingMode = .withinWindow
        root.addSubview(surface)
    }

    static func makeBackdrop(behind panel: NSWindow) -> NSWindow {
        let window = NSWindow(contentRect: panel.frame.insetBy(dx: -64, dy: -48), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = panel.level
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.contentView = PreviewBackdrop(frame: NSRect(origin: .zero, size: window.frame.size))
        window.order(.below, relativeTo: panel.windowNumber)
        return window
    }

    static func capture(panel: NSWindow, backdrop: NSWindow, path: String) async throws {
        guard #available(macOS 14.4, *) else {
            throw error("Composited previews require macOS 14.4 or newer.")
        }
        let content = try await SCShareableContent.currentProcess
        let ownIDs = Set([CGWindowID(panel.windowNumber), CGWindowID(backdrop.windowNumber)])
        let windows = content.windows.filter { ownIDs.contains($0.windowID) && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
        guard windows.count == 2,
              let background = windows.first(where: { $0.windowID == CGWindowID(backdrop.windowNumber) }),
              let number = panel.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
            throw error("The app's own preview windows are not available for capture.")
        }
        let filter = SCContentFilter(display: display, including: windows)
        filter.includeMenuBar = false
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.shouldBeOpaque = false
        config.sourceRect = background.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let scale = panel.backingScaleFactor
        config.width = Int(background.frame.width * scale)
        config.height = Int(background.frame.height * scale)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw error("The preview image could not be encoded.")
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        print("Captured only this app's panel and test backdrop: \(image.width)×\(image.height).")
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "Chit.Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private final class PreviewBackdrop: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let colors = [NSColor(srgbRed: 0.72, green: 0.79, blue: 0.85, alpha: 1),
                      NSColor(srgbRed: 0.55, green: 0.45, blue: 0.64, alpha: 1),
                      NSColor(srgbRed: 0.15, green: 0.18, blue: 0.25, alpha: 1)]
        NSGradient(colors: colors)?.draw(in: bounds, angle: 0)
        // Sharp bars make blur visibly distinguishable from ordinary transparency.
        for x in stride(from: CGFloat(12), to: bounds.width, by: 24) {
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSRect(x: x, y: 0, width: 4, height: bounds.height).fill()
        }
    }
}

import AppKit
import Combine
import SwiftUI

@MainActor
final class TodoPanel: NSPanel {
    var dismissPanel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Borderless windows have no standard close button; keep all close paths
    // routed through the delegate's save and input-composition guards.
    override func performClose(_ sender: Any?) { dismissPanel?() }

    override func cancelOperation(_ sender: Any?) {
        if let editor = firstResponder as? NSTextView, editor.hasMarkedText() { return }
        guard attachedSheet == nil else { return }
        dismissPanel?()
    }
}

/// The material and tint are separate from the hosting view so text stays fully opaque.
@MainActor
final class PanelSurface: NSView {
    private let materialView = NSVisualEffectView()
    private let tint = NSView()
    private var accessibilityObserver: NSObjectProtocol?
    private var lastMaskSize = NSSize.zero
    private var usesSolidBackground = false
    private var backgroundOpacity = 0.80
    private var opacitySubscription: AnyCancellable?

    override var isOpaque: Bool { false }

    // The isolated preview changes this one layer; ordinary windows blur behind
    // the app. Keeping it separate lets the background fade without dimming text.
    var blendingMode: NSVisualEffectView.BlendingMode {
        get { materialView.blendingMode }
        set { materialView.blendingMode = newValue }
    }

    init(model: AppModel) {
        super.init(frame: NSRect(x: 0, y: 0, width: 424, height: 350))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        materialView.material = .underWindowBackground
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.appearance = NSAppearance(named: .darkAqua)
        appearance = NSAppearance(named: .darkAqua)
        tint.wantsLayer = true
        let hosting = ClearHostingView(rootView: ContentView(model: model).preferredColorScheme(.dark))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        let resizing = PanelResizeOverlay()
        for view in [materialView, tint, hosting] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: view === hosting ? -8 : 0)
            ])
        }
        NSLayoutConstraint.activate([
            materialView.topAnchor.constraint(equalTo: topAnchor),
            tint.topAnchor.constraint(equalTo: topAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor, constant: 5)
        ])
        resizing.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resizing)
        NSLayoutConstraint.activate([
            resizing.leadingAnchor.constraint(equalTo: leadingAnchor),
            resizing.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizing.topAnchor.constraint(equalTo: topAnchor),
            resizing.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateAccessibilityAppearance()
        opacitySubscription = model.$backgroundOpacity.sink { [weak self] opacity in
            self?.backgroundOpacity = opacity
            self?.applyBackgroundOpacity()
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAccessibilityAppearance() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }

    func updateAccessibilityAppearance(reduceTransparency: Bool? = nil, increaseContrast: Bool? = nil) {
        let solid = reduceTransparency ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let contrast = increaseContrast ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        usesSolidBackground = solid || contrast
        applyBackgroundOpacity()
        tint.layer?.backgroundColor = NSColor(srgbRed: 30 / 255, green: 30 / 255, blue: 46 / 255, alpha: solid ? 1 : (contrast ? 0.85 : 0.12)).cgColor
        lastMaskSize = .zero
        needsLayout = true
    }

    private func applyBackgroundOpacity() {
        let opacity = usesSolidBackground ? 1 : CGFloat(backgroundOpacity)
        materialView.alphaValue = opacity
        tint.alphaValue = opacity
    }

    override func layout() {
        super.layout()
        guard lastMaskSize != bounds.size else { return }
        lastMaskSize = bounds.size
        guard bounds.width > 20, bounds.height > 20 else {
            materialView.maskImage = nil
            tint.layer?.mask = nil
            return
        }
        let mask = Self.featherMask(size: bounds.size, feather: usesSolidBackground ? 0 : 5)
        materialView.maskImage = mask
        let tintMask = CALayer()
        tintMask.frame = tint.bounds
        tintMask.contents = mask.cgImage(forProposedRect: nil, context: nil, hints: nil)
        tintMask.contentsScale = window?.backingScaleFactor ?? 2
        tint.layer?.mask = tintMask
    }

    private static func featherMask(size: NSSize, feather: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setBlendMode(.copy)
            if feather == 0 {
                // Accessibility modes retain ordinary rounded window corners,
                // with a completely opaque interior and no translucent rim.
                NSColor.white.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
                return true
            }
            // Smooth alpha falloff only affects the material/tint, never foreground content.
            for step in 0...24 {
                let inset = feather * CGFloat(step) / 24
                let t = min(1, inset / feather)
                let alpha = t * t * (3 - 2 * t)
                NSColor(white: 1, alpha: alpha).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: max(0, 12 - inset), yRadius: max(0, 12 - inset)).fill()
            }
            return true
        }
    }
}

private final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override var allowsVibrancy: Bool { false }
}

enum WindowGeometry {
    /// Resize in screen coordinates while keeping the opposite edges fixed.
    static func resized(_ original: NSRect, delta: NSSize, edges: PanelResizeEdges, minimumSize: NSSize = NSSize(width: 320, height: 240)) -> NSRect {
        var result = original
        if edges.contains(.left) {
            result.origin.x = min(original.minX + delta.width, original.maxX - minimumSize.width)
            result.size.width = original.maxX - result.minX
        } else if edges.contains(.right) {
            result.size.width = max(minimumSize.width, original.width + delta.width)
        }
        if edges.contains(.bottom) {
            result.origin.y = min(original.minY + delta.height, original.maxY - minimumSize.height)
            result.size.height = original.maxY - result.minY
        } else if edges.contains(.top) {
            result.size.height = max(minimumSize.height, original.height + delta.height)
        }
        return result
    }

    static func reachable(_ proposed: NSRect, screens: [NSRect]) -> NSRect {
        guard let screen = screens.max(by: { intersectionArea($0, proposed) < intersectionArea($1, proposed) }) else { return proposed }
        var frame = proposed
        frame.size.width = min(max(frame.width, 320), screen.width)
        frame.size.height = min(max(frame.height, 240), screen.height)
        frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        return frame
    }

    private static func intersectionArea(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

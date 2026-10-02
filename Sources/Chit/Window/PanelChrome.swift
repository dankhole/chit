import AppKit
import SwiftUI

/// The native close control lives alongside list navigation in the header.
@MainActor
final class PanelChrome: NSView {
    static let height = Mocha.headerRowHeight
    let closeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        closeButton.cell = CenteredCloseButtonCell(textCell: "")
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Hide Chit")?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.contentTintColor = Mocha.nsBlue
        closeButton.toolTip = "Hide Chit (⌘W)"
        closeButton.setAccessibilityLabel("Hide Chit")
        closeButton.target = self
        closeButton.action = #selector(closePanel)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Preserve the standard accessibility close-window relationship even
        // though the system titlebar and its close button have been removed.
        window?.setAccessibilityCloseButton(closeButton)
    }

    override func mouseDown(with event: NSEvent) {
        guard window?.attachedSheet == nil else { return }
        window?.performDrag(with: event)
    }

    @objc private func closePanel() { window?.performClose(nil) }
}

struct PanelCloseControl: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelChrome { PanelChrome() }
    func updateNSView(_ view: PanelChrome, context: Context) {}
}

struct HeaderDragArea: NSViewRepresentable {
    var excludedRects: [CGRect]

    func makeNSView(context: Context) -> HeaderDragView {
        let view = HeaderDragView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: HeaderDragView, context: Context) {
        view.excludedRects = excludedRects
    }
}

/// Only blank header space moves the window. Interactive bounds are measured
/// by SwiftUI, including controls whose rendering has no individual NSView.
final class HeaderDragView: NSView {
    static let blankClick = Notification.Name("Chit.blankHeaderClick")
    var excludedRects: [CGRect] = []
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard window?.attachedSheet == nil, !excludedRects.isEmpty,
              bounds.contains(local), !excludedRects.contains(where: { $0.contains(local) }) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard window?.attachedSheet == nil else { return }
        window?.performDrag(with: event)
    }
}

/// Inline button cells align symbols like text. Center this control's image in
/// its native hit target, matching the surrounding header controls.
private final class CenteredCloseButtonCell: NSButtonCell {
    override func imageRect(forBounds rect: NSRect) -> NSRect {
        guard let image else { return super.imageRect(forBounds: rect) }
        return NSRect(x: rect.midX - image.size.width / 2,
                      y: rect.midY - image.size.height / 2,
                      width: image.size.width,
                      height: image.size.height)
    }
}

struct PanelResizeEdges: OptionSet {
    let rawValue: Int
    static let left = PanelResizeEdges(rawValue: 1 << 0)
    static let right = PanelResizeEdges(rawValue: 1 << 1)
    static let bottom = PanelResizeEdges(rawValue: 1 << 2)
    static let top = PanelResizeEdges(rawValue: 1 << 3)
}

/// Only the perimeter participates in hit testing; the center remains normal native UI.
/// Explicit drag handling makes resizing independent of undocumented borderless behavior.
@MainActor
final class PanelResizeOverlay: NSView {
    private var dragStart: NSPoint?
    private var originalFrame = NSRect.zero
    private var draggedEdges: PanelResizeEdges = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard window?.attachedSheet == nil else { return nil }
        let local = convert(point, from: superview)
        return resizeEdges(at: local).isEmpty ? nil : self
    }

    func resizeEdges(at point: NSPoint) -> PanelResizeEdges {
        zones.first(where: { $0.rect.contains(point) })?.edges ?? []
    }

    override func resetCursorRects() {
        for zone in zones { addCursorRect(zone.rect, cursor: cursor(for: zone.edges)) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, window.attachedSheet == nil else { return }
        draggedEdges = resizeEdges(at: convert(event.locationInWindow, from: nil))
        guard !draggedEdges.isEmpty else { return }
        originalFrame = window.frame
        dragStart = NSEvent.mouseLocation
        cursor(for: draggedEdges).set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStart else { return }
        let current = NSEvent.mouseLocation
        let frame = WindowGeometry.resized(originalFrame, delta: NSSize(width: current.x - dragStart.x, height: current.y - dragStart.y), edges: draggedEdges, minimumSize: window.minSize)
        window.setFrame(frame, display: true)
        cursor(for: draggedEdges).set()
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil
        draggedEdges = []
        if let window {
            // Borderless frames do not get the titled window's screen constraint.
            // A top-edge drag into the menu bar must not strand the drag strip.
            let reachable = WindowGeometry.reachable(window.frame, screens: NSScreen.screens.map(\.visibleFrame))
            if reachable != window.frame { window.setFrame(reachable, display: true) }
        }
        NSCursor.arrow.set()
        window?.invalidateCursorRects(for: self)
    }

    private var zones: [(rect: NSRect, edges: PanelResizeEdges)] {
        let edge: CGFloat = 6
        let corner: CGFloat = 14
        let w = bounds.width
        let h = bounds.height
        return [
            (NSRect(x: 0, y: 0, width: corner, height: corner), [.left, .bottom]),
            (NSRect(x: w - corner, y: 0, width: corner, height: corner), [.right, .bottom]),
            (NSRect(x: 0, y: h - corner, width: corner, height: corner), [.left, .top]),
            (NSRect(x: w - corner, y: h - corner, width: corner, height: corner), [.right, .top]),
            (NSRect(x: 0, y: corner, width: edge, height: max(0, h - 2 * corner)), .left),
            (NSRect(x: w - edge, y: corner, width: edge, height: max(0, h - 2 * corner)), .right),
            (NSRect(x: corner, y: 0, width: max(0, w - 2 * corner), height: edge), .bottom),
            (NSRect(x: corner, y: h - edge, width: max(0, w - 2 * corner), height: edge), .top)
        ]
    }

    private func cursor(for edges: PanelResizeEdges) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch edges {
            case [.left, .top]: position = .topLeft
            case [.right, .top]: position = .topRight
            case [.left, .bottom]: position = .bottomLeft
            case [.right, .bottom]: position = .bottomRight
            case .left: position = .left
            case .right: position = .right
            case .top: position = .top
            default: position = .bottom
            }
            return .frameResize(position: position, directions: .all)
        }
        // Standard system resize cursors remain available on the macOS 14 floor.
        return edges.intersection([.left, .right]).isEmpty ? .resizeUpDown : .resizeLeftRight
    }
}

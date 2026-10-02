import AppKit
import SwiftUI

struct SidebarLayout {
    static let railWidth: CGFloat = 44
    static let expandedWidth: CGFloat = 176
    static let minimumExpandedWidth: CGFloat = 160
    static let maximumExpandedWidth: CGFloat = 280
    static let dividerWidth: CGFloat = 1
    static let minimumTaskWidth: CGFloat = 276
    static let minimumCollapsedWindowWidth: CGFloat = railWidth + minimumTaskWidth

    let expanded: Bool
    let preferredWidth: CGFloat
    var sidebarWidth: CGFloat { expanded ? preferredWidth : Self.railWidth }
    var taskInset: CGFloat { sidebarWidth + Self.dividerWidth }
    var minimumWindowWidth: CGFloat {
        expanded ? sidebarWidth + Self.dividerWidth + Self.minimumTaskWidth : Self.minimumCollapsedWindowWidth
    }

    init(expanded: Bool, preferredWidth: Double = 176) {
        self.expanded = expanded
        self.preferredWidth = preferredWidth.isFinite
            ? min(Self.maximumExpandedWidth, max(Self.minimumExpandedWidth, CGFloat(preferredWidth)))
            : Self.expandedWidth
    }
}

enum SidebarEventDisposition { case normal, consume, sidebar }

/// Marks the whole padded navigation content, including group labels and row
/// gaps. Only the background below this content can toggle sidebar expansion.
struct SidebarNavigationContentBoundary: NSViewRepresentable {
    func makeNSView(context: Context) -> SidebarNavigationContentRegion { SidebarNavigationContentRegion() }
    func updateNSView(_ view: SidebarNavigationContentRegion, context: Context) {}
}

@MainActor
final class SidebarNavigationContentRegion: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Navigation is nonmodal, but its native pointer events must precede the
/// panel's task routing. The boundary never takes focus or disables editors.
struct SidebarInteractionBoundary: NSViewRepresentable {
    let onBlankToggle: () -> Void
    func makeNSView(context: Context) -> SidebarInteractionRegion { SidebarInteractionRegion() }
    func updateNSView(_ view: SidebarInteractionRegion, context: Context) { view.onBlankToggle = onBlankToggle }
    static func dismantleNSView(_ view: SidebarInteractionRegion, coordinator: ()) { view.detach() }
}

@MainActor
final class SidebarInteractionRegion: NSView {
    var onBlankToggle: () -> Void = {}
    private weak var owningPanel: TodoPanel?
    private var blockedPointerButtons: Set<Int> = []
    private var blankPress: BlankPress?
    private weak var pressedDivider: SidebarDividerView?
    private struct BlankPress {
        let start: NSPoint
        var cancelled = false
    }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard owningPanel !== window else { return }
        detach()
        guard let panel = window as? TodoPanel else { return }
        owningPanel = panel
        panel.sidebarInteractionOwner = self
        panel.sidebarEventDisposition = { [weak self] event in self?.disposition(for: event) ?? .normal }
    }

    func detach() {
        if owningPanel?.sidebarInteractionOwner === self {
            owningPanel?.sidebarEventDisposition = nil
            owningPanel?.sidebarInteractionOwner = nil
        }
        owningPanel = nil
        blockedPointerButtons = []
        blankPress = nil
        pressedDivider = nil
    }

    private func disposition(for event: NSEvent) -> SidebarEventDisposition {
        guard let panel = owningPanel, panel.attachedSheet == nil else { return .normal }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            blankPress = nil
            blockedPointerButtons.remove(event.buttonNumber)
            // The divider's generous hit area extends into task padding. Route
            // its gesture directly: NSWindow otherwise makes this keyboard-
            // focusable view first responder before delivering mouseDown.
            if event.type == .leftMouseDown { pressedDivider = nil }
            if let divider = pointerHitView(at: event.locationInWindow) as? SidebarDividerView {
                if event.type == .leftMouseDown {
                    pressedDivider = divider
                    divider.mouseDown(with: event)
                    return .consume
                }
                return .sidebar
            }
            guard contains(event.locationInWindow) else { return .normal }
            if event.type == .leftMouseDown,
               event.modifierFlags.intersection([.control, .option, .command, .shift]).isEmpty,
               containsBlankPoint(event.locationInWindow) {
                // A safe geometry toggle must not move focus from an editor,
                // including one that still owns unpublished marked text.
                blankPress = BlankPress(start: event.locationInWindow)
                return .consume
            }
            // Guard before a navigation button can move focus away from the
            // owner of unpublished marked text. The model guards other callers.
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
                blockedPointerButtons.insert(event.buttonNumber)
                return .consume
            }
            return .sidebar
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if event.type == .leftMouseUp, let divider = pressedDivider {
                pressedDivider = nil
                divider.mouseUp(with: event)
                return .consume
            }
            if event.type == .leftMouseUp, let press = blankPress {
                blankPress = nil
                if !press.cancelled, event.modifierFlags.intersection([.control, .option, .command, .shift]).isEmpty,
                   pointerDistance(from: press.start, to: event.locationInWindow) < 4,
                   containsBlankPoint(event.locationInWindow) { onBlankToggle() }
                return .consume
            }
            if blockedPointerButtons.remove(event.buttonNumber) != nil { return .consume }
            return contains(event.locationInWindow) ? .sidebar : .normal
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            if event.type == .leftMouseDragged, let divider = pressedDivider {
                divider.mouseDragged(with: event)
                return .consume
            }
            if event.type == .leftMouseDragged, let press = blankPress {
                if pointerDistance(from: press.start, to: event.locationInWindow) >= 4 { blankPress?.cancelled = true }
                return .consume
            }
            if blockedPointerButtons.contains(event.buttonNumber) { return .consume }
            return contains(event.locationInWindow) ? .sidebar : .normal
        case .scrollWheel:
            blankPress?.cancelled = true
            return contains(event.locationInWindow) ? .sidebar : .normal
        default:
            return .normal
        }
    }

    func contains(_ windowPoint: NSPoint) -> Bool {
        let point = convert(windowPoint, from: nil)
        return bounds.contains(point) && visibleRect.contains(point)
    }

    func containsBlankPoint(_ windowPoint: NSPoint) -> Bool {
        guard contains(windowPoint), let panel = owningPanel, let content = panel.contentView else { return false }
        var hit = pointerHitView(at: windowPoint)
        while let view = hit {
            if view is NSControl || view is NSScroller || view is PanelResizeOverlay || view is SidebarDividerView { return false }
            hit = view.superview
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        guard let navigation = descendants(content).compactMap({ $0 as? SidebarNavigationContentRegion })
            .first(where: { convert($0.bounds, from: $0).intersects(bounds) }) else { return false }
        let point = convert(windowPoint, from: nil)
        return point.y >= convert(navigation.bounds, from: navigation).maxY
    }

    private func pointerHitView(at windowPoint: NSPoint) -> NSView? {
        guard let content = owningPanel?.contentView else { return nil }
        let hitPoint = content.superview?.convert(windowPoint, from: nil) ?? windowPoint
        return content.hitTest(hitPoint)
    }

    private func pointerDistance(from start: NSPoint, to end: NSPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}

struct SidebarResizeDivider: NSViewRepresentable {
    static let hitWidth: CGFloat = 6
    @ObservedObject var model: AppModel

    func makeNSView(context: Context) -> SidebarDividerView { SidebarDividerView() }
    func updateNSView(_ view: SidebarDividerView, context: Context) {
        view.active = model.sidebarExpanded
        view.sidebarWidth = CGFloat(model.sidebarExpandedWidth)
        view.onResize = { model.setSidebarExpandedWidth(Double($0)) }
        view.setAccessibilityValue(NSNumber(value: model.sidebarExpandedWidth))
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
}

@MainActor
final class SidebarDividerView: NSView {
    var active = false
    var sidebarWidth = SidebarLayout.expandedWidth
    var onResize: (CGFloat) -> Void = { _ in }
    private var dragStartX: CGFloat?
    private var dragStartWidth = SidebarLayout.expandedWidth

    override var acceptsFirstResponder: Bool { active }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Sidebar width")
        setAccessibilityIdentifier("sidebar-resize")
        setAccessibilityHelp("Drag to resize lists, or use Left and Right Arrow to adjust by ten points.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { active ? super.hitTest(point) : nil }
    override func resetCursorRects() {
        if active { addCursorRect(bounds, cursor: .resizeLeftRight) }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard active else { return }
        Mocha.nsSecondary.withAlphaComponent(0.13).setFill()
        NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()
        if window?.firstResponder === self {
            Mocha.nsBlue.setStroke()
            NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }

    override func mouseDown(with event: NSEvent) {
        guard active, let window, window.attachedSheet == nil else { return }
        dragStartX = window.convertPoint(toScreen: event.locationInWindow).x
        dragStartWidth = sidebarWidth
    }
    override func mouseDragged(with event: NSEvent) {
        guard active, let start = dragStartX, let window else { return }
        resize(to: dragStartWidth + window.convertPoint(toScreen: event.locationInWindow).x - start)
    }
    override func mouseUp(with event: NSEvent) { dragStartX = nil }
    override func keyDown(with event: NSEvent) {
        guard active, event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 123: resize(to: sidebarWidth - 10)
        case 124: resize(to: sidebarWidth + 10)
        default: super.keyDown(with: event)
        }
    }
    override func accessibilityPerformIncrement() -> Bool {
        guard active else { return false }
        resize(to: sidebarWidth + 10)
        return true
    }
    override func accessibilityPerformDecrement() -> Bool {
        guard active else { return false }
        resize(to: sidebarWidth - 10)
        return true
    }
    private func resize(to value: CGFloat) {
        let width = min(SidebarLayout.maximumExpandedWidth, max(SidebarLayout.minimumExpandedWidth, value))
        guard width != sidebarWidth else { return }
        (window as? TodoPanel)?.discardSidebarExpansionRestore()
        sidebarWidth = width
        setAccessibilityValue(NSNumber(value: Double(width)))
        onResize(width)
    }
}

/// SwiftUI supplies keyboard and accessibility activation. This native pointer
/// overlay toggles geometry without first moving focus from a composing editor.
struct SidebarTogglePointerBoundary: NSViewRepresentable {
    let onToggle: () -> Void
    func makeNSView(context: Context) -> SidebarTogglePointerRegion { SidebarTogglePointerRegion() }
    func updateNSView(_ view: SidebarTogglePointerRegion, context: Context) { view.onToggle = onToggle }
}

@MainActor
final class SidebarTogglePointerRegion: NSView {
    var onToggle: () -> Void = {}
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let event = NSApp.currentEvent, event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, window.attachedSheet == nil else { return }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                         until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp {
                if bounds.contains(convert(next.locationInWindow, from: nil)) { onToggle() }
                return
            }
        }
    }
}

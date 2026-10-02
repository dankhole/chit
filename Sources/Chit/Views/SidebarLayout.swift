import AppKit
import Combine
import SwiftUI

struct SidebarLayout {
    static let dividerWidth: CGFloat = 6
    let availableWidth: CGFloat
    let isDocked: Bool
    let sidebarVisible: Bool
    let drawerVisible: Bool
    let sidebarWidth: CGFloat

    var taskInset: CGFloat { isDocked && sidebarVisible ? sidebarWidth + Self.dividerWidth : 0 }

    init(availableWidth: CGFloat, preferredWidth: Double, dockedOpen: Bool, drawerOpen: Bool) {
        self.availableWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
        isDocked = self.availableWidth >= 640
        sidebarVisible = isDocked ? dockedOpen : drawerOpen
        drawerVisible = !isDocked && drawerOpen
        if isDocked {
            let preferred = preferredWidth.isFinite ? min(320, max(200, preferredWidth)) : 240
            sidebarWidth = min(CGFloat(preferred), self.availableWidth - 360 - Self.dividerWidth)
        } else {
            sidebarWidth = max(0, min(280, self.availableWidth - 40))
        }
    }
}

private struct SidebarBlocksTextInputKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sidebarBlocksTextInput: Bool {
        get { self[SidebarBlocksTextInputKey.self] }
        set { self[SidebarBlocksTextInputKey.self] = newValue }
    }
}

enum SidebarEventDisposition { case normal, consume, sidebar }

/// Register with the owning panel instead of layering a click gesture over its
/// native task routing. A drawer click must never reach an editor behind it.
struct SidebarModalBoundary: NSViewRepresentable {
    @ObservedObject var model: AppModel
    let active: Bool

    func makeNSView(context: Context) -> SidebarModalRegion { SidebarModalRegion() }
    func updateNSView(_ view: SidebarModalRegion, context: Context) {
        view.setModel(model)
        view.setActive(active)
    }
    static func dismantleNSView(_ view: SidebarModalRegion, coordinator: ()) { view.detach() }
}

@MainActor
final class SidebarModalRegion: NSView {
    weak var model: AppModel?
    private weak var owningPanel: TodoPanel?
    private weak var previousResponder: NSResponder?
    private var previousProjectID = ""
    private var desiredActive = false
    private var appliedActive = false
    private var editorStates: [EditorState] = []
    private var drawerObservation: AnyCancellable?

    private struct EditorState {
        weak var editor: PlainTextView?
        let editable: Bool
        let selectable: Bool
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { desiredActive }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard owningPanel !== window else { return }
        unregister()
        guard let panel = window as? TodoPanel else { return }
        owningPanel = panel
        panel.sidebarInteractionOwner = self
        panel.sidebarEventDisposition = { [weak self] event in self?.disposition(for: event) ?? .normal }
        panel.sidebarDidRouteEvent = { [weak self] _ in self?.keepNativeFocusInsideDrawer() }
        panel.dismissSidebarDrawer = { [weak self] in
            guard let self, self.desiredActive else { return false }
            self.model?.dismissSidebarDrawer()
            return true
        }
        applyActiveState()
    }

    func setActive(_ active: Bool) {
        desiredActive = active
        applyActiveState()
    }

    func setModel(_ model: AppModel) {
        guard self.model !== model else { return }
        self.model = model
        // Published sends synchronously before SwiftUI changes focus. Capture
        // the original native editor before the drawer's focused row takes over.
        drawerObservation = model.$sidebarDrawerOpen.sink { [weak self, weak model] open in
            MainActor.assumeIsolated { self?.setActive(open && model?.sidebarIsDocked == false) }
        }
    }

    func detach() {
        drawerObservation = nil
        desiredActive = false
        applyActiveState()
        unregister()
    }

    private func unregister() {
        if owningPanel?.sidebarInteractionOwner === self {
            owningPanel?.sidebarEventDisposition = nil
            owningPanel?.sidebarDidRouteEvent = nil
            owningPanel?.dismissSidebarDrawer = nil
            owningPanel?.sidebarInteractionOwner = nil
        }
        owningPanel = nil
    }

    private func applyActiveState() {
        guard let panel = owningPanel, desiredActive != appliedActive else { return }
        appliedActive = desiredActive
        if desiredActive {
            previousResponder = panel.firstResponder
            previousProjectID = model?.selectedProjectID ?? ""
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let editors = panel.contentView.map(descendants)?.compactMap { $0 as? PlainTextView } ?? []
            editorStates = editors.map { EditorState(editor: $0, editable: $0.isEditable, selectable: $0.isSelectable) }
            // SwiftUI's disabled environment does not make an NSTextView inert.
            // Preserve each native value and remove these editors from input
            // while the modal sidebar owns focus.
            for editor in editors {
                if editor.isEditable { editor.isEditable = false }
                if editor.isSelectable { editor.isSelectable = false }
            }
            if panel.firstResponder is PlainTextView { panel.makeFirstResponder(self) }
        } else {
            for state in editorStates {
                guard let editor = state.editor else { continue }
                if editor.isEditable != state.editable { editor.isEditable = state.editable }
                if editor.isSelectable != state.selectable { editor.isSelectable = state.selectable }
            }
            editorStates = []
            if previousProjectID == model?.selectedProjectID,
               let previous = previousResponder as? NSView, previous.window === panel,
               (panel.firstResponder as? NSTextView)?.hasMarkedText() != true {
                panel.makeFirstResponder(previous)
                // Clearing SwiftUI's drawer focus occurs after this synchronous
                // state publication. Restore again after that update only if no
                // other native text control has acquired focus in the meantime.
                DispatchQueue.main.async { [weak self, weak panel, weak previous] in
                    guard let self, let panel, let previous, !self.desiredActive,
                          self.previousProjectID == self.model?.selectedProjectID,
                          previous.window === panel,
                          !(panel.firstResponder is NSTextView) else { return }
                    panel.makeFirstResponder(previous)
                }
            }
            previousResponder = nil
        }
    }

    private func disposition(for event: NSEvent) -> SidebarEventDisposition {
        guard desiredActive, let panel = owningPanel, panel.attachedSheet == nil else { return .normal }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard contains(event.locationInWindow) else {
                model?.dismissSidebarDrawer()
                return .consume
            }
            return .sidebar
        case .scrollWheel, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return contains(event.locationInWindow) ? .sidebar : .consume
        case .keyDown:
            if event.keyCode == 53 {
                if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true { return .sidebar }
                model?.dismissSidebarDrawer()
                return .consume
            }
            if panel.firstResponder is PlainTextView {
                // An accessibility or key-loop request cannot reactivate an
                // editor covered by the drawer.
                panel.makeFirstResponder(self)
                return .consume
            }
            return .sidebar
        default:
            return .sidebar
        }
    }

    private func contains(_ windowPoint: NSPoint) -> Bool {
        let point = convert(windowPoint, from: nil)
        return bounds.contains(point) && visibleRect.contains(point)
    }

    private func keepNativeFocusInsideDrawer() {
        guard desiredActive, let panel = owningPanel, panel.attachedSheet == nil,
              panel.firstResponder is PlainTextView else { return }
        panel.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48, let panel = owningPanel {
            if event.modifierFlags.contains(.shift) { panel.selectPreviousKeyView(nil) }
            else { panel.selectNextKeyView(nil) }
            if panel.firstResponder is PlainTextView { panel.makeFirstResponder(self) }
        } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { model?.dismissSidebarDrawer() }
}

struct SidebarResizeDivider: NSViewRepresentable {
    @ObservedObject var model: AppModel
    let availableWidth: CGFloat
    let actualWidth: CGFloat

    func makeNSView(context: Context) -> SidebarDividerView { SidebarDividerView() }
    func updateNSView(_ view: SidebarDividerView, context: Context) {
        view.sidebarWidth = actualWidth
        view.maximumWidth = min(320, availableWidth - 360 - SidebarLayout.dividerWidth)
        view.onResize = { model.setSidebarWidth(Double($0)) }
        view.setAccessibilityValue(NSNumber(value: Double(actualWidth)))
    }
}

@MainActor
final class SidebarDividerView: NSView {
    var sidebarWidth: CGFloat = 240
    var maximumWidth: CGFloat = 320
    var onResize: (CGFloat) -> Void = { _ in }
    private var dragStartX: CGFloat?
    private var dragStartWidth: CGFloat = 240

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Sidebar width")
        setAccessibilityIdentifier("sidebar-resize")
        setAccessibilityHelp("Drag to resize the sidebar, or adjust by ten points.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func draw(_ dirtyRect: NSRect) {
        Mocha.nsSecondary.withAlphaComponent(0.15).setFill()
        NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()
    }
    override func mouseDown(with event: NSEvent) {
        dragStartX = NSEvent.mouseLocation.x
        dragStartWidth = sidebarWidth
    }
    override func mouseDragged(with event: NSEvent) {
        guard let dragStartX else { return }
        resize(to: dragStartWidth + NSEvent.mouseLocation.x - dragStartX)
    }
    override func mouseUp(with event: NSEvent) { dragStartX = nil }
    override func accessibilityPerformIncrement() -> Bool { resize(to: sidebarWidth + 10); return true }
    override func accessibilityPerformDecrement() -> Bool { resize(to: sidebarWidth - 10); return true }
    private func resize(to value: CGFloat) { onResize(min(maximumWidth, max(200, value))) }
}

import AppKit
import SwiftUI

enum TitleClickDisposition { case editOnly, toggleDetails, reject }

struct TaskDeadlineActions {
    let hasDeadline: Bool
    let edit: () -> Void
    let remove: () -> Void
}

/// A plain NSTextView keeps native composition, selection, clipboard and text Undo.
struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let identity: String
    var placeholder = ""
    var fontSize: CGFloat = 14
    var secondary = false
    var completed = false
    var submitOnReturn = false
    var links = false
    var compactTrailingNewlines = false
    var deadlineActions: TaskDeadlineActions? = nil
    var onTitlePointerDown: (() -> TitleClickDisposition)? = nil
    var onTitleSingleClick: (() -> Void)? = nil
    var onTitleFocus: (() -> Bool)? = nil
    var onSubmit: () -> Void = {}
    var onEndEditing: () -> Void = {}
    var onTextChange: ((String, String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PlainTextView {
        let savedSelection = Coordinator.selections[identity]
        let view = PlainTextView()
        view.editorIdentity = identity
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isEditable = true
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        // SwiftUI owns the frame. AppKit growing it independently lets text
        // draw over the next row without changing that row's layout position.
        view.isVerticallyResizable = false
        view.autoresizingMask = [.width]
        view.focusRingType = .none
        view.insertionPointColor = Mocha.nsText
        view.selectedTextAttributes = [.backgroundColor: Mocha.nsSelection, .foregroundColor: Mocha.nsText]
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.setAccessibilityLabel(placeholder.isEmpty ? "Task title" : placeholder)
        view.string = text
        configure(view)
        if let selection = savedSelection {
            view.setSelectedRange(clamped(selection, length: (text as NSString).length))
        }
        return view
    }

    func updateNSView(_ view: PlainTextView, context: Context) {
        view.editorIdentity = identity
        context.coordinator.parent = self
        // Unrelated model notifications must never disturb an active editor.
        if view.string != text && !view.hasMarkedText() {
            let range = view.selectedRange()
            view.localUndo.removeAllActions()
            view.string = text
            view.setSelectedRange(clamped(range, length: (text as NSString).length))
            context.coordinator.synchronizedText = text
        }
        configure(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PlainTextView, context: Context) -> CGSize? {
        let proposedWidth = proposal.width ?? 250
        let width = max(24, proposedWidth.isFinite ? proposedWidth : 250)
        // SwiftUI probes several widths before choosing the frame. Measuring
        // the live container leaves it at the last trial width, even if the
        // editor's frame never changes. Keep those probes away from the editor.
        return CGSize(width: width, height: context.coordinator.measuredHeight(of: nsView, width: width))
    }

    private func configure(_ view: PlainTextView) {
        view.placeholder = placeholder
        view.font = NSFont.systemFont(ofSize: fontSize)
        view.textContainerInset = NSSize(width: 0, height: Mocha.textRowTopInset(fontSize: fontSize))
        view.textColor = secondary || completed ? Mocha.nsSecondary : Mocha.nsText
        view.linkTextAttributes = [.foregroundColor: Mocha.nsBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.submitOnReturn = submitOnReturn
        view.onSubmit = onSubmit
        view.onTitlePointerDown = onTitlePointerDown
        view.onTitleSingleClick = onTitleSingleClick
        view.onTitleFocus = onTitleFocus
        view.deadlineActions = deadlineActions
        // Formatting is presentation only. The binding and shared store contain strings.
        if !view.hasMarkedText(), let storage = view.textStorage {
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.strikethroughStyle, range: full)
            if completed { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: full) }
            storage.removeAttribute(.link, range: full)
            if links, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
                for match in detector.matches(in: view.string, range: full) {
                    if let url = match.url { storage.addAttribute(.link, value: url, range: match.range) }
                }
            }
            storage.endEditing()
        }
        view.needsDisplay = true
    }

    private func clamped(_ range: NSRange, length: Int) -> NSRange {
        let start = min(range.location, length)
        return NSRange(location: start, length: min(range.length, length - start))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextEditor
        var synchronizedText: String
        private let measurementStorage = NSTextStorage()
        private let measurementLayout = NSLayoutManager()
        private let measurementContainer = NSTextContainer()
        static var selections: [String: NSRange] = [:]
        init(_ parent: NativeTextEditor) {
            self.parent = parent
            synchronizedText = parent.text
            super.init()
            measurementContainer.lineFragmentPadding = 0
            measurementLayout.addTextContainer(measurementContainer)
            measurementStorage.addLayoutManager(measurementLayout)
        }
        func measuredHeight(of view: PlainTextView, width: CGFloat) -> CGFloat {
            if let storage = view.textStorage { measurementStorage.setAttributedString(storage) }
            if parent.compactTrailingNewlines {
                let visibleTitle = String(view.string.reversed().drop(while: { $0.isNewline }).reversed())
                let length = (visibleTitle as NSString).length
                if length < measurementStorage.length {
                    measurementStorage.deleteCharacters(in: NSRange(location: length, length: measurementStorage.length - length))
                }
            }
            measurementContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            measurementLayout.ensureLayout(for: measurementContainer)
            // The extra fragment accounts for an empty editor or a trailing
            // newline whose caret occupies a line without any glyphs.
            let used = max(measurementLayout.usedRect(for: measurementContainer).maxY,
                           measurementLayout.extraLineFragmentRect.maxY)
            // NSTextView places glyphs and the caret using its top inset. The
            // extra bottom space keeps optical alignment from shrinking rows.
            let padding = Mocha.textRowTopInset(fontSize: parent.fontSize)
                + Mocha.textRowBottomInset(fontSize: parent.fontSize)
            return max(Mocha.textRowHeight, ceil(used + padding))
        }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? PlainTextView else { return }
            // Do not publish provisional IME text to the persistence layer.
            if !view.hasMarkedText() { publish(view.string) }
            view.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            Self.selections[parent.identity] = view.selectedRange()
        }
        func textDidEndEditing(_ notification: Notification) {
            if let view = notification.object as? NSTextView, !view.hasMarkedText() { publish(view.string) }
            parent.onEndEditing()
        }
        private func publish(_ value: String) {
            guard value != synchronizedText else { return }
            let base = synchronizedText
            synchronizedText = value
            if let onTextChange = parent.onTextChange { onTextChange(value, base) }
            else { parent.text = value }
        }
    }
}

final class PlainTextView: NSTextView {
    var editorIdentity = ""
    let localUndo = UndoManager()
    override var undoManager: UndoManager? { localUndo }
    var placeholder = ""
    var submitOnReturn = false
    var onSubmit: () -> Void = {}
    var onTitlePointerDown: (() -> TitleClickDisposition)?
    var onTitleSingleClick: (() -> Void)?
    var onTitleFocus: (() -> Bool)?
    var deadlineActions: TaskDeadlineActions?
    private var pointerFocus: (eventNumber: Int, timestamp: TimeInterval, disposition: TitleClickDisposition)?
    private var handlingCompositionKey = false

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let deadlineActions else { return menu }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let edit = NSMenuItem(title: deadlineActions.hasDeadline ? "Edit deadline…" : "Set deadline…",
                              action: #selector(editDeadline(_:)), keyEquivalent: "")
        edit.target = self
        edit.representedObject = deadlineActions
        menu.addItem(edit)
        if deadlineActions.hasDeadline {
            let remove = NSMenuItem(title: "Remove deadline", action: #selector(removeDeadline(_:)), keyEquivalent: "")
            remove.target = self
            remove.representedObject = deadlineActions
            menu.addItem(remove)
        }
        return menu
    }

    @objc private func editDeadline(_ sender: Any?) {
        ((sender as? NSMenuItem)?.representedObject as? TaskDeadlineActions)?.edit()
    }
    @objc private func removeDeadline(_ sender: Any?) {
        ((sender as? NSMenuItem)?.representedObject as? TaskDeadlineActions)?.remove()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { pointerFocus = nil }
        super.viewWillMove(toWindow: newWindow)
    }

    override func becomeFirstResponder() -> Bool {
        if let event = NSApp.currentEvent, event.type == .leftMouseDown,
           event.windowNumber == window?.windowNumber,
           bounds.contains(convert(event.locationInWindow, from: nil)),
           let onTitlePointerDown {
            // NSWindow focuses the text view before delivering mouseDown.
            // Preserve whether this event began with an unselected title.
            let disposition = onTitlePointerDown()
            pointerFocus = (event.eventNumber, event.timestamp, disposition)
            guard disposition != .reject else { return false }
        } else {
            guard onTitleFocus?() != false else { return false }
        }
        return super.becomeFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        let focusedForThisEvent = pointerFocus.flatMap { focus in
            focus.eventNumber == event.eventNumber && focus.timestamp == event.timestamp ? focus.disposition : nil
        }
        pointerFocus = nil
        let disposition = focusedForThisEvent ?? onTitlePointerDown?() ?? .editOnly
        guard disposition != .reject else { return }
        super.mouseDown(with: event)
        // NSTextView owns native caret placement, dragging and multi-click
        // selection. The first constituent click can toggle immediately;
        // later clicks in a native multi-click selection do not toggle again.
        guard disposition == .toggleDetails, event.clickCount == 1,
              event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty,
              selectedRange().length == 0, !hasMarkedText(),
              window?.firstResponder === self else { return }
        onTitleSingleClick?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // The rendered container always follows the allocated frame, including
        // widening an already mounted editor while composition is active.
        textContainer?.containerSize = NSSize(width: max(0, newSize.width - 2 * textContainerInset.width),
                                             height: .greatestFiniteMagnitude)
    }

    @objc func undo(_ sender: Any?) { if localUndo.canUndo { localUndo.undo() } }
    @objc func redo(_ sender: Any?) { if localUndo.canRedo { localUndo.redo() } }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(editDeadline(_:)) { return (item as? NSMenuItem)?.representedObject is TaskDeadlineActions }
        if item.action == #selector(removeDeadline(_:)) {
            return ((item as? NSMenuItem)?.representedObject as? TaskDeadlineActions)?.hasDeadline == true
        }
        if item.action == #selector(undo(_:)) { return localUndo.canUndo }
        if item.action == #selector(redo(_:)) { return localUndo.canRedo }
        return super.validateUserInterfaceItem(item)
    }

    override func keyDown(with event: NSEvent) {
        handlingCompositionKey = hasMarkedText()
        defer { handlingCompositionKey = false }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if submitOnReturn && !hasMarkedText() && !handlingCompositionKey && !(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false) {
            onSubmit()
        } else {
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        if hasMarkedText() { super.insertTab(sender) }
        else { window?.selectNextKeyView(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        if hasMarkedText() { super.insertBacktab(sender) }
        else { window?.selectPreviousKeyView(sender) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && !hasMarkedText() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 14),
                .foregroundColor: Mocha.nsSecondary
            ]
            (placeholder as NSString).draw(at: NSPoint(x: 0, y: textContainerInset.height), withAttributes: attributes)
        }
    }
}

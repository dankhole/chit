import AppKit
import SwiftUI

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
        view.textContainerInset = NSSize(width: 0, height: 4)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
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
        let width = max(24, proposal.width ?? 250)
        nsView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        nsView.layoutManager?.ensureLayout(for: nsView.textContainer!)
        let used = nsView.layoutManager?.usedRect(for: nsView.textContainer!).height ?? fontSize + 3
        return CGSize(width: width, height: max(fontSize + 8, ceil(used) + 8))
    }

    private func configure(_ view: PlainTextView) {
        view.placeholder = placeholder
        view.font = NSFont.systemFont(ofSize: fontSize)
        view.textColor = secondary || completed ? Mocha.nsSecondary : Mocha.nsText
        view.linkTextAttributes = [.foregroundColor: Mocha.nsBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.submitOnReturn = submitOnReturn
        view.onSubmit = onSubmit
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
        static var selections: [String: NSRange] = [:]
        init(_ parent: NativeTextEditor) { self.parent = parent; synchronizedText = parent.text }
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
    private var handlingCompositionKey = false

    @objc func undo(_ sender: Any?) { if localUndo.canUndo { localUndo.undo() } }
    @objc func redo(_ sender: Any?) { if localUndo.canRedo { localUndo.redo() } }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
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

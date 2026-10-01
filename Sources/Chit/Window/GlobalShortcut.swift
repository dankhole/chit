import AppKit
import Carbon

struct ShortcutValue {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    static let standard = ShortcutValue(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(optionKey), label: "⌥W")
}

/// Carbon hot keys are system-wide without monitoring keystrokes or requesting Accessibility access.
@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var action: (() -> Void)?

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { shortcut.action?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    func register(_ value: ShortcutValue?) throws {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        guard let value else { return }
        let identifier = EventHotKeyID(signature: 0x544F544F, id: 1)
        let result = RegisterEventHotKey(value.keyCode, value.modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
        guard result == noErr else {
            throw NSError(domain: "Chit.Shortcut", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "That shortcut is unavailable. Choose a different combination."])
        }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
    }
}

@MainActor
final class ShortcutRecorder: NSWindowController {
    private let capture = ShortcutCaptureView(frame: .zero)
    private let message = NSTextField(wrappingLabelWithString: "Press a key with Control, Option, or Command. Escape cancels.")
    var onSave: ((ShortcutValue?) -> String?)?
    var onClose: (() -> Void)?

    init(current: ShortcutValue?) {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 176), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Global Shortcut"
        window.appearance = NSAppearance(named: .darkAqua)
        super.init(window: window)
        capture.value = current
        capture.setAccessibilityElement(true)
        capture.setAccessibilityRole(.button)
        capture.setAccessibilityLabel("Global keyboard shortcut")
        capture.setAccessibilityHelp("Press a key with Control, Option, or Command to choose a shortcut.")
        capture.onCancel = { [weak self] in self?.dismiss() }
        capture.onChange = { [weak self] in self?.message.stringValue = "Use this shortcut to show, focus, or hide Chit." }
        message.font = .systemFont(ofSize: 12)
        let disable = NSButton(title: "Disable", target: self, action: #selector(disableShortcut))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save", target: self, action: #selector(saveShortcut))
        save.keyEquivalent = "\r"
        let buttons = NSStackView(views: [disable, NSView(), cancel, save])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [message, capture, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 15
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            capture.widthAnchor.constraint(equalTo: stack.widthAnchor), capture.heightAnchor.constraint(equalToConstant: 42),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(on parent: NSWindow) {
        guard let window else { return }
        parent.beginSheet(window)
        window.makeFirstResponder(capture)
    }

    @objc private func saveShortcut() { commit(capture.value) }
    @objc private func disableShortcut() { commit(nil) }
    @objc private func cancel() { dismiss() }

    private func commit(_ value: ShortcutValue?) {
        if let error = onSave?(value) { message.stringValue = error; return }
        dismiss()
    }

    private func dismiss() {
        if let window, let parent = window.sheetParent { parent.endSheet(window) }
        window?.orderOut(nil)
        onClose?()
    }
}

@MainActor
private final class ShortcutCaptureView: NSView {
    var value: ShortcutValue? { didSet { needsDisplay = true; setAccessibilityValue(value?.label ?? "Disabled") } }
    var onCancel: (() -> Void)?
    var onChange: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              !event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        path.fill()
        NSColor.keyboardFocusIndicatorColor.setStroke()
        path.lineWidth = 2
        path.stroke()
        let text = value?.label ?? "Type shortcut…"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.labelColor]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { NSSound.beep(); return }
        var modifiers: UInt32 = 0
        var label = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
        let special: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        label += special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        value = ShortcutValue(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label)
        onChange?()
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TodoCore

/// Native file panels stay at the presentation boundary; storage never chooses a path.
@MainActor
enum ListActions {
    enum Destination {
        case save(URL)
        case open(URL)
    }

    static let focusEntry = Notification.Name("ChitFocusListEntry")

    static func open(model: AppModel, groupID: String? = nil) {
        chooseExisting(title: "Open List", prompt: "Open") { url in
            openLinked(at: url, model: model, groupID: groupID) { _ in }
        }
    }

    static func openLinked(at url: URL, model: AppModel, groupID: String? = nil,
                           completion: @escaping (Bool) -> Void) {
        if model.openList(at: url, groupID: groupID) { completion(true); return }
        guard let conflict = model.listIdentityConflict else { completion(false); return }
        let alert = NSAlert()
        alert.messageText = "This list is already linked."
        alert.informativeText = "Current file:\n\(conflict.existingURL.path)\n\nSelected file:\n\(conflict.candidateURL.path)\n\nRelink the existing tab to the selected file? Its tasks will come from that file."
        alert.addButton(withTitle: "Relink List")
        alert.addButton(withTitle: "Cancel")
        present(alert) { response in
            guard response == .alertFirstButtonReturn else {
                model.listIdentityConflict = nil
                if model.errorMessage == conflict.localizedDescription { model.errorMessage = nil }
                completion(false)
                return
            }
            let succeeded = model.relinkList(id: conflict.listID, to: conflict.candidateURL)
            if succeeded { model.selectProject(conflict.listID) }
            completion(succeeded)
        }
    }

    static func locate(_ project: Project, model: AppModel) {
        chooseExisting(title: "Locate \(project.name)", prompt: "Locate",
            directory: model.location(for: project.id)?.url.deletingLastPathComponent()) { url in
            _ = model.relinkList(id: project.id, to: url)
        }
    }

    static func move(_ project: Project, model: AppModel) {
        guard let location = model.location(for: project.id) else { return }
        chooseDestination(title: "Move List", prompt: "Move", suggestedName: location.url.lastPathComponent,
            directory: location.url.deletingLastPathComponent(), allowOpenExisting: false) { result in
            if case .save(let url) = result { _ = model.moveList(id: project.id, to: url) }
        }
    }

    static func chooseDestination(title: String = "Save List", prompt: String = "Choose",
                                  suggestedName: String = "todo.yaml", directory: URL? = nil,
                                  allowOpenExisting: Bool = true,
                                  completion: @escaping (Destination) -> Void) {
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = prompt
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = directory
        panel.canCreateDirectories = true
        panel.allowedContentTypes = yamlTypes
        panel.allowsOtherFileTypes = false
        present(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            guard FileManager.default.fileExists(atPath: url.path) else { completion(.save(url)); return }
            // Even a confirmed native Replace must never turn list creation into an overwrite.
            let alert = NSAlert()
            alert.messageText = "A file already exists here."
            alert.informativeText = allowOpenExisting
                ? "Open this file as a list, or choose a different filename."
                : "Choose a different filename to move this list. The existing file will be kept."
            if allowOpenExisting { alert.addButton(withTitle: "Open Existing") }
            alert.addButton(withTitle: "Choose Another Name")
            alert.addButton(withTitle: "Cancel")
            present(alert) { response in
                if allowOpenExisting && response == .alertFirstButtonReturn { completion(.open(url)); return }
                let chooseResponse: NSApplication.ModalResponse = allowOpenExisting ? .alertSecondButtonReturn : .alertFirstButtonReturn
                if response == chooseResponse {
                    chooseDestination(title: title, prompt: prompt, suggestedName: url.lastPathComponent,
                        directory: url.deletingLastPathComponent(), allowOpenExisting: allowOpenExisting,
                        completion: completion)
                }
            }
        }
    }

    static func focusNewList(_ id: String) {
        // Wait for the creation sheet to leave and the selected list's editors to appear.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: focusEntry, object: id)
        }
    }

    static func focusEditor(identity: String) {
        func find(in view: NSView) -> PlainTextView? {
            if let editor = view as? PlainTextView, editor.editorIdentity == identity { return editor }
            for child in view.subviews { if let match = find(in: child) { return match } }
            return nil
        }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let content = window.contentView, let editor = find(in: content) else { return }
        window.makeFirstResponder(editor)
    }

    /// Called only by the explicit isolated snapshot harness. Uses the shipping form.
    static func captureNewListForm(model: AppModel, at destination: URL) async throws {
        let form = NewListForm(model: model, groupID: nil, initialName: "Website",
            initialDestination: URL(fileURLWithPath: "/Users/example/Projects/Website/todo.yaml"), onFinish: {})
        let host = NSHostingView(rootView: form.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 210),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.center()
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(nanoseconds: 200_000_000)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "ChitPreview", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not allocate New List preview."])
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ChitPreview", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode New List preview."])
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: destination, options: .atomic)
        print("Snapshot saved: \(destination.path)")
    }

    private static var yamlTypes: [UTType] {
        [UTType(filenameExtension: "yaml"), UTType(filenameExtension: "yml")].compactMap { $0 }
    }

    private static func chooseExisting(title: String, prompt: String, directory: URL? = nil,
                                       completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.directoryURL = directory
        panel.allowedContentTypes = yamlTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        present(panel) { response in
            if response == .OK, let url = panel.url { completion(url) }
        }
    }

    private static var presentationWindow: NSWindow? {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        if window is NSSavePanel { return window?.sheetParent ?? NSApp.mainWindow }
        return window
    }

    private static func present(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = presentationWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    private static func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = presentationWindow { alert.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(alert.runModal()) }
    }
}

struct NewListForm: View {
    @ObservedObject var model: AppModel
    let groupID: String?
    let onFinish: () -> Void
    @State private var name = ""
    @State private var destination: URL?
    @State private var failure: String?
    @State private var committed = false
    @FocusState private var nameFocused: Bool

    init(model: AppModel, groupID: String?, initialName: String = "", initialDestination: URL? = nil,
         onFinish: @escaping () -> Void) {
        self.model = model
        self.groupID = groupID
        self.onFinish = onFinish
        _name = State(initialValue: initialName)
        _destination = State(initialValue: initialDestination)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New List").font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Name").frame(width: 48, alignment: .leading)
                    TextField("List name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit(create)
                        .accessibilityLabel("List name")
                }
                HStack(spacing: 10) {
                    Text("Save in").frame(width: 48, alignment: .leading)
                    Menu {
                        Button("In app") { destination = nil; failure = nil }
                        Button("Choose folder…", action: chooseFolder)
                    } label: {
                        Text(destination == nil ? "In app" : "Chosen folder")
                    }
                    .menuStyle(.borderedButton)
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                if let destination {
                    Text(destination.path)
                        .font(.system(size: 11))
                        .foregroundStyle(Mocha.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 58)
                        .accessibilityLabel("Save destination: \(destination.path)")
                }
            }
            if let failure {
                Text(failure).font(.system(size: 11)).foregroundStyle(Mocha.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            HStack {
                Button("Cancel", action: onFinish).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Mocha.text)
        .tint(Mocha.blue)
        .padding(16)
        .frame(width: 320)
        .preferredColorScheme(.dark)
        .onAppear { nameFocused = true }
    }

    private func chooseFolder() {
        ListActions.chooseDestination(directory: destination?.deletingLastPathComponent()) { result in
            switch result {
            case .save(let url): destination = url; failure = nil
            case .open(let url):
                ListActions.openLinked(at: url, model: model, groupID: groupID) { succeeded in
                    if succeeded { onFinish() }
                    else { failure = model.errorMessage }
                }
            }
        }
    }

    private func create() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !committed else { return }
        committed = true
        if model.createList(name: clean, at: destination, groupID: groupID) {
            let id = model.selectedProjectID
            onFinish()
            ListActions.focusNewList(id)
        } else { committed = false; failure = model.errorMessage }
    }
}

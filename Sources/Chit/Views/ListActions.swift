import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TodoCore

/// Native file panels stay at the presentation boundary; storage never chooses a path.
@MainActor
enum ListActions {
    enum Destination {
        case save(URL, tags: [String])
        case open(URL)
    }

    static let focusEntry = Notification.Name("ChitFocusListEntry")

    static func createInFolder(model: AppModel, groupID: String? = nil, startingDirectory: URL? = nil) {
        guard canBeginAction() else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder for Your List"
        panel.prompt = "Choose Folder"
        panel.directoryURL = startingDirectory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        present(panel) { response in
            guard response == .OK, let directory = panel.url else { return }
            chooseDestination(title: "New List", prompt: "Create", directory: directory,
                              showsTagField: true) { destination in
                switch destination {
                case .save(let url, let tags):
                    let name = url.deletingPathExtension().lastPathComponent
                    guard model.createList(name: name, at: url, groupID: groupID) else { return }
                    // The native panel collects tags; the app applies them only after
                    // the store has exclusively created the new file.
                    if !tags.isEmpty {
                        do {
                            try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
                        } catch {
                            model.errorMessage = "The list was created, but its Finder tags could not be saved: \(error.localizedDescription)"
                        }
                    }
                    focusNewList(model.selectedProjectID)
                case .open(let url):
                    openLinked(at: url, model: model, groupID: groupID) { succeeded in
                        if succeeded { focusNewList(model.selectedProjectID) }
                    }
                }
            }
        }
    }

    static func open(model: AppModel, groupID: String? = nil) {
        guard canBeginAction() else { return }
        chooseExisting(title: "Open List", prompt: "Open") { url in
            openLinked(at: url, model: model, groupID: groupID) { _ in }
        }
    }

    static func chooseCatalogRecoveryFiles(model: AppModel) {
        guard !model.isStoreAvailable, model.isCatalogRecoveryPresented, canBeginAction() else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose List Files"
        panel.prompt = "Add to Review"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = yamlTypes
        panel.allowsOtherFileTypes = false
        present(panel) { response in
            guard response == .OK else { return }
            _ = model.refreshCatalogRecovery(additionalURLs: panel.urls)
        }
    }

    static func openLinked(at url: URL, model: AppModel, groupID: String? = nil,
                           completion: @escaping (Bool) -> Void) {
        guard canBeginAction() else { completion(false); return }
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
        guard canBeginAction() else { return }
        chooseExisting(title: "Locate \(project.name)", prompt: "Locate",
            directory: model.location(for: project.id)?.url.deletingLastPathComponent()) { url in
            _ = model.relinkList(id: project.id, to: url)
        }
    }

    static func move(_ project: Project, model: AppModel) {
        guard canBeginAction() else { return }
        guard let location = model.location(for: project.id) else { return }
        chooseDestination(title: "Move List", prompt: "Move", suggestedName: location.url.lastPathComponent,
            directory: location.url.deletingLastPathComponent(), allowOpenExisting: false) { result in
            if case .save(let url, _) = result { _ = model.moveList(id: project.id, to: url) }
        }
    }

    static func delete(_ project: Project, model: AppModel) {
        guard canBeginAction() else { return }
        guard let location = model.location(for: project.id),
              model.prepareListDeletion(id: project.id, expectedURL: location.url) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \u{201c}\(project.name)\u{201d}?"
        alert.informativeText = "This list's file and all its saved tasks will move to macOS Trash:\n\n\(location.url.path)"
        if !location.isManaged {
            alert.informativeText += "\n\nThis is an external file. It will also be removed from its folder or repository."
        }
        alert.informativeText += "\n\nYou can restore the file from Trash and open the list again."
        if model.hasRetainedDrafts(listID: project.id) {
            alert.informativeText += " Unsubmitted entries will stay in Chit and return when you reopen this list."
        }
        // Return and Escape cancel; the destructive action requires an explicit choice.
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Move to Trash")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = ""
        alert.buttons[1].hasDestructiveAction = true
        present(alert) { response in
            guard response == .alertSecondButtonReturn else { return }
            _ = model.deleteList(id: project.id, expectedURL: location.url)
        }
    }

    static func chooseDestination(title: String = "Save List", prompt: String = "Choose",
                                  suggestedName: String = "todo.yaml", directory: URL? = nil,
                                  allowOpenExisting: Bool = true,
                                  showsTagField: Bool = false, initialTags: [String] = [],
                                  completion: @escaping (Destination) -> Void) {
        guard canBeginAction() else { return }
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = prompt
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = directory
        panel.canCreateDirectories = true
        panel.allowedContentTypes = yamlTypes
        panel.allowsOtherFileTypes = false
        panel.showsTagField = showsTagField
        panel.tagNames = initialTags
        present(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            let tags = panel.tagNames ?? []
            guard FileManager.default.fileExists(atPath: url.path) else { completion(.save(url, tags: tags)); return }
            // Even a confirmed native Replace must never turn list creation into an overwrite.
            let alert = NSAlert()
            alert.messageText = "A file already exists here."
            alert.informativeText = allowOpenExisting
                ? "Open this file as a list, or choose a different filename."
                : "Choose a different filename. The existing file will be kept."
            if allowOpenExisting { alert.addButton(withTitle: "Open Existing") }
            alert.addButton(withTitle: "Choose Another Name")
            alert.addButton(withTitle: "Cancel")
            present(alert) { response in
                if allowOpenExisting && response == .alertFirstButtonReturn { completion(.open(url)); return }
                let chooseResponse: NSApplication.ModalResponse = allowOpenExisting ? .alertSecondButtonReturn : .alertFirstButtonReturn
                if response == chooseResponse {
                    chooseDestination(title: title, prompt: prompt, suggestedName: url.lastPathComponent,
                        directory: url.deletingLastPathComponent(), allowOpenExisting: allowOpenExisting,
                        showsTagField: showsTagField, initialTags: tags,
                        completion: completion)
                }
            }
        }
    }

    static func focusNewList(_ id: String) {
        // Wait for the native picker to leave and the selected list's editors to appear.
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
        let form = NewListForm(model: model, groupID: nil, initialName: "Website", onFinish: {})
        let host = NSHostingView(rootView: form.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 150),
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
        try LabEnvironment.requireAllowed(destination)
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
        [(NSApp.delegate as? AppDelegate)?.panel, NSApp.mainWindow, NSApp.keyWindow]
            .compactMap { $0 }
            .first { $0.isVisible && !($0 is NSSavePanel) && $0.sheetParent == nil }
    }

    private static func present(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        FilePanelPresenter.present(panel, relativeTo: presentationWindow, completion: completion)
    }

    private static func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard canBeginAction() else { completion(.abort); return }
        if let window = presentationWindow {
            guard window.attachedSheet == nil else { completion(.abort); return }
            alert.beginSheetModal(for: window, completionHandler: completion)
        }
        else { completion(alert.runModal()) }
    }

    private static func canBeginAction() -> Bool {
        guard !FilePanelPresenter.isPresenting else {
            _ = FilePanelPresenter.focusActivePanel()
            return false
        }
        return presentationWindow?.attachedSheet == nil
    }
}

struct NewListDestinationOptions: View {
    let model: AppModel
    var groupID: String? = nil
    let onInChit: () -> Void

    var body: some View {
        Button("In Chit", action: onInChit)
        Button("Choose Folder…") { ListActions.createInFolder(model: model, groupID: groupID) }
    }
}

struct NewListForm: View {
    @ObservedObject var model: AppModel
    let groupID: String?
    let onFinish: () -> Void
    @State private var name = ""
    @State private var failure: String?
    @State private var committed = false
    @FocusState private var nameFocused: Bool

    init(model: AppModel, groupID: String?, initialName: String = "",
         onFinish: @escaping () -> Void) {
        self.model = model
        self.groupID = groupID
        self.onFinish = onFinish
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New List").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 10) {
                Text("Name").frame(width: 40, alignment: .leading)
                TextField("List name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(create)
                    .accessibilityLabel("List name")
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

    private func create() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !committed else { return }
        committed = true
        if model.createList(name: clean, groupID: groupID) {
            let id = model.selectedProjectID
            onFinish()
            ListActions.focusNewList(id)
        } else { committed = false; failure = model.errorMessage }
    }
}

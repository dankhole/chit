import AppKit
import TodoCore

/// Explicit isolated-store regression check; never runs during ordinary app use.
@MainActor
enum NativeFilePanelHarness {
    static func run(delegate: AppDelegate) async throws {
        progress("starting")
        guard delegate.model.isStoreAvailable else {
            throw failure("The isolated test catalog must load before checking native dialogs.")
        }
        guard let parent = delegate.panel, let screen = parent.screen ?? NSScreen.main else {
            throw failure("No screen is available for the file-panel regression check.")
        }
        let base = LabEnvironment.root ?? ProcessInfo.processInfo.environment["CHIT_FILE_STATE_DIRECTORY"]
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("picker-folder", isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        let directory = base
            .appendingPathComponent("Chit.FilePanel.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalFrame = parent.frame
        defer {
            FilePanelPresenter.cancelActivePanel()
            parent.setFrame(originalFrame, display: true)
            delegate.showPanel()
            try? FileManager.default.removeItem(at: directory)
        }
        let visible = screen.visibleFrame
        parent.setFrame(NSRect(x: visible.maxX - 320, y: visible.minY,
                               width: 320, height: 240), display: true)
        delegate.showPanel()

        let folder = NSOpenPanel()
        folder.canChooseDirectories = true
        folder.canChooseFiles = false
        folder.directoryURL = directory
        var cancelResponse: NSApplication.ModalResponse?
        FilePanelPresenter.present(folder, relativeTo: parent) { cancelResponse = $0 }
        try await ready(folder, parent: parent, visible: visible)
        let initialFrame = folder.frame
        delegate.showPanel()
        try check(FilePanelPresenter.activePanel === folder,
                  "Showing Chit replaced its active native picker.")
        var duplicateResponse: NSApplication.ModalResponse?
        FilePanelPresenter.present(NSOpenPanel(), relativeTo: parent) { duplicateResponse = $0 }
        try check(duplicateResponse == .cancel && FilePanelPresenter.activePanel === folder,
                  "A repeated picker request created another native dialog.")
        // Later frame changes must not trigger another centering pass.
        folder.setFrameOrigin(NSPoint(x: initialFrame.minX + 12, y: initialFrame.minY + 12))
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(folder.frame.origin != initialFrame.origin,
                  "The native picker was recentered after moving it.")
        folder.cancel(nil)
        try await wait("Native Cancel did not finish the picker.") {
            cancelResponse == .cancel && FilePanelPresenter.activePanel == nil && !folder.isVisible
        }
        progress("native Cancel passed")

        // Exercise both production dialogs without creating a file. The remote
        // native-panel proxy does not implement programmatic ok(_:), so choosing
        // a folder and accepting the save dialog remain hands-on checks.
        ListActions.createInFolder(model: delegate.model, startingDirectory: directory)
        guard let productionFolder = FilePanelPresenter.activePanel as? NSOpenPanel else {
            throw failure("Choose Folder did not present a native folder picker.")
        }
        try await ready(productionFolder, parent: parent, visible: visible)
        productionFolder.cancel(nil)
        try await wait("Cancelling the production folder picker did not clean up.") {
            FilePanelPresenter.activePanel == nil && !productionFolder.isVisible
        }
        progress("folder cancellation passed")
        var saved = false
        ListActions.chooseDestination(directory: directory, showsTagField: true) { _ in saved = true }
        guard let save = FilePanelPresenter.activePanel else {
            throw failure("The production save panel did not appear.")
        }
        try await ready(save, parent: parent, visible: visible)
        try check(save.directoryURL?.resolvingSymlinksInPath().standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL,
                  "The save panel did not start in the chosen temporary folder.")
        save.cancel(nil)
        try await wait("Cancelling the save panel did not clean up.") {
            FilePanelPresenter.activePanel == nil && !save.isVisible
        }
        try check(!saved, "Cancelling the save panel unexpectedly accepted a destination.")
        try check(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty,
                  "Cancelling the save panel unexpectedly created a file.")
        progress("save cancellation passed")

        let hidden = NSSavePanel()
        hidden.directoryURL = directory
        var hideResponse: NSApplication.ModalResponse?
        FilePanelPresenter.present(hidden, relativeTo: parent) { hideResponse = $0 }
        try await ready(hidden, parent: parent, visible: visible)
        progress("checking Hide")
        try check(delegate.hidePanel() && !parent.isVisible,
                  "Hide Chit did not dismiss the app while its picker was open.")
        try await wait("Hide Chit left a native picker alive.") {
            hideResponse == .cancel && FilePanelPresenter.activePanel == nil && !hidden.isVisible
        }
        delegate.showPanel()
        progress("Hide passed; checking Quit")

        let quitting = NSOpenPanel()
        quitting.directoryURL = directory
        var quitResponse: NSApplication.ModalResponse?
        FilePanelPresenter.present(quitting, relativeTo: parent) { quitResponse = $0 }
        try await ready(quitting, parent: parent, visible: visible)
        try check(delegate.applicationShouldTerminate(NSApp) == .terminateNow,
                  "A clean app could not quit with its native picker open.")
        try await wait("Quit cleanup left a native picker alive.") {
            quitResponse == .cancel && FilePanelPresenter.activePanel == nil && !quitting.isVisible
        }
        print("Chit file-panel regression passed: standalone native picker at screen edge, frame movement, duplicate/show focus, folder and save dialogs, Cancel, Hide and Quit cleanup.")
    }

    private static func ready(_ panel: NSSavePanel, parent: NSWindow, visible: NSRect) async throws {
        // Let AppKit's remote panel service complete a presentation/layout turn.
        try await Task.sleep(nanoseconds: 100_000_000)
        try await wait("The native file panel did not become visible and reachable.") {
            panel.isVisible && panel.frame.width > 100 && panel.frame.height > 80 &&
                visible.insetBy(dx: -1, dy: -1).contains(panel.frame)
        }
        // Stock begin/runModal panels report isMovable=false through the remote
        // proxy too; that getter cannot establish native title-bar drag behavior.
        try check(panel.sheetParent == nil && parent.attachedSheet == nil,
                  "The native picker is still attached as a sheet.")
    }

    private static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            if Date() >= deadline { throw failure(message) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw failure(message) }
    }

    private static func progress(_ message: String) {
        print("File-panel check: \(message).")
        fflush(stdout)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Chit.FilePanelHarness", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

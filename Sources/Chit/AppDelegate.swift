import AppKit
import SwiftUI
import TodoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private(set) var model: AppModel!
    private(set) var panel: TodoPanel!
    private var statusItem: NSStatusItem?
    private var settingsPopover: NSPopover?
    private var shortcut: GlobalShortcut?
    private var shortcutValue: ShortcutValue?
    private var recorder: ShortcutRecorder?
    private var previousApplication: NSRunningApplication?
    // The retained local.dcole.TotTodo bundle ID preserves the existing preferences domain.
    private var preferences = UserDefaults.standard
    private var screenObserver: NSObjectProtocol?
    private var isHarness = false
    private var isolatedStorePath: String?
    private var snapshotPath: String?
    private var snapshotExpandedTask: String?
    private var snapshotSize: NSSize?
    private var snapshotCollapsedGroups: [String] = []
    private var snapshotSolid = false
    private var snapshotContrast = false
    private var snapshotBackdrop = false
    private var snapshotContainedBackdrop = false
    private var snapshotCompleted = false
    private var snapshotNewList = false
    private var snapshotRecovery = false
    private var previewBackdrop: NSWindow?
    private var smokeTest = false
    private var filePanelTest = false
    private var labResultPath: String?
    private var labVisibilityOverride: Bool?
    private var applicationName: String { LabEnvironment.isEnabled ? "Chit Lab" : "Chit" }
    private var needsVisibleHarness: Bool { smokeTest || filePanelTest || snapshotBackdrop || snapshotNewList }
    private var showsInterface: Bool { !LabEnvironment.isEnabled || labVisibilityOverride == true || needsVisibleHarness }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil else { return }
        do { try parseArguments() } catch { exitHarness(error.localizedDescription, code: 64) }
        isHarness = smokeTest || filePanelTest || snapshotPath != nil
        NSApp.setActivationPolicy(showsInterface ? .accessory : .prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        if let suite = LabEnvironment.preferencesSuite {
            preferences = UserDefaults(suiteName: suite)!
            model = AppModel(store: TodoStore(url: URL(fileURLWithPath: isolatedStorePath!)), preferences: preferences)
        } else if let isolatedStorePath {
            // Test and preview launches never change the user's navigation/window preferences.
            // Keep legacy suites so existing isolated-store settings and drafts remain available.
            let suite = "TotTodo.Isolated.\(isolatedStorePath.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) })"
            preferences = UserDefaults(suiteName: suite)!
            model = AppModel(store: TodoStore(url: URL(fileURLWithPath: isolatedStorePath)), preferences: preferences)
        } else {
            model = AppModel()
        }
        if let taskID = snapshotExpandedTask {
            guard let project = model.workspace.projects.first(where: { $0.tasks.contains(where: { $0.id == taskID }) }) else {
                exitHarness("Snapshot task ID was not found in the isolated store.", code: 64)
            }
            model.selectProject(project.id)
            if model.expandedTaskID != taskID { model.toggleDetails(taskID: taskID) }
        }
        if snapshotPath != nil {
            if snapshotRecovery { _ = model.beginCatalogRecovery() }
            let showCompleted = snapshotCompleted || model.selectedProject?.tasks.contains(where: { $0.id == snapshotExpandedTask && $0.completed }) == true
            if showCompleted != model.isCompletedExpanded(projectID: model.selectedProjectID) {
                model.toggleCompleted(projectID: model.selectedProjectID)
            }
            for groupID in model.collapsedGroupIDs { model.toggleGroup(groupID) }
            for groupID in snapshotCollapsedGroups {
                guard model.workspace.groups.contains(where: { $0.id == groupID }) else { exitHarness("Snapshot group ID was not found.", code: 64) }
                model.toggleGroup(groupID)
            }
        }
        makePanel()
        if snapshotPath != nil { panel.setContentSize(snapshotSize ?? NSSize(width: 424, height: 350)); clampWindow() }
        if snapshotContainedBackdrop { NativePreview.containBackdrop(in: panel) }
        makeMainMenu()
        if showsInterface {
            makeStatusItem()
            showPanel()
        }
        if snapshotBackdrop { previewBackdrop = NativePreview.makeBackdrop(behind: panel) }
        if !isHarness && !LabEnvironment.isEnabled { configureShortcut() }
        if isHarness {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.runHarness() }
        }
    }

    private func parseArguments() throws {
        let arguments = try LabEnvironment.configure(arguments: Array(CommandLine.arguments.dropFirst()))
        if LabEnvironment.isEnabled { isolatedStorePath = TodoStore.defaultURL.path }
        var index = 0
        while index < arguments.count {
            let value = arguments[index]
            switch value {
            case "--store", "--snapshot", "--snapshot-expand", "--snapshot-size", "--snapshot-collapse", "--lab-result":
                index += 1
                guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                    throw harnessError("\(value) requires a path.")
                }
                let path = (arguments[index] as NSString).expandingTildeInPath
                if value == "--store" { isolatedStorePath = path }
                else if value == "--lab-result" {
                    guard LabEnvironment.isEnabled else { throw harnessError("--lab-result is available only in Chit Lab.") }
                    try LabEnvironment.requireAllowed(URL(fileURLWithPath: path))
                    labResultPath = path
                }
                else if value == "--snapshot-expand" { snapshotExpandedTask = arguments[index] }
                else if value == "--snapshot-collapse" { snapshotCollapsedGroups.append(arguments[index]) }
                else if value == "--snapshot-size" {
                    let parts = arguments[index].split(separator: "x")
                    guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]), width >= 320, height >= 240, width.isFinite, height.isFinite else {
                        throw harnessError("--snapshot-size requires WIDTHxHEIGHT, at least 320x240 points.")
                    }
                    snapshotSize = NSSize(width: width, height: height)
                }
                else { snapshotPath = path }
            case "--smoke-test": smokeTest = true
            case "--file-panel-test": filePanelTest = true
            case "--lab-hidden", "--lab-visible":
                guard LabEnvironment.isEnabled else { throw harnessError("\(value) is available only in Chit Lab.") }
                let visible = value == "--lab-visible"
                if let previous = labVisibilityOverride, previous != visible {
                    throw harnessError("Choose either --lab-hidden or --lab-visible.")
                }
                labVisibilityOverride = visible
            case "--snapshot-solid": snapshotSolid = true
            case "--snapshot-contrast": snapshotContrast = true
            case "--snapshot-backdrop": snapshotBackdrop = true
            case "--snapshot-contained-backdrop": snapshotContainedBackdrop = true; snapshotBackdrop = true
            case "--snapshot-completed": snapshotCompleted = true
            case "--snapshot-new-list": snapshotNewList = true
            case "--snapshot-recovery": snapshotRecovery = true
            default: break // AppKit and test runners may pass their own launch arguments.
            }
            index += 1
        }
        if let isolatedStorePath { try LabEnvironment.requireAllowed(URL(fileURLWithPath: isolatedStorePath)) }
        if let snapshotPath { try LabEnvironment.requireAllowed(URL(fileURLWithPath: snapshotPath)) }
        if labVisibilityOverride == false && needsVisibleHarness {
            throw harnessError("This native check requires visible windows; omit --lab-hidden. Ordinary snapshots support hidden rendering.")
        }
        if labResultPath != nil && !(smokeTest || filePanelTest || snapshotPath != nil) {
            throw harnessError("--lab-result requires a snapshot, smoke test, or file-panel test.")
        }
        if (smokeTest || filePanelTest || snapshotPath != nil) && isolatedStorePath == nil {
            throw harnessError("--smoke-test, --file-panel-test and --snapshot require --store with an isolated workspace path.")
        }
        if (snapshotExpandedTask != nil || snapshotSize != nil || !snapshotCollapsedGroups.isEmpty || snapshotSolid || snapshotContrast || snapshotBackdrop || snapshotCompleted || snapshotNewList || snapshotRecovery) && snapshotPath == nil {
            throw harnessError("Snapshot layout flags require --snapshot and an isolated --store.")
        }
    }

    private func makePanel() {
        panel = TodoPanel(contentRect: NSRect(x: 0, y: 0, width: 424, height: 350), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = applicationName
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 1
        panel.hasShadow = false
        panel.minSize = NSSize(width: 320, height: 240)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        let surface = PanelSurface(model: model)
        if snapshotSolid || snapshotContrast {
            surface.updateAccessibilityAppearance(reduceTransparency: snapshotSolid, increaseContrast: snapshotContrast)
        }
        panel.contentView = surface
        panel.delegate = self
        panel.dismissPanel = { [weak self] in self?.hidePanel() }
        if let saved = preferences.string(forKey: "window.frame") {
            panel.setFrame(WindowGeometry.reachable(NSRectFromString(saved), screens: NSScreen.screens.map(\.visibleFrame)), display: false)
        } else { panel.center() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clampWindow() }
        }
    }

    private func clampWindow() {
        panel.setFrame(WindowGeometry.reachable(panel.frame, screens: NSScreen.screens.map(\.visibleFrame)), display: true)
        FilePanelPresenter.keepActivePanelOnScreen()
    }

    private func makeMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: applicationName)
        appMenu.addItem(item("Settings…", action: #selector(showSettings), key: ","))
        if !LabEnvironment.isEnabled { appMenu.addItem(item("Global Shortcut…", action: #selector(editShortcut))) }
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide \(applicationName)", action: #selector(hideFromMenu), key: "h"))
        appMenu.addItem(item("Quit \(applicationName)", action: #selector(quit), key: "q"))
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let file = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("Close Window", action: #selector(closeFromMenu), key: "w"))
        file.submenu = fileMenu
        menu.addItem(file)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        // First-responder dispatch preserves native text editing and IME behavior.
        for (title, selector, key) in [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            editMenu.addItem(entry)
        }
        edit.submenu = editMenu
        menu.addItem(edit)
        NSApp.mainMenu = menu
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let value = NSMenuItem(title: title, action: action, keyEquivalent: key)
        value.target = self
        return value
    }

    private func makeStatusItem() {
        let status = NSStatusBar.system.statusItem(withLength: LabEnvironment.isEnabled ? NSStatusItem.variableLength : NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: applicationName)
        if LabEnvironment.isEnabled { status.button?.title = " Lab" }
        status.button?.toolTip = "\(applicationName) — click to show or hide; right-click for settings"
        status.button?.target = self
        status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = status
    }

    @objc private func statusClicked() {
        settingsPopover?.performClose(nil)
        if NSApp.currentEvent?.type == .rightMouseUp, let statusItem {
            let menu = NSMenu()
            menu.addItem(item(panel.isVisible ? "Hide \(applicationName)" : "Show \(applicationName)", action: #selector(toggleFromMenu)))
            menu.addItem(item("Settings…", action: #selector(showSettings)))
            if !LabEnvironment.isEnabled { menu.addItem(item("Global Shortcut…", action: #selector(editShortcut))) }
            menu.addItem(.separator())
            menu.addItem(item("Quit \(applicationName)", action: #selector(quit)))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { toggleFromMenu() }
    }

    @objc private func showSettings() {
        // Open after the status menu finishes tracking so it cannot dismiss
        // the new popover as the menu closes.
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem?.button else { return }
            let popover: NSPopover
            if let existing = self.settingsPopover {
                popover = existing
            } else {
                popover = NSPopover()
                popover.behavior = .transient
                popover.appearance = NSAppearance(named: .darkAqua)
                let controller = NSHostingController(rootView: AppearanceSettingsView(model: self.model))
                popover.contentViewController = controller
                popover.contentSize = controller.view.fittingSize
                self.settingsPopover = popover
            }
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func toggleFromMenu() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }
    @objc private func hideFromMenu() { hidePanel() }
    @objc private func closeFromMenu() {
        if FilePanelPresenter.cancelActivePanel() { return }
        hidePanel()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func toggleFromShortcut() {
        if FilePanelPresenter.focusActivePanel() { return }
        if panel.isVisible && panel.isKeyWindow && NSApp.isActive { hidePanel() } else { showPanel() }
    }

    func showPanel() {
        guard showsInterface else { return }
        if FilePanelPresenter.focusActivePanel() { return }
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = front
        }
        model.refresh()
        clampWindow()
        if isHarness && !smokeTest && !filePanelTest {
            // Appearance snapshots must not steal keystrokes from the user's app.
            panel.orderFrontRegardless()
            return
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult
    func hidePanel() -> Bool {
        guard panel.attachedSheet == nil, compositionAllowsDismissal(), model.flushEditsForDismissal() else { return false }
        let restoreFocus = NSApp.isActive && (panel.isKeyWindow || FilePanelPresenter.activePanel != nil)
        FilePanelPresenter.cancelActivePanel()
        saveGeometry()
        panel.orderOut(nil)
        if restoreFocus, let previousApplication, !previousApplication.isTerminated {
            NSApp.yieldActivation(to: previousApplication)
            previousApplication.activate(options: [])
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { hidePanel(); return false }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { model.undoManager }
    func windowDidMove(_ notification: Notification) { saveGeometry() }
    func windowDidResize(_ notification: Notification) { saveGeometry() }
    private func saveGeometry() { if let panel { preferences.set(NSStringFromRect(panel.frame), forKey: "window.frame") } }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard showsInterface else { return false }
        if panel != nil { showPanel() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if panel?.attachedSheet == nil && compositionAllowsDismissal() && model.flushEditsForDismissal() {
            FilePanelPresenter.cancelActivePanel()
            saveGeometry()
            return .terminateNow
        }
        showPanel()
        return .terminateCancel
    }

    private func compositionAllowsDismissal() -> Bool {
        if let editor = panel?.firstResponder as? NSTextView, editor.hasMarkedText() {
            model.errorMessage = "Finish composing text before hiding or quitting."
            return false
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        FilePanelPresenter.cancelActivePanel()
        shortcut?.stop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    private func configureShortcut() {
        guard !LabEnvironment.isEnabled else { return }
        if preferences.bool(forKey: "shortcut.disabled") { shortcutValue = nil }
        else if preferences.object(forKey: "shortcut.keyCode") != nil {
            shortcutValue = ShortcutValue(keyCode: UInt32(preferences.integer(forKey: "shortcut.keyCode")), modifiers: UInt32(preferences.integer(forKey: "shortcut.modifiers")), label: preferences.string(forKey: "shortcut.label") ?? "Custom")
        } else { shortcutValue = .standard }
        let shortcut = GlobalShortcut()
        shortcut.action = { [weak self] in self?.toggleFromShortcut() }
        self.shortcut = shortcut
        do { try shortcut.register(shortcutValue) }
        catch { model.errorMessage = "\(error.localizedDescription) Set another shortcut in the Chit menu." }
    }

    @objc private func editShortcut() {
        guard !LabEnvironment.isEnabled else { return }
        showPanel()
        guard recorder == nil else { return }
        let recorder = ShortcutRecorder(current: shortcutValue)
        recorder.onSave = { [weak self] value in
            guard let self else { return "The app is no longer available." }
            do {
                try self.shortcut?.register(value)
                self.shortcutValue = value
                self.preferences.set(value == nil, forKey: "shortcut.disabled")
                if let value {
                    self.preferences.set(Int(value.keyCode), forKey: "shortcut.keyCode")
                    self.preferences.set(Int(value.modifiers), forKey: "shortcut.modifiers")
                    self.preferences.set(value.label, forKey: "shortcut.label")
                }
                return nil
            } catch {
                try? self.shortcut?.register(self.shortcutValue)
                return error.localizedDescription
            }
        }
        recorder.onClose = { [weak self] in self?.recorder = nil }
        self.recorder = recorder
        recorder.present(on: panel)
    }

    private func runHarness() {
        Task { @MainActor in
            do {
                if filePanelTest { try await NativeFilePanelHarness.run(delegate: self) }
                if smokeTest { try await NativeSmokeHarness.run(delegate: self, statusItem: statusItem) }
                // Give SwiftUI a run-loop pass after smoke mutations before rendering.
                try await Task.sleep(nanoseconds: 200_000_000)
                finishHarness()
            } catch { exitHarness(error.localizedDescription, code: 1) }
        }
    }

    private func finishHarness() {
        Task { @MainActor in
            do {
                if let snapshotPath {
                    if snapshotNewList {
                        try await ListActions.captureNewListForm(model: model, at: URL(fileURLWithPath: snapshotPath))
                    } else if let previewBackdrop {
                        try await NativePreview.capture(panel: panel, backdrop: previewBackdrop, path: snapshotPath)
                    } else { try saveSnapshot(to: snapshotPath) }
                }
                if !showsInterface {
                    guard !panel.isVisible, statusItem == nil, !NSApp.isActive else {
                        throw harnessError("Hidden Lab validation unexpectedly displayed UI or took focus.")
                    }
                }
                guard model.flushPendingEdits() else { throw harnessError(model.errorMessage ?? "Final save failed.") }
                if smokeTest { print("Chit smoke test passed: borderless panel and focus, shortcut toggle, hide/reopen, close control, project tab drops and grouping, task selection/repeated clicks, blank-space reset, native text selection, pending edits, native typing/Undo, editor retention across completion, marked composition guards, resize geometry, persistence.") }
                previewBackdrop?.orderOut(nil)
                shortcut?.stop()
                try writeLabResult(ok: true, message: "Native validation completed.")
                NSApp.terminate(nil)
            } catch { exitHarness(error.localizedDescription, code: 1) }
        }
    }

    private func saveSnapshot(to path: String) throws {
        guard let root = panel.contentView else { throw harnessError("No content view to snapshot.") }
        // Capture the complete owning view hierarchy, including custom window controls.
        // Caching our own view hierarchy needs no screen-recording permission.
        let content = root.superview ?? root
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw harnessError("Could not allocate snapshot bitmap.") }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw harnessError("Could not encode snapshot PNG.") }
        let destination = URL(fileURLWithPath: path)
        try LabEnvironment.requireAllowed(destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: destination, options: .atomic)
        print("Snapshot saved: \(path)")
    }

    private func harnessError(_ message: String) -> NSError {
        NSError(domain: "Chit.Launch", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func exitHarness(_ message: String, code: Int32) -> Never {
        try? writeLabResult(ok: false, message: message)
        FileHandle.standardError.write(Data("\(applicationName): \(message)\n".utf8))
        Darwin.exit(code)
    }

    private func writeLabResult(ok: Bool, message: String) throws {
        guard let labResultPath else { return }
        let url = URL(fileURLWithPath: labResultPath)
        try LabEnvironment.requireAllowed(url)
        let data = try JSONSerialization.data(withJSONObject: ["ok": ok, "message": message], options: [.sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

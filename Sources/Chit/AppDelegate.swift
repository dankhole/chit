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

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil else { return }
        do { try parseArguments() } catch { exitHarness(error.localizedDescription, code: 64) }
        isHarness = smokeTest || filePanelTest || snapshotPath != nil
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        if let isolatedStorePath {
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
        makeStatusItem()
        showPanel()
        if snapshotBackdrop { previewBackdrop = NativePreview.makeBackdrop(behind: panel) }
        if !isHarness { configureShortcut() }
        if isHarness {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.runHarness() }
        }
    }

    private func parseArguments() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var index = 0
        while index < arguments.count {
            let value = arguments[index]
            switch value {
            case "--store", "--snapshot", "--snapshot-expand", "--snapshot-size", "--snapshot-collapse":
                index += 1
                guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                    throw harnessError("\(value) requires a path.")
                }
                let path = (arguments[index] as NSString).expandingTildeInPath
                if value == "--store" { isolatedStorePath = path }
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
        if (smokeTest || filePanelTest || snapshotPath != nil) && isolatedStorePath == nil {
            throw harnessError("--smoke-test, --file-panel-test and --snapshot require --store with an isolated workspace path.")
        }
        if (snapshotExpandedTask != nil || snapshotSize != nil || !snapshotCollapsedGroups.isEmpty || snapshotSolid || snapshotContrast || snapshotBackdrop || snapshotCompleted || snapshotNewList || snapshotRecovery) && snapshotPath == nil {
            throw harnessError("Snapshot layout flags require --snapshot and an isolated --store.")
        }
    }

    private func makePanel() {
        panel = TodoPanel(contentRect: NSRect(x: 0, y: 0, width: 424, height: 350), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "Chit"
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
        let appMenu = NSMenu(title: "Chit")
        appMenu.addItem(item("Settings…", action: #selector(showSettings), key: ","))
        appMenu.addItem(item("Global Shortcut…", action: #selector(editShortcut)))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide Chit", action: #selector(hideFromMenu), key: "h"))
        appMenu.addItem(item("Quit Chit", action: #selector(quit), key: "q"))
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
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Chit")
        status.button?.toolTip = "Chit — click to show or hide; right-click for settings"
        status.button?.target = self
        status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = status
    }

    @objc private func statusClicked() {
        settingsPopover?.performClose(nil)
        if NSApp.currentEvent?.type == .rightMouseUp, let statusItem {
            let menu = NSMenu()
            menu.addItem(item(panel.isVisible ? "Hide Chit" : "Show Chit", action: #selector(toggleFromMenu)))
            menu.addItem(item("Settings…", action: #selector(showSettings)))
            menu.addItem(item("Global Shortcut…", action: #selector(editShortcut)))
            menu.addItem(.separator())
            menu.addItem(item("Quit Chit", action: #selector(quit)))
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
                if smokeTest {
                    try exerciseLifecycle()
                    try await exerciseProjectDrag()
                    let previousExpanded = model.expandedTaskID
                    let title = "Native editor smoke \(UUID().uuidString)"
                    model.addTask(title)
                    guard let task = model.selectedProject?.tasks.first(where: { $0.title == title }) else { throw harnessError("Could not create native editor smoke task.") }
                    model.toggleDetails(taskID: task.id)
                    try await Task.sleep(nanoseconds: 250_000_000)
                    try await exerciseNativeEditor(taskID: task.id, title: title)
                    if let task = model.selectedProject?.tasks.first(where: { $0.id == task.id }) { model.deleteTask(task) }
                    if let previousExpanded { model.toggleDetails(taskID: previousExpanded) }
                }
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
                guard model.flushPendingEdits() else { throw harnessError(model.errorMessage ?? "Final save failed.") }
                if smokeTest { print("Chit smoke test passed: borderless panel and focus, shortcut toggle, hide/reopen, close control, project tab drops and grouping, pending edits, native typing/Undo, editor retention across completion, marked composition guards, resize geometry, persistence.") }
                previewBackdrop?.orderOut(nil)
                shortcut?.stop()
                NSApp.terminate(nil)
            } catch { exitHarness(error.localizedDescription, code: 1) }
        }
    }

    private func exerciseLifecycle() throws {
        func check(_ value: Bool, _ message: String) throws { if !value { throw harnessError(message) } }
        try check(model.isStoreAvailable, model.errorMessage ?? "Store unavailable.")
        try check(panel.isVisible && panel.canBecomeKey && !panel.hidesOnDeactivate && panel.level == .floating && panel.alphaValue == 1, "Native panel configuration failed.")
        try check(panel.styleMask == .borderless, "Panel still has native frame chrome.")
        try check(panel.isKeyWindow && NSApp.isActive, "Showing the panel did not focus it (key=\(panel.isKeyWindow), active=\(NSApp.isActive)).")
        try check(NSApp.activationPolicy() == .accessory && statusItem?.button != nil, "Menu-bar-only app integration failed.")
        statusItem?.button?.performClick(nil)
        try check(!panel.isVisible, "Menu bar button did not hide the panel.")
        statusItem?.button?.performClick(nil)
        try check(panel.isVisible, "Menu bar button did not show the panel.")
        toggleFromShortcut()
        try check(!panel.isVisible, "Focused shortcut did not hide the panel.")
        toggleFromShortcut()
        try check(panel.isVisible, "Hidden shortcut did not show the panel.")
        let originalProject = model.selectedProjectID
        model.addTask("Native lifecycle smoke \(UUID().uuidString)")
        guard let task = model.selectedProject?.tasks.last else { throw harnessError("Could not create smoke task.") }
        model.setText(itemID: task.id, field: .title, value: "")
        try check(!hidePanel() && panel.isVisible, "An invalid draft did not prevent hiding.")
        try check(applicationShouldTerminate(NSApp) == .terminateCancel, "An invalid draft did not prevent normal quit.")
        model.setText(itemID: task.id, field: .title, value: "Saved native lifecycle smoke")
        try check(hidePanel() && !panel.isVisible, "A valid edit did not save and hide.")
        let persisted = try model.store.load()
        try check(persisted.projects.flatMap(\.tasks).contains(where: { $0.id == task.id && $0.title == "Saved native lifecycle smoke" }), "Pending edit did not reach the store.")
        showPanel()
        try check(panel.isVisible && model.selectedProjectID == originalProject, "Reopen did not preserve project state.")
        panel.performClose(nil)
        try check(!panel.isVisible, "Close did not hide the panel.")
        showPanel()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        guard let root = panel.contentView,
              let chrome = descendants(root).compactMap({ $0 as? PanelChrome }).first,
              let resizing = panel.contentView?.subviews.compactMap({ $0 as? PanelResizeOverlay }).first else {
            throw harnessError("Borderless panel controls were not mounted.")
        }
        chrome.closeButton.performClick(nil)
        try check(!panel.isVisible, "Borderless close control did not hide the panel.")
        showPanel()
        panel.contentView?.layoutSubtreeIfNeeded()
        try check(resizing.resizeEdges(at: NSPoint(x: resizing.bounds.midX, y: resizing.bounds.midY)).isEmpty,
                  "Resize overlay intercepts ordinary content.")
        try check(resizing.resizeEdges(at: NSPoint(x: 2, y: 2)) == [.left, .bottom], "Resize corner hit target failed.")
        let initial = NSRect(x: 100, y: 200, width: 424, height: 350)
        try check(WindowGeometry.resized(initial, delta: NSSize(width: 1000, height: 1000), edges: [.left, .bottom]) == NSRect(x: 204, y: 310, width: 320, height: 240),
                  "Resizing from the bottom-left did not preserve opposite edges at the minimum size.")
        try check(WindowGeometry.resized(initial, delta: NSSize(width: 76, height: 50), edges: [.right, .top]) == NSRect(x: 100, y: 200, width: 500, height: 400),
                  "Resizing from the top-right did not preserve opposite edges.")
        let reachable = WindowGeometry.reachable(NSRect(x: 9000, y: -9000, width: 424, height: 350), screens: [NSRect(x: 0, y: 0, width: 1000, height: 700)])
        try check(NSRect(x: 0, y: 0, width: 1000, height: 700).contains(reachable), "Offscreen window restoration failed.")
        if let current = model.selectedProject?.tasks.first(where: { $0.id == task.id }) { model.deleteTask(current) }
        try check(applicationShouldTerminate(NSApp) == .terminateNow, "Clean state did not permit quitting.")
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
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: destination, options: .atomic)
        print("Snapshot saved: \(path)")
    }

    private func exerciseProjectDrag() async throws {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func check(_ value: Bool, _ message: String) throws { if !value { throw harnessError(message) } }
        func target(_ destination: ProjectDragDestination) throws -> ProjectDragView {
            panel.contentView?.layoutSubtreeIfNeeded()
            guard let root = panel.contentView,
                  let view = descendants(root).compactMap({ $0 as? ProjectDragView }).first(where: { $0.destination == destination }) else {
                throw harnessError("Native project drop target was not mounted.")
            }
            return view
        }
        let selected = model.selectedProjectID
        let group = ProjectGroup(name: "Smoke drop group")
        let anchor = Project(name: "Smoke anchor")
        let source = Project(name: "Smoke draggable")
        _ = try model.store.apply(.batch([
            .addGroup(group: group, index: nil),
            .addProject(project: anchor, index: nil),
            .addProject(project: source, index: nil)
        ]))
        defer {
            if let latest = try? model.store.load() {
                let projects = latest.projects.filter { $0.id == anchor.id || $0.id == source.id }
                _ = try? model.store.apply(.batch(projects.map { .deleteProject(id: $0.id, expected: $0) } + [.deleteEmptyGroup(id: group.id, expected: group)]))
            }
            model.refresh()
            model.selectProject(selected)
        }
        model.refresh()
        try await Task.sleep(nanoseconds: 150_000_000)
        let anchorView = try target(.tab(anchor.id))
        guard let state = anchorView.dragState else { throw harnessError("Native project drag state was not connected.") }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally(); state.finish() }
        func beginDrag() throws {
            guard let current = model.workspace.projects.first(where: { $0.id == source.id }) else { throw harnessError("Smoke project disappeared.") }
            let payload = state.begin(project: current, model: model)
            pasteboard.clearContents()
            pasteboard.setData(try JSONEncoder().encode(payload), forType: ProjectDragView.pasteboardType)
        }
        try beginDrag()
        try check(anchorView.performDrop(pasteboard: pasteboard, location: NSPoint(x: 1, y: anchorView.bounds.midY)), "Dropping before a project failed.")
        var ids = model.workspace.projects.map(\.id)
        try check(ids.firstIndex(of: source.id)! + 1 == ids.firstIndex(of: anchor.id)!, "Leading tab drop did not reorder projects.")
        try beginDrag()
        try check(anchorView.performDrop(pasteboard: pasteboard, location: NSPoint(x: anchorView.bounds.width - 1, y: anchorView.bounds.midY)), "Dropping after a project failed.")
        ids = model.workspace.projects.map(\.id)
        try check(ids.firstIndex(of: anchor.id)! + 1 == ids.firstIndex(of: source.id)!, "Trailing tab drop did not reorder projects.")
        model.toggleGroup(group.id)
        try await Task.sleep(nanoseconds: 100_000_000)
        let groupView = try target(.group(group.id))
        try beginDrag()
        try check(groupView.performDrop(pasteboard: pasteboard, location: NSPoint(x: groupView.bounds.midX, y: groupView.bounds.midY)), "Dropping into a collapsed group failed.")
        try check(model.workspace.projects.first(where: { $0.id == source.id })?.groupID == group.id && model.collapsedGroupIDs.contains(group.id),
                  "Group drop did not preserve the collapsed group state.")
        try beginDrag()
        try await Task.sleep(nanoseconds: 100_000_000)
        let ungroupView = try target(.group(nil))
        try check(ungroupView.performDrop(pasteboard: pasteboard, location: NSPoint(x: ungroupView.bounds.midX, y: ungroupView.bounds.midY)), "Temporary Ungroup target rejected a project.")
        try check(model.workspace.projects.first(where: { $0.id == source.id })?.groupID == nil, "Ungroup drop did not save.")
        try beginDrag()
        let foreign = ProjectDragPayload(workspaceScope: UUID().uuidString, projectID: source.id, sourceGroupID: nil, expectedOrder: model.workspace.projects.map(\.id))
        pasteboard.clearContents()
        pasteboard.setData(try JSONEncoder().encode(foreign), forType: ProjectDragView.pasteboardType)
        let revision = model.workspace.revision
        try check(!anchorView.performDrop(pasteboard: pasteboard, location: NSPoint(x: 1, y: 1)) && model.workspace.revision == revision,
                  "A foreign project payload changed the store.")
        pasteboard.clearContents()
        pasteboard.setString("Arbitrary text", forType: .string)
        try check(!anchorView.performDrop(pasteboard: pasteboard, location: NSPoint(x: 1, y: 1)), "A text drop was treated as a project.")
        state.finish()
        try check(model.selectedProjectID == selected && state.payload == nil && state.hoveredTarget == nil,
                  "Dragging changed selection or left temporary drop feedback behind.")
        try check(try model.store.load() == model.workspace, "Project drops were not persisted.")
    }

    private func exerciseNativeEditor(taskID: String, title: String) async throws {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func check(_ value: Bool, _ message: String) throws { if !value { throw harnessError(message) } }
        panel.contentView?.layoutSubtreeIfNeeded()
        guard let root = panel.contentView,
              let editor = descendants(root).compactMap({ $0 as? PlainTextView }).first(where: { $0.string == title }) else {
            throw harnessError("Expanded native title editor was not mounted.")
        }
        try check(panel.makeFirstResponder(editor), "Native title editor rejected first responder.")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.insertText(" typed", replacementRange: editor.selectedRange())
        let typed = title + " typed"
        try check(model.text(itemID: taskID, field: .title, fallback: title) == typed, "Native typing did not publish a draft.")
        editor.breakUndoCoalescing()
        try check(editor.localUndo.canUndo, "Native text edit did not register Undo.")
        try check(NSApp.sendAction(Selector(("undo:")), to: nil, from: self), "Native responder rejected Undo.")
        try check(editor.string == title && model.text(itemID: taskID, field: .title, fallback: title) == title, "Native text Undo did not restore the draft (editor=\(editor.string), draft=\(model.text(itemID: taskID, field: .title, fallback: title))).")
        try check(NSApp.sendAction(Selector(("redo:")), to: nil, from: self), "Native responder rejected Redo.")
        try check(editor.string == typed, "Native text Redo did not restore the edit.")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
        try check(editor.hasMarkedText(), "Could not establish native marked composition.")
        try check(model.text(itemID: taskID, field: .title, fallback: title) == typed, "Provisional composition was published prematurely.")
        try check(!hidePanel() && panel.isVisible, "Marked composition did not prevent hide.")
        try check(applicationShouldTerminate(NSApp) == .terminateCancel, "Marked composition did not prevent normal quit.")
        let compositionSelection = editor.selectedRange()
        let external = TodoStore(url: model.store.url)
        _ = try external.apply(.patchTask(id: taskID, patch: TaskPatch(completed: FieldChange(expected: false, value: true))))
        model.refresh()
        try await Task.sleep(nanoseconds: 150_000_000)
        panel.contentView?.layoutSubtreeIfNeeded()
        try check(model.isCompletedExpanded(projectID: model.selectedProjectID), "Completing an edited task did not reveal its Completed section.")
        try check(descendants(root).contains(where: { $0 === editor }) && editor.window === panel,
                  "Moving into Completed replaced the native editor.")
        try check(panel.firstResponder === editor && editor.hasMarkedText() && editor.selectedRange() == compositionSelection,
                  "Moving into Completed disrupted focus, composition, or selection.")
        try check(!model.toggleCompleted(projectID: model.selectedProjectID), "Collapsing Completed discarded native composition.")
        editor.insertText("あ", replacementRange: NSRange(location: NSNotFound, length: 0))
        try check(!editor.hasMarkedText(), "Native composition did not commit.")
        try check(model.flushPendingEdits(), "Native committed edit failed to save.")
        let saved = try model.store.load().projects.flatMap(\.tasks).first(where: { $0.id == taskID })
        try check(saved?.title == typed + "あ", "Native committed composition was not persisted.")
        try check(saved?.completed == true, "Saving native composition lost the agent's completion.")
        try check(model.toggleCompleted(projectID: model.selectedProjectID), "Completed section could not collapse after saving composition.")
        panel.makeFirstResponder(nil)
    }

    private func harnessError(_ message: String) -> NSError {
        NSError(domain: "Chit.Launch", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func exitHarness(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data("Chit: \(message)\n".utf8))
        Darwin.exit(code)
    }
}

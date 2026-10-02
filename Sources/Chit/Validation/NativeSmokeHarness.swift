import AppKit
import TodoCore

/// Native smoke scenarios for explicitly requested isolated-store launches.
/// Launch configuration, isolation, snapshots, and exit handling stay with AppDelegate.
@MainActor
final class NativeSmokeHarness {
    private let delegate: AppDelegate
    private let statusItem: NSStatusItem?
    private var model: AppModel { delegate.model }
    private var panel: TodoPanel { delegate.panel }

    private init(delegate: AppDelegate, statusItem: NSStatusItem?) {
        self.delegate = delegate
        self.statusItem = statusItem
    }

    static func run(delegate: AppDelegate, statusItem: NSStatusItem?) async throws {
        try await NativeSmokeHarness(delegate: delegate, statusItem: statusItem).run()
    }

    private func run() async throws {
        try exerciseLifecycle()
        try await exerciseProjectDrag()
        try await exerciseTaskDrag()
        try await exerciseTaskEntry()
        let previousExpanded = model.expandedTaskID
        let title = "Native editor smoke \(UUID().uuidString)"
        model.addTask(title)
        guard let task = model.selectedProject?.tasks.first(where: { $0.title == title }) else { throw harnessError("Could not create native editor smoke task.") }
        model.toggleDetails(taskID: task.id)
        try await Task.sleep(nanoseconds: 250_000_000)
        try await exerciseDeadlineMenus(taskID: task.id)
        try await exerciseNativeEditor(taskID: task.id, title: title)
        if let task = model.selectedProject?.tasks.first(where: { $0.id == task.id }) { model.deleteTask(task) }
        if let previousExpanded { model.toggleDetails(taskID: previousExpanded) }
        try await exerciseTaskRowClicks()
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
        delegate.toggleFromShortcut()
        try check(!panel.isVisible, "Focused shortcut did not hide the panel.")
        delegate.toggleFromShortcut()
        try check(panel.isVisible, "Hidden shortcut did not show the panel.")
        let originalProject = model.selectedProjectID
        let title = "Native lifecycle smoke \(UUID().uuidString)"
        model.addTask(title)
        guard let task = model.selectedProject?.tasks.first, task.title == title else { throw harnessError("Could not create smoke task at the top of the list.") }
        model.setText(itemID: task.id, field: .title, value: "")
        try check(!delegate.hidePanel() && panel.isVisible, "An invalid draft did not prevent hiding.")
        try check(delegate.applicationShouldTerminate(NSApp) == .terminateCancel, "An invalid draft did not prevent normal quit.")
        model.setText(itemID: task.id, field: .title, value: "Saved native lifecycle smoke")
        try check(delegate.hidePanel() && !panel.isVisible, "A valid edit did not save and hide.")
        let persisted = try model.store.load()
        try check(persisted.projects.flatMap(\.tasks).contains(where: { $0.id == task.id && $0.title == "Saved native lifecycle smoke" }), "Pending edit did not reach the store.")
        delegate.showPanel()
        try check(panel.isVisible && model.selectedProjectID == originalProject, "Reopen did not preserve project state.")
        panel.performClose(nil)
        try check(!panel.isVisible, "Close did not hide the panel.")
        delegate.showPanel()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        guard let root = panel.contentView,
              let chrome = descendants(root).compactMap({ $0 as? PanelChrome }).first,
              let resizing = panel.contentView?.subviews.compactMap({ $0 as? PanelResizeOverlay }).first else {
            throw harnessError("Borderless panel controls were not mounted.")
        }
        chrome.closeButton.performClick(nil)
        try check(!panel.isVisible, "Borderless close control did not hide the panel.")
        delegate.showPanel()
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
        try check(delegate.applicationShouldTerminate(NSApp) == .terminateNow, "Clean state did not permit quitting.")
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
        let originalSize = panel.contentRect(forFrameRect: panel.frame).size
        let originalSidebarOpen = model.sidebarDockedOpen
        let group = ProjectGroup(name: "Smoke drop group")
        let anchor = Project(name: "Smoke anchor")
        let source = Project(name: "Smoke draggable")
        let scrollProjects = (1...12).map { Project(name: "Smoke scroll \($0)") }
        let fixtureIDs = Set([anchor.id, source.id] + scrollProjects.map(\.id))
        _ = try model.store.apply(.batch([
            .addGroup(group: group, index: nil),
            .addProject(project: anchor, index: nil),
            .addProject(project: source, index: nil)
        ] + scrollProjects.map { .addProject(project: $0, index: nil) }))
        defer {
            if let latest = try? model.store.load() {
                let projects = latest.projects.filter { fixtureIDs.contains($0.id) }
                _ = try? model.store.apply(.batch(projects.map { .deleteProject(id: $0.id, expected: $0) } + [.deleteEmptyGroup(id: group.id, expected: group)]))
            }
            model.refresh()
            model.selectProject(selected)
            if model.sidebarDockedOpen != originalSidebarOpen { _ = model.toggleSidebar() }
            panel.setContentSize(originalSize)
        }
        model.refresh()
        panel.setContentSize(NSSize(width: 760, height: 350))
        model.updateSidebarLayout(availableWidth: 760)
        if !model.sidebarDockedOpen { _ = model.toggleSidebar() }
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
        func verticalPoint(_ view: ProjectDragView, above: Bool) -> NSPoint {
            NSPoint(x: view.bounds.midX,
                    y: above == view.isFlipped ? view.bounds.minY + 1 : view.bounds.maxY - 1)
        }
        let upperPoint = verticalPoint(anchorView, above: true)
        try check(anchorView.updateDrop(pasteboard: pasteboard, location: upperPoint) == .move && state.hoveredTarget == .before(anchor.id),
                  "The upper sidebar row did not provide insertion feedback.")
        try check(anchorView.performDrop(pasteboard: pasteboard, location: upperPoint), "Dropping above a project failed.")
        var ids = model.workspace.projects.map(\.id)
        try check(ids.firstIndex(of: source.id)! + 1 == ids.firstIndex(of: anchor.id)!, "Upper sidebar drop did not reorder projects.")
        try beginDrag()
        let lowerPoint = verticalPoint(anchorView, above: false)
        try check(anchorView.updateDrop(pasteboard: pasteboard, location: lowerPoint) == .move && state.hoveredTarget == .after(anchor.id),
                  "The lower sidebar row did not provide insertion feedback.")
        try check(anchorView.performDrop(pasteboard: pasteboard, location: lowerPoint), "Dropping below a project failed.")
        ids = model.workspace.projects.map(\.id)
        try check(ids.firstIndex(of: anchor.id)! + 1 == ids.firstIndex(of: source.id)!, "Lower sidebar drop did not reorder projects.")
        guard let sidebarScroll = anchorView.enclosingScrollView,
              let root = panel.contentView,
              let taskEditor = descendants(root).compactMap({ $0 as? PlainTextView }).first,
              let taskScroll = taskEditor.enclosingScrollView else {
            throw harnessError("The sidebar and task scroll views were not mounted.")
        }
        try check(sidebarScroll !== taskScroll, "Sidebar rows share the task pane's scroll view.")
        let clip = sidebarScroll.contentView
        let originalScroll = clip.bounds.origin
        let originalTaskScroll = taskScroll.contentView.bounds.origin
        try beginDrag()
        let bottomEdge = NSPoint(x: clip.bounds.midX,
                                 y: clip.isFlipped ? clip.bounds.maxY - 2 : clip.bounds.minY + 2)
        try check(anchorView.autoscrollSidebar(at: clip.convert(bottomEdge, to: nil)) && clip.bounds.origin != originalScroll,
                  "Dragging at the lower sidebar edge did not scroll overflowing lists.")
        let afterEdgeScroll = clip.bounds.origin
        guard let wheelEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                       wheel1: -60, wheel2: 0, wheel3: 0).flatMap({ NSEvent(cgEvent: $0) }) else {
            throw harnessError("Could not create a native sidebar scroll event.")
        }
        anchorView.scrollWheel(with: wheelEvent)
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(clip.bounds.origin != afterEdgeScroll && taskScroll.contentView.bounds.origin == originalTaskScroll,
                  "Wheel scrolling over a native sidebar row did not scroll only its own pane.")
        state.finish()
        clip.scroll(to: originalScroll)
        sidebarScroll.reflectScrolledClipView(clip)
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

    private func exerciseTaskDrag() async throws {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func check(_ value: Bool, _ message: String) throws { if !value { throw harnessError(message) } }
        let originalProject = model.selectedProjectID
        let originalSize = panel.contentRect(forFrameRect: panel.frame).size
        let source = TaskItem(title: "Native draggable task", notes: "Drag keeps notes", subtasks: [Subtask(title: "Drag keeps child")])
        let anchor = TaskItem(title: "Native task anchor")
        let done = TaskItem(title: "Native completed task", completed: true)
        let project = Project(name: "Task drag smoke", tasks: [anchor, done, source])
        _ = try model.store.apply(.addProject(project: project, index: nil))
        defer {
            panel.makeFirstResponder(nil)
            if let current = try? model.store.load().projects.first(where: { $0.id == project.id }) {
                _ = try? model.store.apply(.deleteProject(id: project.id, expected: current))
            }
            model.refresh()
            model.selectProject(originalProject)
            panel.setContentSize(originalSize)
        }
        model.refresh()
        model.selectProject(project.id)
        model.toggleCompleted(projectID: project.id)
        panel.setContentSize(NSSize(width: 424, height: 400))
        try await Task.sleep(nanoseconds: 150_000_000)
        panel.contentView?.layoutSubtreeIfNeeded()
        guard let root = panel.contentView else { throw harnessError("No task drag content view.") }
        func nativeView(taskID: String, source: Bool = false) throws -> TaskDragView {
            root.layoutSubtreeIfNeeded()
            guard let view = descendants(root).compactMap({ $0 as? TaskDragView }).first(where: {
                $0.task?.id == taskID && $0.projectID == project.id && $0.isSource == source
            }) else { throw harnessError("Native task grip/drop target was not mounted.") }
            return view
        }
        let grip = try nativeView(taskID: source.id, source: true)
        let destination = try nativeView(taskID: anchor.id)
        let completedDestination = try nativeView(taskID: done.id)
        guard let state = grip.dragState,
              let title = descendants(root).compactMap({ $0 as? PlainTextView }).first(where: { $0.editorIdentity == "\(anchor.id):title" }) else {
            throw harnessError("Task drag state or native title was not connected.")
        }
        let gripPoint = grip.convert(NSPoint(x: grip.bounds.midX, y: grip.bounds.midY), to: nil)
        let gripHit = root.hitTest(root.superview?.convert(gripPoint, from: nil) ?? gripPoint)
        try check(gripHit === grip && grip.bounds.width <= 20 && grip.bounds.height >= 24,
                  "The visible task grip did not own its compact drag hit area.")
        let titlePoint = title.convert(NSPoint(x: 30, y: title.textContainerInset.height + 8), to: nil)
        let titleHit = root.hitTest(root.superview?.convert(titlePoint, from: nil) ?? titlePoint)
        try check(titleHit === title, "An idle task drop overlay intercepted native title selection.")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally(); state.finish() }
        func beginDrag() throws {
            guard let current = model.selectedProject?.tasks.first(where: { $0.id == source.id }),
                  let payload = state.begin(task: current, projectID: project.id, model: model) else {
                throw harnessError("Task drag could not begin from its mounted grip.")
            }
            pasteboard.clearContents()
            pasteboard.setData(try JSONEncoder().encode(payload), forType: TaskDragView.pasteboardType)
        }
        try beginDrag()
        try check(destination.updateDrop(pasteboard: pasteboard, location: NSPoint(x: destination.bounds.midX, y: 1)) == .move && state.hoveredTarget == .before(anchor.id),
                  "The upper task drop target did not provide insertion feedback.")
        try check(destination.hitTest(destination.superview?.convert(titlePoint, from: nil) ?? titlePoint) === destination,
                  "The active task destination did not cover the title area.")
        _ = try model.store.apply(.patchTask(id: source.id, patch: TaskPatch(notes: FieldChange(expected: source.notes, value: "Concurrent drag notes"))))
        try check(destination.performDrop(pasteboard: pasteboard, location: NSPoint(x: destination.bounds.midX, y: 1)), "Dropping before a task failed.")
        try check(model.selectedProject?.tasks.filter { !$0.completed }.map(\.id) == [source.id, anchor.id],
                  "The upper row drop did not persist task order.")
        try beginDrag()
        try check(destination.updateDrop(pasteboard: pasteboard, location: NSPoint(x: destination.bounds.midX, y: destination.bounds.height - 1)) == .move && state.hoveredTarget == .after(anchor.id),
                  "The lower task drop target did not provide insertion feedback.")
        try check(destination.performDrop(pasteboard: pasteboard, location: NSPoint(x: destination.bounds.midX, y: destination.bounds.height - 1)), "Dropping after a task failed.")
        try check(model.selectedProject?.tasks.filter { !$0.completed }.map(\.id) == [anchor.id, source.id],
                  "The lower row drop did not persist task order.")
        try beginDrag()
        try check(completedDestination.updateDrop(pasteboard: pasteboard, location: NSPoint(x: 10, y: 1)) == [] && state.hoveredTarget == nil,
                  "A task drag offered placement in another completion section.")
        try check(!completedDestination.performDrop(pasteboard: pasteboard, location: NSPoint(x: 10, y: 1)),
                  "A task drag crossed completion sections.")
        try beginDrag()
        guard let active = state.payload else { throw harnessError("Task drag payload disappeared.") }
        let foreign = TaskDragPayload(workspaceScope: UUID().uuidString, projectID: active.projectID,
            taskID: active.taskID, completed: active.completed, expectedOrder: active.expectedOrder)
        pasteboard.clearContents()
        pasteboard.setData(try JSONEncoder().encode(foreign), forType: TaskDragView.pasteboardType)
        let revision = model.workspace.revision
        try check(!destination.performDrop(pasteboard: pasteboard, location: NSPoint(x: 10, y: 1)) && model.workspace.revision == revision,
                  "A foreign task payload changed the store.")
        try beginDrag()
        pasteboard.clearContents()
        pasteboard.setString("Arbitrary text", forType: .string)
        try check(!destination.performDrop(pasteboard: pasteboard, location: NSPoint(x: 10, y: 1)), "A text drop was treated as a task.")
        try check(state.payload == nil && state.hoveredTarget == nil && model.selectedProjectID == project.id,
                  "A task drag left feedback behind or changed list selection.")
        let stored = try model.store.load()
        let latest = stored.projects.first(where: { $0.id == project.id })?.tasks.first(where: { $0.id == source.id })
        try check(latest?.notes == "Concurrent drag notes" && latest?.subtasks == source.subtasks && latest?.completed == false,
                  "Task dragging lost concurrent notes, subtasks, or completion state.")
        try check(stored == model.workspace, "Native task drops were not persisted.")
    }

    private func exerciseTaskEntry() async throws {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        guard let project = model.selectedProject, let root = panel.contentView else {
            throw harnessError("Could not prepare the top task entry check.")
        }
        NotificationCenter.default.post(name: ListActions.focusEntry, object: project.id)
        try await Task.sleep(nanoseconds: 150_000_000)
        root.layoutSubtreeIfNeeded()
        guard let entry = descendants(root).compactMap({ $0 as? PlainTextView }).first(where: { $0.editorIdentity == "add:\(project.id)" }),
              panel.makeFirstResponder(entry) else {
            throw harnessError("The top task entry was not mounted or could not receive focus.")
        }
        let initialY = entry.convert(entry.bounds, to: nil).midY
        var added: [String] = []
        defer {
            panel.makeFirstResponder(nil)
            for id in added {
                if let task = model.selectedProject?.tasks.first(where: { $0.id == id }) { model.deleteTask(task) }
            }
        }
        for index in 1...2 {
            let title = "Top entry smoke \(index) \(UUID().uuidString)"
            entry.insertText(title, replacementRange: entry.selectedRange())
            entry.insertNewline(nil)
            try await Task.sleep(nanoseconds: 150_000_000)
            root.layoutSubtreeIfNeeded()
            guard let latest = model.selectedProject, let task = latest.tasks.first, task.title == title else {
                throw harnessError("Submitting the native task entry did not prepend its task.")
            }
            added.insert(task.id, at: 0)
            guard Array(latest.tasks.prefix(added.count).map(\.id)) == added,
                  entry.string.isEmpty, panel.firstResponder === entry,
                  descendants(root).contains(where: { $0 === entry }),
                  abs(entry.convert(entry.bounds, to: nil).midY - initialY) <= 1 else {
                throw harnessError("Repeated task additions moved, replaced, or defocused the top entry.")
            }
        }
    }

    private func exerciseTaskRowClicks() async throws {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func check(_ value: Bool, _ message: String) throws { if !value { throw harnessError(message) } }
        let originalProject = model.selectedProjectID
        let originalSize = panel.contentRect(forFrameRect: panel.frame).size
        let subtask = Subtask(title: "Native row subtask")
        let task = TaskItem(title: "Native row click selection\n", notes: "Native row notes", subtasks: [subtask])
        let ordinaryTask = TaskItem(title: "Native ordinary row")
        let project = Project(name: "Click smoke", tasks: [task, ordinaryTask])
        _ = try model.store.apply(.addProject(project: project, index: nil))
        defer {
            panel.makeFirstResponder(nil)
            if let current = try? model.store.load().projects.first(where: { $0.id == project.id }) {
                _ = try? model.store.apply(.deleteProject(id: project.id, expected: current))
            }
            model.refresh()
            model.selectProject(originalProject)
            panel.setContentSize(originalSize)
        }
        model.refresh()
        model.selectProject(project.id)
        panel.setContentSize(NSSize(width: 600, height: 500))
        try await Task.sleep(nanoseconds: 150_000_000)
        // Lifecycle checks deliberately hand activation to the previous app.
        // Reestablish native focus after those asynchronous handoffs settle.
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(panel.isKeyWindow && NSApp.isActive,
                  "Task click check could not establish native focus (key=\(panel.isKeyWindow), active=\(NSApp.isActive)).")
        panel.contentView?.layoutSubtreeIfNeeded()
        guard let root = panel.contentView,
              let title = descendants(root).compactMap({ $0 as? PlainTextView }).first(where: { $0.editorIdentity == "\(task.id):title" }),
              let ordinaryTitle = descendants(root).compactMap({ $0 as? PlainTextView }).first(where: { $0.editorIdentity == "\(ordinaryTask.id):title" }) else {
            throw harnessError("Collapsed native task title was not mounted.")
        }
        try check(title.string == task.title && title.bounds.height <= Mocha.textRowHeight + 1 && ordinaryTitle.bounds.height <= Mocha.textRowHeight + 1,
                  "Collapsed native titles lost trailing-newline content or reserved an unnecessary text row.")
        let rowDistance = abs(title.convert(title.bounds, to: nil).maxY - ordinaryTitle.convert(ordinaryTitle.bounds, to: nil).maxY)
        try check(abs(rowDistance - 30) <= 1, "Ordinary collapsed task rows lost their existing 30-point spacing.")
        let ordinaryUnselectedWidth = ordinaryTitle.bounds.width
        var eventNumber = 0
        var deliveredEvents: [String] = []
        var diagnoseNextBlank = false
        var blankTrace: [String] = []
        var blankFocusToRestore: (() -> Bool)?
        var installedBlankTrace = false
        let eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { event in
            if event.windowNumber == self.panel.windowNumber {
                deliveredEvents.append("\(event.type)#\(event.eventNumber) at \(NSStringFromPoint(event.locationInWindow))")
                if diagnoseNextBlank, event.type == .leftMouseDown,
                   let region = descendants(root).compactMap({ $0 as? TaskBlankClickRegion }).first(where: { $0.containsBlankPoint(event.locationInWindow) }) {
                    diagnoseNextBlank = false
                    installedBlankTrace = true
                    let originalBlank = region.onBlankClick
                    let originalTitleFocus = title.onTitleFocus
                    blankFocusToRestore = originalTitleFocus
                    title.onTitleFocus = {
                        blankTrace.append("title focus before: \(clickState())")
                        let result = originalTitleFocus?() ?? true
                        blankTrace.append("title focus returned \(result): \(clickState())")
                        return result
                    }
                    region.onBlankClick = { [weak region] in
                        region?.onBlankClick = originalBlank
                        blankTrace.append("clear before: \(clickState())")
                        let result = originalBlank()
                        blankTrace.append("clear returned \(result): \(clickState())")
                        return result
                    }
                }
            }
            return event
        }
        defer { if let eventMonitor { NSEvent.removeMonitor(eventMonitor) } }
        func sendMouse(_ events: [(NSEvent.EventType, NSPoint, Int)]) async throws {
            let timestamp = ProcessInfo.processInfo.systemUptime
            // Queue matching mouse-up/drag events before dispatch. NSTextView's
            // native mouseDown tracking loop consumes them from the app queue.
            for (index, item) in events.enumerated() {
                eventNumber += 1
                guard let event = NSEvent.mouseEvent(with: item.0, location: item.1, modifierFlags: [],
                                                     timestamp: timestamp + Double(index) * 0.02,
                                                     windowNumber: panel.windowNumber, context: nil,
                                                     eventNumber: eventNumber, clickCount: item.2,
                                                     pressure: item.0 == .leftMouseUp ? 0 : 1) else {
                    throw harnessError("Could not create a native task mouse event.")
                }
                NSApp.postEvent(event, atStart: false)
            }
            try await Task.sleep(nanoseconds: 80_000_000)
            root.layoutSubtreeIfNeeded()
        }
        func click(_ point: NSPoint) async throws {
            try await sendMouse([(.leftMouseDown, point, 1), (.leftMouseUp, point, 1)])
        }
        func titlePoint(_ x: CGFloat = 40) -> NSPoint {
            title.convert(NSPoint(x: x, y: title.textContainerInset.height + 8), to: nil)
        }
        func clickState() -> String {
            let responder = (panel.firstResponder as? PlainTextView)?.editorIdentity
                ?? panel.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
            return "selected=\(model.selectedTaskIDs[project.id] ?? "nil"), expanded=\(model.expandedTaskID ?? "nil"), responder=\(responder), marked=\((panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false), key=\(panel.isKeyWindow), active=\(NSApp.isActive), mode=\(RunLoop.current.currentMode?.rawValue ?? "nil")"
        }
        func pointClassification(_ point: NSPoint) -> String {
            let hit = root.hitTest(root.superview?.convert(point, from: nil) ?? point)
            let bars = descendants(root).compactMap { $0 as? TaskBarClickRegion }.filter {
                $0.bounds.contains($0.convert(point, from: nil))
            }.map {
                "task=\($0.taskID), contains=\($0.containsBarPoint(point)), bounds=\(NSStringFromRect($0.convert($0.bounds, to: nil))), visible=\(NSStringFromRect($0.convert($0.visibleRect, to: nil)))"
            }.joined(separator: "; ")
            let blanks = descendants(root).compactMap { $0 as? TaskBlankClickRegion }.map {
                "contains=\($0.containsBlankPoint(point)), exclusions=\($0.excludedRects.count), bounds=\(NSStringFromRect($0.convert($0.bounds, to: nil))), visible=\(NSStringFromRect($0.convert($0.visibleRect, to: nil)))"
            }.joined(separator: "; ")
            return "hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil"), point=\(NSStringFromPoint(point)); bars: \(bars); blanks: \(blanks)"
        }
        var firstClickTrace: [String] = []
        let originalPointerDown = title.onTitlePointerDown
        let originalFocus = title.onTitleFocus
        title.onTitlePointerDown = {
            firstClickTrace.append("pointer before: \(clickState())")
            let result = originalPointerDown?() ?? .editOnly
            firstClickTrace.append("pointer returned \(result): \(clickState())")
            return result
        }
        title.onTitleFocus = {
            firstClickTrace.append("focus before: \(clickState())")
            let result = originalFocus?() ?? true
            firstClickTrace.append("focus returned \(result): \(clickState())")
            return result
        }
        let blank = root.convert(NSPoint(x: root.bounds.midX, y: 36), to: nil)
        let firstClickPoint = titlePoint()
        let beforeFirstClick = clickState()
        let hit = root.hitTest(root.superview?.convert(firstClickPoint, from: nil) ?? firstClickPoint)
        let hitClass = hit.map { String(describing: type(of: $0)) } ?? "nil"
        let regions = descendants(root).compactMap { $0 as? TaskBlankClickRegion }.map {
            "blank=\($0.containsBlankPoint(firstClickPoint)), exclusions=\($0.excludedRects.count), frame=\(NSStringFromRect($0.convert($0.bounds, to: nil)))"
        }.joined(separator: "; ")
        try await click(firstClickPoint)
        try check(model.selectedTaskIDs[project.id] == task.id && model.expandedTaskID == nil && panel.firstResponder === title,
                  "First title click did not select and focus editing without expanding details. Before: \(beforeFirstClick). After: \(clickState()). Hit: \(hitClass); title=\(NSStringFromRect(title.convert(title.bounds, to: nil))); point=\(NSStringFromPoint(firstClickPoint)); regions: \(regions); callbacks: \(firstClickTrace).")
        title.onTitlePointerDown = originalPointerDown
        title.onTitleFocus = originalFocus
        try await click(titlePoint())
        try check(model.expandedTaskID == task.id && descendants(root).contains(where: { $0 === title }),
                  "A second independent title click did not expand details within 80ms while retaining the native title.")
        let detailEditors = descendants(root).compactMap { $0 as? PlainTextView }
        guard let notes = detailEditors.first(where: { $0.editorIdentity == "\(task.id):notes" }),
              let child = detailEditors.first(where: { $0.editorIdentity == "\(subtask.id):title" }),
              let addChild = detailEditors.first(where: { $0.editorIdentity == "add-child:\(task.id)" }) else {
            throw harnessError("Expanded notes and subtask editors were not mounted for row click checks.")
        }
        let notesRect = notes.convert(notes.bounds, to: nil)
        try check(child.convert(child.bounds, to: nil).minY + 1 >= notesRect.maxY && addChild.convert(addChild.bounds, to: nil).minY + 1 >= notesRect.maxY,
                  "Subtask and Add-subtask editors were not positioned above notes.")
        try await click(notes.convert(NSPoint(x: 30, y: notes.textContainerInset.height + 8), to: nil))
        try check(panel.firstResponder === notes && model.expandedTaskID == task.id,
                  "Clicking notes toggled task details or failed to focus its native editor.")
        notes.setSelectedRange(NSRange(location: (notes.string as NSString).length, length: 0))
        notes.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0), replacementRange: notes.selectedRange())
        try await click(NSPoint(x: 8, y: titlePoint().y))
        try check(notes.hasMarkedText() && panel.firstResponder === notes && model.expandedTaskID == task.id,
                  "A task bar click collapsed details or moved focus away from notes during native composition.")
        notes.insertText("あ", replacementRange: NSRange(location: NSNotFound, length: 0))
        try check(model.flushPendingEdits(), "Committing notes composition did not save its draft.")
        try await click(titlePoint())
        try check(model.expandedTaskID == nil && model.selectedTaskIDs[project.id] == task.id,
                  "A later selected title click did not collapse details while retaining row selection.")
        let wordPoint = titlePoint()
        try await sendMouse([(.leftMouseDown, wordPoint, 1), (.leftMouseUp, wordPoint, 1)])
        let expansionAfterFirstClick = model.expandedTaskID
        let selectionAfterFirstClick = title.selectedRange()
        let secondClickPoint = titlePoint()
        let classificationBeforeSecondClick = pointClassification(secondClickPoint)
        try await sendMouse([(.leftMouseDown, secondClickPoint, 2), (.leftMouseUp, secondClickPoint, 2)])
        let textLayout = title.textContainer.map { container in
            "container=\(NSStringFromSize(container.containerSize)), used=\(title.layoutManager.map { NSStringFromRect($0.usedRect(for: container)) } ?? "nil")"
        } ?? "no container"
        try check(title.selectedRange().length > 0 && model.expandedTaskID == expansionAfterFirstClick,
                  "The second constituent of a native double-click toggled details or failed to select text. Before: expanded=\(expansionAfterFirstClick ?? "nil"), selection=\(NSStringFromRange(selectionAfterFirstClick)), firstPoint=\(NSStringFromPoint(wordPoint)), secondPoint=\(NSStringFromPoint(secondClickPoint)); \(classificationBeforeSecondClick). After: \(clickState()), selection=\(NSStringFromRange(title.selectedRange())), mounted=\(descendants(root).contains(where: { $0 === title })), title=\(NSStringFromRect(title.convert(title.bounds, to: nil))), \(textLayout); events=\(deliveredEvents.suffix(6)).")
        title.setSelectedRange(NSRange(location: (title.string as NSString).length, length: 0))
        try await sendMouse([(.leftMouseDown, titlePoint(8), 1), (.leftMouseDragged, titlePoint(92), 1),
                             (.leftMouseUp, titlePoint(92), 1)])
        try check(title.selectedRange().length > 0 && model.expandedTaskID == expansionAfterFirstClick,
                  "Dragging native text selection toggled details or failed to select text.")
        let beforeBlankClick = clickState()
        let blankClassification = pointClassification(blank)
        diagnoseNextBlank = true
        try await click(blank)
        if installedBlankTrace { title.onTitleFocus = blankFocusToRestore }
        try check(model.selectedTaskIDs[project.id] == nil && model.expandedTaskID == nil,
                  "Blank list space outside task bars did not reset selection and collapse details. Before: \(beforeBlankClick). After: \(clickState()); \(blankClassification); callbacks: \(blankTrace); delivered: \(deliveredEvents.suffix(6)).")
        for x in [CGFloat(8), root.bounds.width - 8] {
            let margin = NSPoint(x: x, y: titlePoint().y)
            try await click(margin)
            try check(model.selectedTaskIDs[project.id] == task.id && model.expandedTaskID == nil,
                      "The task bar margin at x=\(x) did not select without expanding. \(clickState()).")
            try await click(margin)
            try check(model.expandedTaskID == task.id,
                      "The selected task bar margin at x=\(x) did not toggle details within 80ms. \(clickState()).")
            try await sendMouse([(.leftMouseDown, margin, 2), (.leftMouseUp, margin, 2)])
            try check(model.selectedTaskIDs[project.id] == task.id && model.expandedTaskID == nil,
                      "A rapid repeated background click at x=\(x) did not toggle the selected task bar.")
            try await click(blank)
            try check(model.selectedTaskIDs[project.id] == nil && model.expandedTaskID == nil,
                      "Blank space outside task bars did not collapse a margin-selected task.")
        }
        try await click(titlePoint())
        try check(model.selectedTaskIDs[project.id] == task.id && model.expandedTaskID == nil,
                  "First click after blank-space reset expanded task details.")
        title.setSelectedRange(NSRange(location: (title.string as NSString).length, length: 0))
        title.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0), replacementRange: title.selectedRange())
        func titleCompositionState() -> String {
            "\(clickState()), title=\(title.string.debugDescription), titleMarked=\(title.hasMarkedText()), titleSelection=\(NSStringFromRange(title.selectedRange())), titleEditable=\(title.isEditable), titleSelectable=\(title.isSelectable), titleWindow=\(title.window?.windowNumber ?? -1), panel=\(panel.windowNumber), keyWindow=\(NSApp.keyWindow?.windowNumber ?? -1), selectedProject=\(model.selectedProjectID), sidebarDocked=\(model.sidebarIsDocked), sidebarOpen=\(model.sidebarDockedOpen), drawerOpen=\(model.sidebarDrawerOpen)"
        }
        let beforeBlankCompositionClick = titleCompositionState()
        try check(title.hasMarkedText() && model.selectedTaskIDs[project.id] == task.id && panel.firstResponder === title,
                  "Could not establish the selected title's native composition before a blank click. \(beforeBlankCompositionClick).")
        try await click(blank)
        try check(title.hasMarkedText() && model.selectedTaskIDs[project.id] == task.id && panel.firstResponder === title,
                  "Blank-space reset discarded a selected title's native composition. Before: \(beforeBlankCompositionClick). After: \(titleCompositionState()); \(pointClassification(blank)); delivered: \(deliveredEvents.suffix(6)).")
        title.insertText("あ", replacementRange: NSRange(location: NSNotFound, length: 0))
        try check(model.flushPendingEdits(), "Committing selected-title composition did not save its draft.")
        _ = try model.store.apply(.patchTask(id: task.id, patch: TaskPatch(completed: FieldChange(expected: false, value: true))))
        model.refresh()
        try await Task.sleep(nanoseconds: 150_000_000)
        root.layoutSubtreeIfNeeded()
        try check(model.isCompletedExpanded(projectID: project.id) && descendants(root).contains(where: { $0 === title }) && panel.firstResponder === title,
                  "External completion hid or replaced the selected collapsed title editor.")
        let completionPoint = title.convert(NSPoint(x: -14, y: 14), to: nil)
        try await click(completionPoint)
        try check(model.selectedProject?.tasks.first?.completed == false && model.expandedTaskID == nil,
                  "The completion control stopped working or toggled details.")
        guard let header = descendants(root).compactMap({ $0 as? HeaderDragView }).first,
              let headerPoint = stride(from: CGFloat(8), to: header.bounds.width - 8, by: CGFloat(8)).map({ NSPoint(x: $0, y: header.bounds.midY) }).first(where: { point in
                  let windowPoint = header.convert(point, to: nil)
                  let hitPoint = root.superview?.convert(windowPoint, from: nil) ?? windowPoint
                  return !header.excludedRects.contains(where: { $0.contains(point) }) && root.hitTest(hitPoint) === header
              }) else { throw harnessError("No blank native header area was available for selection reset.") }
        let headerWindowPoint = header.convert(headerPoint, to: nil)
        let beforeHeaderClick = clickState()
        let headerClassification = pointClassification(headerWindowPoint)
        var headerNotifications = 0
        let headerObserver = NotificationCenter.default.addObserver(forName: HeaderDragView.blankClick, object: panel, queue: nil) { _ in
            headerNotifications += 1
        }
        defer { NotificationCenter.default.removeObserver(headerObserver) }
        // Verify the window's header boundary deterministically. Native control
        // trackers can consume a posted synthetic down before NSWindow dispatch;
        // queue the up for native header tracking, then deliver the down here.
        let headerTimestamp = ProcessInfo.processInfo.systemUptime
        eventNumber += 1
        guard let headerDown = NSEvent.mouseEvent(with: .leftMouseDown, location: headerWindowPoint, modifierFlags: [],
            timestamp: headerTimestamp, windowNumber: panel.windowNumber, context: nil,
            eventNumber: eventNumber, clickCount: 1, pressure: 1) else { throw harnessError("Could not create header mouse-down.") }
        eventNumber += 1
        guard let headerUp = NSEvent.mouseEvent(with: .leftMouseUp, location: headerWindowPoint, modifierFlags: [],
            timestamp: headerTimestamp + 0.02, windowNumber: panel.windowNumber, context: nil,
            eventNumber: eventNumber, clickCount: 1, pressure: 0) else { throw harnessError("Could not create header mouse-up.") }
        NSApp.postEvent(headerUp, atStart: false)
        panel.sendEvent(headerDown)
        try await Task.sleep(nanoseconds: 80_000_000)
        root.layoutSubtreeIfNeeded()
        try check(headerNotifications == 1 && model.selectedTaskIDs[project.id] == nil && model.expandedTaskID == nil,
                  "Blank header space did not reset task selection. Before: \(beforeHeaderClick). After: \(clickState()); \(headerClassification); notifications=\(headerNotifications); delivered: \(deliveredEvents.suffix(6)).")
        try await click(titlePoint())
        try check(model.selectedTaskIDs[project.id] == task.id && model.expandedTaskID == nil,
                  "First title click after header reset expanded details.")
        try await click(ordinaryTitle.convert(NSPoint(x: 40, y: ordinaryTitle.textContainerInset.height + 8), to: nil))
        try check(model.selectedTaskIDs[project.id] == ordinaryTask.id && model.expandedTaskID == nil && ordinaryTitle.bounds.width + 20 < ordinaryUnselectedWidth,
                  "Selecting a task without details did not show its chevron slot.")
        let ordinaryChevron = ordinaryTitle.convert(NSPoint(x: ordinaryTitle.bounds.maxX + 11, y: 14), to: nil)
        try await click(ordinaryChevron)
        try check(model.expandedTaskID == ordinaryTask.id,
                  "The selected task's chevron did not open its empty details.")
    }

    private func exerciseDeadlineMenus(taskID: String) async throws {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        guard let root = panel.contentView,
              model.selectedProject?.tasks.contains(where: { $0.id == taskID }) == true,
              let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                  context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else {
            throw harnessError("Could not prepare deadline menu check.")
        }
        let editors = descendants(root).compactMap { $0 as? PlainTextView }.filter {
            $0.editorIdentity == "\(taskID):title" || $0.editorIdentity == "\(taskID):notes"
        }
        guard editors.count == 2 else { throw harnessError("Deadline title and notes editors were not mounted.") }
        func waitForDeadlinePopup(_ phase: String) async throws -> NSWindow {
            let limit = ProcessInfo.processInfo.systemUptime + 2
            while true {
                if let popup = NSApp.windows.first(where: { window in
                    window !== panel && window.isVisible && window.contentView.map {
                        descendants($0).contains { $0 is NSDatePicker }
                    } == true
                }) { return popup }
                let remaining = limit - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { break }
                try await Task.sleep(nanoseconds: UInt64(min(0.05, remaining) * 1_000_000_000))
            }
            let windows = NSApp.windows.map { window in
                let views = window.contentView.map(descendants) ?? []
                let types = Set(views.map { String(describing: type(of: $0)) }).sorted().joined(separator: "/")
                return "\(type(of: window))#\(window.windowNumber)(visible=\(window.isVisible), key=\(window.isKeyWindow), pickers=\(views.filter { $0 is NSDatePicker }.count), views=\(types))"
            }.joined(separator: "; ")
            let mounted = editors.map { editor in
                "\(editor.editorIdentity)(mounted=\(descendants(root).contains { $0 === editor }), window=\(editor.window?.windowNumber ?? -1), marked=\(editor.hasMarkedText()))"
            }.joined(separator: "; ")
            let composition = (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
            throw harnessError("\(phase) did not open its native date and time picker within 2 seconds. error=\(model.errorMessage ?? "nil"), composition=\(composition), storeAvailable=\(model.isStoreAvailable), listAvailable=\(model.isSelectedListAvailable), listIssue=\(String(describing: model.selectedListIssue)), active=\(NSApp.isActive), keyWindow=\(NSApp.keyWindow?.windowNumber ?? -1), editors=[\(mounted)], windows=[\(windows)].")
        }
        for editor in editors {
            guard let menu = editor.menu(for: event),
                  let item = menu.items.first(where: { $0.title == "Set deadline…" }),
                  editor.validateUserInterfaceItem(item) else {
                throw harnessError("Right-click deadline action was missing or disabled on \(editor.editorIdentity).")
            }
        }
        guard let set = editors[0].menu(for: event)?.items.first(where: { $0.title == "Set deadline…" }),
              let setAction = set.action, NSApp.sendAction(setAction, to: set.target, from: set) else {
            throw harnessError("Native Set deadline action could not be invoked.")
        }
        let popup = try await waitForDeadlinePopup("Set deadline")
        guard let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: popup.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else {
            throw harnessError("Could not prepare deadline Cancel key event.")
        }
        NSApp.sendEvent(escape)
        try await Task.sleep(nanoseconds: 100_000_000)
        guard !popup.isVisible,
              model.selectedProject?.tasks.first(where: { $0.id == taskID })?.deadline == nil else {
            throw harnessError("Cancelling the deadline picker did not dismiss without saving.")
        }
        guard NSApp.sendAction(setAction, to: set.target, from: set) else {
            throw harnessError("Could not reopen the deadline picker after Cancel.")
        }
        let savePopup = try await waitForDeadlinePopup("Reopening deadline after Cancel")
        guard let popupRoot = savePopup.contentView,
              let picker = descendants(popupRoot).compactMap({ $0 as? NSDatePicker }).first else {
            throw harnessError("Could not prepare deadline Save check: its native date picker was not mounted.")
        }
        let expected = Date(timeIntervalSince1970: floor(picker.dateValue.timeIntervalSince1970 / 60) * 60)
        // Route the default action as a key equivalent, without sending Return
        // through the focused date field's text-editing path.
        guard let saveKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: savePopup.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36),
              savePopup.performKeyEquivalent(with: saveKey) else {
            throw harnessError("The deadline picker did not handle its Save key equivalent.")
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        guard !savePopup.isVisible,
              let savedTask = model.selectedProject?.tasks.first(where: { $0.id == taskID }),
              savedTask.deadline == expected else {
            throw harnessError("Saving the deadline picker did not persist the displayed date and time (visible=\(savePopup.isVisible), expected=\(expected), saved=\(String(describing: model.selectedProject?.tasks.first(where: { $0.id == taskID })?.deadline))).")
        }
        let deadline = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 60)
        guard model.setDeadline(deadline, for: savedTask, projectID: model.selectedProjectID) else {
            throw harnessError("Could not set smoke task deadline.")
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        for editor in editors {
            guard let menu = editor.menu(for: event),
                  menu.items.contains(where: { $0.title == "Edit deadline…" }),
                  let remove = menu.items.first(where: { $0.title == "Remove deadline" }),
                  editor.validateUserInterfaceItem(remove) else {
                throw harnessError("A saved deadline did not update the native context menu.")
            }
        }
        guard let current = model.selectedProject?.tasks.first(where: { $0.id == taskID }),
              model.isOverdue(current, projectID: model.selectedProjectID),
              model.hasOverdueTasks(projectID: model.selectedProjectID),
              let staleRemove = editors[0].menu(for: event)?.items.first(where: { $0.title == "Remove deadline" }),
              let action = staleRemove.action else {
            throw harnessError("The overdue state or native Remove deadline action was missing.")
        }
        let updatedDeadline = deadline.addingTimeInterval(3600)
        _ = try model.store.apply(.patchTask(id: taskID, patch: TaskPatch(deadline: FieldChange(expected: deadline, value: updatedDeadline))),
                                  owningListID: model.selectedProjectID)
        model.refresh()
        try await Task.sleep(nanoseconds: 100_000_000)
        guard NSApp.sendAction(action, to: staleRemove.target, from: staleRemove),
              model.selectedProject?.tasks.first(where: { $0.id == taskID })?.deadline == updatedDeadline,
              model.errorMessage != nil else {
            throw harnessError("An open native deadline menu overwrote a concurrent deadline change.")
        }
        guard let remove = editors[0].menu(for: event)?.items.first(where: { $0.title == "Remove deadline" }),
              NSApp.sendAction(action, to: remove.target, from: remove),
              model.selectedProject?.tasks.first(where: { $0.id == taskID })?.deadline == nil else {
            throw harnessError("The refreshed native Remove deadline action failed.")
        }
        print("Deadline native menus passed for task titles and notes, including picker Save, Cancel, removal, and a concurrent change while the menu was open.")
    }

    private func exerciseNativeEditor(taskID: String, title: String) async throws {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func check(_ value: Bool, _ message: String) throws { if !value { throw harnessError(message) } }
        // The preceding deadline check uses a transient popover. Restore the
        // editor's window before testing first-responder command dispatch.
        panel.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 100_000_000)
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
        try check(NSApp.sendAction(Selector(("undo:")), to: nil, from: delegate), "Native responder rejected Undo.")
        try check(editor.string == title && model.text(itemID: taskID, field: .title, fallback: title) == title, "Native text Undo did not restore the draft (editor=\(editor.string), draft=\(model.text(itemID: taskID, field: .title, fallback: title))).")
        try check(NSApp.sendAction(Selector(("redo:")), to: nil, from: delegate), "Native responder rejected Redo.")
        try check(editor.string == typed, "Native text Redo did not restore the edit.")
        let originalSize = panel.contentRect(forFrameRect: panel.frame).size
        let originalSidebarOpen = model.sidebarDockedOpen
        let originalSidebarWidth = model.sidebarWidth
        defer {
            model.dismissSidebarDrawer()
            model.setSidebarWidth(originalSidebarWidth)
            if model.sidebarDockedOpen != originalSidebarOpen {
                model.updateSidebarLayout(availableWidth: 900)
                _ = model.toggleSidebar()
            }
            panel.setContentSize(originalSize)
            model.updateSidebarLayout(availableWidth: originalSize.width)
        }
        editor.breakUndoCoalescing()
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.insertText("\nResize this multiline title while keeping its native editor, selection, and Undo history intact. The following notes must stay below every wrapped line.", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        panel.setContentSize(NSSize(width: 320, height: 600))
        try await Task.sleep(nanoseconds: 150_000_000)
        panel.contentView?.layoutSubtreeIfNeeded()
        guard let notes = descendants(root).compactMap({ $0 as? PlainTextView }).first(where: { $0.editorIdentity == "\(taskID):notes" }),
              let container = editor.textContainer, let layout = editor.layoutManager else {
            throw harnessError("Native editor resize check could not find its notes or text layout.")
        }
        func checkEditorLayout() throws {
            layout.ensureLayout(for: container)
            try check(abs(container.containerSize.width - editor.bounds.width) < 1,
                      "Rendered text width did not track its editor frame after resize.")
            let requiredHeight = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY) + 2 * editor.textContainerInset.height
            try check(editor.bounds.height + 1 >= requiredHeight, "Multiline editor height does not contain its rendered text.")
            let titleBounds = editor.convert(editor.bounds, to: nil)
            let notesBounds = notes.convert(notes.bounds, to: nil)
            try check(titleBounds.minY + 1 >= notesBounds.maxY, "Multiline title overlaps the following notes editor.")
        }
        try checkEditorLayout()
        let narrowWidth = editor.bounds.width
        let narrowHeight = editor.bounds.height
        let resizeSelection = editor.selectedRange()
        panel.setContentSize(NSSize(width: 600, height: 600))
        try await Task.sleep(nanoseconds: 150_000_000)
        panel.contentView?.layoutSubtreeIfNeeded()
        try checkEditorLayout()
        try check(editor.bounds.width > narrowWidth + 200 && editor.bounds.height < narrowHeight,
                  "Widening the panel did not expand and reflow the existing editor.")
        try check(descendants(root).contains(where: { $0 === editor }) && panel.firstResponder === editor && editor.selectedRange() == resizeSelection,
                  "Resizing replaced the native editor or disrupted focus and selection.")
        try check(editor.localUndo.canUndo, "Resizing discarded native Undo history.")
        editor.localUndo.undo()
        try check(editor.string == typed, "Undo after resizing did not restore the native title.")
        editor.setSelectedRange(NSRange(location: 3, length: 4))
        let sidebarSelection = editor.selectedRange()
        func checkSidebarEditor(_ phase: String, focused: Bool = true) throws {
            try check(descendants(root).contains(where: { $0 === editor }) && editor.window === panel &&
                      editor.selectedRange() == sidebarSelection && (!focused || panel.firstResponder === editor),
                      "\(phase) replaced the task editor or changed its focus and selection.")
            try check(editor.localUndo.canUndo, "\(phase) discarded native Undo history.")
        }
        panel.setContentSize(NSSize(width: 900, height: 600))
        model.updateSidebarLayout(availableWidth: 900)
        if !model.sidebarDockedOpen { _ = model.toggleSidebar() }
        try await Task.sleep(nanoseconds: 100_000_000)
        root.layoutSubtreeIfNeeded()
        let dockedEditorWidth = editor.bounds.width
        try checkSidebarEditor("Docking the sidebar")
        try check(model.toggleSidebar() && !model.sidebarDockedOpen, "The docked sidebar did not hide.")
        try await Task.sleep(nanoseconds: 100_000_000)
        root.layoutSubtreeIfNeeded()
        try check(editor.bounds.width > dockedEditorWidth + 150, "Hiding the docked sidebar did not return its space to the task editor.")
        try checkSidebarEditor("Hiding the docked sidebar")
        try check(model.toggleSidebar() && model.sidebarDockedOpen, "The docked sidebar did not reopen.")
        model.setSidebarWidth(320)
        try await Task.sleep(nanoseconds: 100_000_000)
        root.layoutSubtreeIfNeeded()
        try checkSidebarEditor("Reopening and resizing the docked sidebar")
        model.setSidebarWidth(originalSidebarWidth)
        panel.setContentSize(NSSize(width: 424, height: 600))
        model.updateSidebarLayout(availableWidth: 424)
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(model.showSidebarDrawer() && model.sidebarDrawerOpen, "The narrow sidebar drawer did not open.")
        try await Task.sleep(nanoseconds: 100_000_000)
        root.layoutSubtreeIfNeeded()
        try checkSidebarEditor("Opening the narrow sidebar drawer", focused: false)
        try check(!editor.isEditable && !editor.isSelectable, "The open sidebar drawer left native task editing enabled behind it.")
        guard let drawerEscape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else {
            throw harnessError("Could not prepare sidebar drawer Escape event.")
        }
        panel.sendEvent(drawerEscape)
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(!model.sidebarDrawerOpen && editor.isEditable && editor.isSelectable,
                  "Escape did not dismiss the sidebar drawer and restore task editing.")
        try checkSidebarEditor("Dismissing the sidebar drawer with Escape")
        try check(model.showSidebarDrawer(), "The sidebar drawer did not reopen after Escape.")
        try await Task.sleep(nanoseconds: 100_000_000)
        let outsidePoint = editor.convert(NSPoint(x: editor.bounds.maxX - 4, y: editor.bounds.midY), to: nil)
        guard let outsideDown = NSEvent.mouseEvent(with: .leftMouseDown, location: outsidePoint, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else {
            throw harnessError("Could not prepare sidebar drawer outside click.")
        }
        panel.sendEvent(outsideDown)
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(!model.sidebarDrawerOpen, "Clicking outside the narrow sidebar drawer did not dismiss it.")
        try checkSidebarEditor("Dismissing the sidebar drawer with an outside click")
        panel.setContentSize(originalSize)
        model.updateSidebarLayout(availableWidth: originalSize.width)
        try await Task.sleep(nanoseconds: 100_000_000)
        func currentPublishedTitle() throws -> String {
            guard let current = model.selectedProject?.tasks.first(where: { $0.id == taskID }) else {
                throw harnessError("The native composition task disappeared.")
            }
            // Sidebar focus changes can save the draft. AppModel.text returns
            // this fallback once saved, so it must be the current task title.
            return model.text(itemID: taskID, field: .title, fallback: current.title,
                              projectID: model.selectedProjectID)
        }
        let beforeComposition = try currentPublishedTitle()
        try check(beforeComposition == typed && editor.string == typed,
                  "The native composition baseline changed (expected=\(typed.debugDescription), published=\(beforeComposition.debugDescription), editor=\(editor.string.debugDescription)).")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
        try check(editor.hasMarkedText(), "Could not establish native marked composition.")
        let markedSelection = editor.selectedRange()
        panel.setContentSize(NSSize(width: 900, height: originalSize.height))
        model.updateSidebarLayout(availableWidth: 900)
        try await Task.sleep(nanoseconds: 100_000_000)
        panel.contentView?.layoutSubtreeIfNeeded()
        try check(editor.hasMarkedText() && editor.selectedRange() == markedSelection && panel.firstResponder === editor,
                  "Resizing into the docked sidebar layout disrupted native marked composition.")
        try check(model.toggleSidebar(), "The docked sidebar could not hide during native composition.")
        try check(model.toggleSidebar(), "The docked sidebar could not reopen during native composition.")
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(editor.hasMarkedText() && editor.selectedRange() == markedSelection && panel.firstResponder === editor,
                  "Hiding and showing the docked sidebar disrupted native marked composition.")
        panel.setContentSize(originalSize)
        model.updateSidebarLayout(availableWidth: originalSize.width)
        if !model.sidebarIsDocked {
            try check(!model.showSidebarDrawer() && !model.sidebarDrawerOpen && editor.hasMarkedText() && panel.firstResponder === editor,
                      "Opening the narrow drawer interrupted native marked composition.")
        }
        let publishedDuringComposition = try currentPublishedTitle()
        let persistedDuringComposition = try model.store.load().projects.flatMap(\.tasks).first(where: { $0.id == taskID })?.title
        try check(publishedDuringComposition == typed && persistedDuringComposition == typed,
                  "Provisional composition changed published or persisted text (expected=\(typed.debugDescription), published=\(publishedDuringComposition.debugDescription), persisted=\(String(describing: persistedDuringComposition)), editor=\(editor.string.debugDescription), marked=\(editor.hasMarkedText()), selection=\(editor.selectedRange())).")
        try check(!delegate.hidePanel() && panel.isVisible, "Marked composition did not prevent hide.")
        try check(delegate.applicationShouldTerminate(NSApp) == .terminateCancel, "Marked composition did not prevent normal quit.")
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

}

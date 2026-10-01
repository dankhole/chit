import AppKit
import SwiftUI
import TodoCore

struct TaskDragPayload: Codable, Equatable {
    let workspaceScope: String
    let projectID: String
    let taskID: String
    let completed: Bool
    let expectedOrder: [String]
}

@MainActor
final class TaskDragState: ObservableObject {
    @Published private(set) var payload: TaskDragPayload?
    @Published var hoveredTarget: AppModel.TaskDropTarget?

    @discardableResult
    func begin(task: TaskItem, projectID: String, model: AppModel) -> TaskDragPayload? {
        guard model.canStartTaskDrag(projectID: projectID),
              let project = model.workspace.projects.first(where: { $0.id == projectID }),
              let current = project.tasks.first(where: { $0.id == task.id }),
              current.completed == task.completed else { return nil }
        let payload = TaskDragPayload(workspaceScope: model.taskDragScope, projectID: projectID,
            taskID: task.id, completed: task.completed,
            expectedOrder: project.tasks.filter { $0.completed == task.completed }.map(\.id))
        self.payload = payload
        hoveredTarget = nil
        return payload
    }

    func finish() {
        hoveredTarget = nil
        payload = nil
    }
}

/// The source view covers only the grip. The destination view covers the row,
/// but participates in hit testing solely while a task drag is active.
struct TaskDragHandle: NSViewRepresentable {
    let model: AppModel
    let state: TaskDragState
    let task: TaskItem
    let projectID: String
    var isSource = false

    func makeNSView(context: Context) -> TaskDragView {
        let view = TaskDragView()
        view.registerForDraggedTypes([TaskDragView.pasteboardType])
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: TaskDragView, context: Context) {
        view.model = model
        view.dragState = state
        view.task = task
        view.projectID = projectID
        view.isSource = isSource
        view.toolTip = isSource ? "Drag to reorder task" : nil
        view.window?.invalidateCursorRects(for: view)
    }
}

final class TaskDragView: NSView, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("local.dcole.tottodo.task")
    weak var model: AppModel?
    weak var dragState: TaskDragState?
    var task: TaskItem?
    var projectID = ""
    var isSource = false
    private var lastTarget: AppModel.TaskDropTarget?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        if isSource { addCursorRect(bounds, cursor: .openHand) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            return nil
        }
        guard isSource || dragState?.payload != nil else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard isSource, let window else { return }
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp { return }
            guard hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) >= 4,
                  let task, let model, let dragState else { continue }
            guard let payload = dragState.begin(task: task, projectID: projectID, model: model),
                  let data = try? JSONEncoder().encode(payload) else { return }
            let writer = NSPasteboardItem()
            writer.setData(data, forType: Self.pasteboardType)
            let item = NSDraggingItem(pasteboardWriter: writer)
            let title = model.text(itemID: task.id, field: .title, fallback: task.title, projectID: projectID)
            item.setDraggingFrame(NSRect(x: 0, y: 0, width: 220, height: 30), contents: dragImage(for: title))
            NSCursor.closedHand.set()
            let session = beginDraggingSession(with: [item], event: next, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
            return
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragState?.finish()
        window?.invalidateCursorRects(for: self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDrop(pasteboard: sender.draggingPasteboard, location: convert(sender.draggingLocation, from: nil))
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        if !isSource, let event = NSApp.currentEvent { _ = autoscroll(with: event) }
        return updateDrop(pasteboard: sender.draggingPasteboard, location: location)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if dragState?.hoveredTarget == lastTarget { dragState?.hoveredTarget = nil }
        lastTarget = nil
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        acceptedPayload(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        performDrop(pasteboard: sender.draggingPasteboard, location: convert(sender.draggingLocation, from: nil))
    }

    @discardableResult
    func performDrop(pasteboard: NSPasteboard, location: NSPoint) -> Bool {
        guard let payload = acceptedPayload(from: pasteboard), let model,
              let target = dropTarget(at: location),
              let current = model.workspace.projects.first(where: { $0.id == projectID })?.tasks.first(where: { $0.id == payload.taskID }) else {
            dragState?.finish()
            return false
        }
        let succeeded = model.moveTask(current, projectID: payload.projectID, to: target, expectedOrder: payload.expectedOrder)
        dragState?.finish()
        return succeeded
    }

    func acceptedPayload(from pasteboard: NSPasteboard) -> TaskDragPayload? {
        guard let model, model.canStartTaskDrag(projectID: projectID), let task,
              let active = dragState?.payload,
              let data = pasteboard.data(forType: Self.pasteboardType),
              let payload = try? JSONDecoder().decode(TaskDragPayload.self, from: data),
              payload == active, payload.workspaceScope == model.taskDragScope,
              payload.projectID == projectID, payload.completed == task.completed,
              let project = model.workspace.projects.first(where: { $0.id == projectID }),
              project.tasks.first(where: { $0.id == task.id })?.completed == payload.completed,
              project.tasks.first(where: { $0.id == payload.taskID })?.completed == payload.completed else { return nil }
        return payload
    }

    @discardableResult
    func updateDrop(pasteboard: NSPasteboard, location: NSPoint) -> NSDragOperation {
        guard acceptedPayload(from: pasteboard) != nil, let target = dropTarget(at: location) else {
            draggingExited(nil)
            return []
        }
        lastTarget = target
        if dragState?.hoveredTarget != target { dragState?.hoveredTarget = target }
        return .move
    }

    private func dropTarget(at location: NSPoint) -> AppModel.TaskDropTarget? {
        guard let task, task.id != dragState?.payload?.taskID else { return nil }
        return location.y < bounds.midY ? .before(task.id) : .after(task.id)
    }

    private func dragImage(for title: String) -> NSImage {
        NSImage(size: NSSize(width: 220, height: 30), flipped: false) { rect in
            Mocha.nsSelection.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            (title.replacingOccurrences(of: "\n", with: " ") as NSString).draw(in: rect.insetBy(dx: 9, dy: 7), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Mocha.nsText, .paragraphStyle: paragraph
            ])
            return true
        }
    }
}

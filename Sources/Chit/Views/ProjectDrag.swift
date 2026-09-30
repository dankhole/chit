import AppKit
import SwiftUI
import TodoCore

struct ProjectDragPayload: Codable, Equatable {
    let workspaceScope: String
    let projectID: String
    let sourceGroupID: String?
    let expectedOrder: [String]
}

@MainActor
final class ProjectDragState: ObservableObject {
    @Published private(set) var payload: ProjectDragPayload?
    @Published var hoveredTarget: AppModel.ProjectDropTarget?

    @discardableResult
    func begin(project: Project, model: AppModel) -> ProjectDragPayload {
        let payload = ProjectDragPayload(workspaceScope: model.projectDragScope,
            projectID: project.id, sourceGroupID: project.groupID,
            expectedOrder: model.workspace.projects.map(\.id))
        self.payload = payload
        hoveredTarget = nil
        return payload
    }

    func finish() {
        hoveredTarget = nil
        payload = nil
    }
}

enum ProjectDragDestination: Equatable {
    case tab(String)
    case group(String?)
}

/// Native drag lifecycle reliably removes temporary targets even after Escape or
/// a drop outside this window. The SwiftUI button beneath supplies keyboard/AX.
struct ProjectDragHandle: NSViewRepresentable {
    let model: AppModel
    let state: ProjectDragState
    var sourceProject: Project? = nil
    let destination: ProjectDragDestination
    let onClick: () -> Void
    var tooltip: String? = nil

    func makeNSView(context: Context) -> ProjectDragView {
        let view = ProjectDragView()
        view.registerForDraggedTypes([ProjectDragView.pasteboardType])
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: ProjectDragView, context: Context) {
        view.model = model
        view.dragState = state
        view.sourceProject = sourceProject
        view.destination = destination
        view.onClick = onClick
        view.toolTip = tooltip
    }
}

final class ProjectDragView: NSView, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("local.dcole.tottodo.project")
    weak var model: AppModel?
    weak var dragState: ProjectDragState?
    var sourceProject: Project?
    var destination: ProjectDragDestination = .group(nil)
    var onClick: () -> Void = {}
    private var lastTarget: AppModel.ProjectDropTarget?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Leave contextual clicks with the SwiftUI button beneath this overlay.
        if let event = NSApp.currentEvent,
           event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            return nil
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp {
                if bounds.contains(convert(next.locationInWindow, from: nil)) { onClick() }
                return
            }
            guard hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) >= 4,
                  let project = sourceProject, let model, let dragState,
                  model.isStoreAvailable else { continue }
            let payload = dragState.begin(project: project, model: model)
            guard let data = try? JSONEncoder().encode(payload) else { dragState.finish(); return }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(data, forType: Self.pasteboardType)
            let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
            item.setDraggingFrame(bounds, contents: dragImage(for: project.name))
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
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }

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

    /// Shared with the native harness: decode and validate the real pasteboard
    /// payload before using the exact same destination/model path as a live drop.
    @discardableResult
    func performDrop(pasteboard: NSPasteboard, location: NSPoint) -> Bool {
        guard let payload = acceptedPayload(from: pasteboard), let model,
              let target = dropTarget(at: location),
              let current = model.workspace.projects.first(where: { $0.id == payload.projectID }) else { return false }
        let source = Project(id: current.id, name: current.name, groupID: payload.sourceGroupID)
        let succeeded = model.moveProject(source, to: target, expectedOrder: payload.expectedOrder)
        dragState?.finish()
        return succeeded
    }

    func acceptedPayload(from pasteboard: NSPasteboard) -> ProjectDragPayload? {
        guard let model, let active = dragState?.payload,
              let data = pasteboard.data(forType: Self.pasteboardType),
              let payload = try? JSONDecoder().decode(ProjectDragPayload.self, from: data),
              payload == active, payload.workspaceScope == model.projectDragScope,
              model.workspace.projects.contains(where: { $0.id == payload.projectID }) else { return nil }
        return payload
    }

    private func updateDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptedPayload(from: sender.draggingPasteboard) != nil,
              let target = dropTarget(at: convert(sender.draggingLocation, from: nil)) else {
            draggingExited(sender)
            return []
        }
        lastTarget = target
        if dragState?.hoveredTarget != target { dragState?.hoveredTarget = target }
        return .move
    }

    private func dropTarget(at location: NSPoint) -> AppModel.ProjectDropTarget? {
        guard let model else { return nil }
        switch destination {
        case .tab(let projectID):
            guard projectID != dragState?.payload?.projectID,
                  model.workspace.projects.contains(where: { $0.id == projectID }) else { return nil }
            return location.x < bounds.midX ? .before(projectID) : .after(projectID)
        case .group(let groupID):
            guard groupID == nil || model.workspace.groups.contains(where: { $0.id == groupID }) else { return nil }
            return .group(groupID)
        }
    }

    private func dragImage(for name: String) -> NSImage {
        NSImage(size: bounds.size, flipped: false) { rect in
            Mocha.nsSelection.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            (name as NSString).draw(in: rect.insetBy(dx: 7, dy: 5), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Mocha.nsText
            ])
            return true
        }
    }
}

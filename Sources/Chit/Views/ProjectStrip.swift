import AppKit
import SwiftUI
import TodoCore

struct ProjectStrip: View {
    @ObservedObject var model: AppModel
    var onNewList: (String?) -> Void
    @StateObject private var dragState = ProjectDragState()
    @State private var form: NameForm?
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @State private var interactiveFrames: [CGRect] = []

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            PanelCloseControl()
                .frame(width: 22, height: 26)
                .background(HeaderControlBounds())
            if LabEnvironment.isEnabled {
                Text("LAB")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Mocha.secondary)
                    .frame(height: 26)
                    .padding(.trailing, 4)
                    .help("Chit Lab · disposable session")
                    .accessibilityLabel("Chit Lab, disposable session")
            }
            WrappingStrip {
                ForEach(model.workspace.projects.filter { $0.groupID == nil }) { project in
                    projectTab(project)
                }
                ForEach(model.workspace.groups) { group in
                    groupLabel(group)
                    if !model.collapsedGroupIDs.contains(group.id) {
                        ForEach(model.workspace.projects.filter { $0.groupID == group.id }) { project in
                            projectTab(project)
                        }
                    }
                }
                if dragState.payload != nil { ungroupTarget }
            }
            Menu {
                Menu("New List") {
                    NewListDestinationOptions(model: model) { onNewList(nil) }
                }
                Button("Open List…") { ListActions.open(model: model) }
                Button("New Group…") { show(.newGroup) }
                if let project = model.selectedProject {
                    Divider()
                    Menu("Current List: \(project.name)") { projectActions(project) }
                }
                if !model.workspace.groups.isEmpty {
                    Menu("Groups") {
                        ForEach(model.workspace.groups) { group in
                            Menu(group.name) { groupActions(group) }
                        }
                    }
                }
                Divider()
                Button("Undo") { model.undo() }.disabled(!model.canUndo)
                Button("Redo") { model.redo() }.disabled(!model.canRedo)
            } label: {
                Image(systemName: "plus").font(.system(size: 13)).frame(width: 22, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 22, height: 26, alignment: .center)
            .accessibilityLabel("Lists and groups")
            .help("Create and manage lists and groups")
            .disabled(!model.isStoreAvailable)
            .background(HeaderControlBounds())
            .popover(isPresented: Binding(get: { form != nil }, set: { if !$0 { form = nil } }), arrowEdge: .bottom) {
                if let form {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(form.heading).font(.system(size: 13, weight: .semibold))
                        TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                            .onSubmit(saveName)
                            .focused($nameFocused)
                            .accessibilityLabel(form.heading + " name")
                        HStack {
                            Button("Cancel") { self.form = nil }.keyboardShortcut(.cancelAction)
                            Spacer()
                            Button(form.isNew ? "Create" : "Rename", action: saveName)
                                .keyboardShortcut(.defaultAction)
                                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(12).frame(width: 248)
                    .preferredColorScheme(.dark)
                    .onAppear { nameFocused = true }
                }
            }
        }
        .coordinateSpace(name: "project-header")
        .onPreferenceChange(HeaderControlFrames.self) { interactiveFrames = $0 }
        .background { HeaderDragArea(excludedRects: interactiveFrames) }
        .font(.system(size: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lists")
    }

    private func projectTab(_ project: Project) -> some View {
        Button { model.selectProject(project.id) } label: {
            HStack(spacing: 4) {
                if isExternal(project.id) { folderGlyph }
                Text(project.name)
            }
                .fontWeight(model.selectedProjectID == project.id ? .semibold : .regular)
                .foregroundStyle(model.selectedProjectID == project.id ? Mocha.blue : Mocha.text)
                .padding(.horizontal, 7).padding(.vertical, 6)
                .background(model.selectedProjectID == project.id ? Mocha.selected : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locationDescription(project))
        .help(locationDescription(project))
        .accessibilityAddTraits(model.selectedProjectID == project.id ? .isSelected : [])
        .overlay {
            ProjectDragHandle(model: model, state: dragState, sourceProject: project,
                destination: .tab(project.id), onClick: { model.selectProject(project.id) },
                tooltip: locationDescription(project))
        }
        .overlay(alignment: .leading) {
            if dragState.hoveredTarget == .before(project.id) { insertionMark }
        }
        .overlay(alignment: .trailing) {
            if dragState.hoveredTarget == .after(project.id) { insertionMark }
        }
        .contextMenu { projectActions(project) }
        .background(HeaderControlBounds())
    }

    private func groupLabel(_ group: ProjectGroup) -> some View {
        let collapsed = model.collapsedGroupIDs.contains(group.id)
        let selected = model.selectedProject
        let active = collapsed && selected?.groupID == group.id ? selected : nil
        let label = active.map { "\(group.name) · \($0.name)" } ?? group.name
        return Button { model.toggleGroup(group.id) } label: {
            HStack(spacing: 4) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .medium))
                Text(group.name).fixedSize(horizontal: false, vertical: true)
                if let active {
                    Text("·")
                    if isExternal(active.id) { folderGlyph }
                    Text(active.name).fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(collapsed && selected?.groupID == group.id ? Mocha.blue : Mocha.secondary)
            .padding(.horizontal, 5).padding(.vertical, 6)
            .background(dragState.hoveredTarget == .group(group.id) ? Mocha.selected : Color.clear,
                in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active.map { "\(group.name), \(locationDescription($0))" } ?? label)
        .help(active.map(locationDescription) ?? group.name)
        .accessibilityValue(collapsed ? "Collapsed group" : "Expanded group")
        .accessibilityHint(collapsed ? "Expand to show lists" : "Collapse lists")
        .overlay {
            ProjectDragHandle(model: model, state: dragState, destination: .group(group.id),
                onClick: { model.toggleGroup(group.id) }, tooltip: active.map(locationDescription) ?? group.name)
        }
        .contextMenu { groupActions(group) }
        .background(HeaderControlBounds())
    }

    private var insertionMark: some View {
        Capsule().fill(Mocha.blue).frame(width: 2, height: 18).allowsHitTesting(false)
    }

    private var ungroupTarget: some View {
        Text("Ungroup").foregroundStyle(Mocha.secondary)
            .padding(.horizontal, 7).padding(.vertical, 6)
            .background(dragState.hoveredTarget == .group(nil) ? Mocha.selected : Mocha.hover,
                in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                ProjectDragHandle(model: model, state: dragState, destination: .group(nil), onClick: {})
            }
            .accessibilityLabel("Move dragged list out of its group")
            .background(HeaderControlBounds())
    }

    @ViewBuilder private func projectActions(_ project: Project) -> some View {
        Button("Rename List…") { show(.renameProject(project)) }
            .disabled(model.issue(for: project.id) != nil)
        if let location = model.location(for: project.id) {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([location.url]) }
                .disabled(model.issue(for: project.id)?.isMissing == true)
            Button("Copy File Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(location.url.path, forType: .string)
            }
            Button("Copy Agent Instructions") { ListActions.copyAgentInstructions(for: location.url) }
            Button("Move File…") { ListActions.move(project, model: model) }
                .disabled(model.issue(for: project.id) != nil)
            if model.issue(for: project.id) != nil {
                Button("Locate List…") { ListActions.locate(project, model: model) }
                Button("Retry") { model.refresh() }
            }
        }
        Divider()
        Button("Move Left") { model.moveProject(project, offset: -1) }
            .disabled(!model.canMoveProject(project, offset: -1))
        Button("Move Right") { model.moveProject(project, offset: 1) }
            .disabled(!model.canMoveProject(project, offset: 1))
        Menu("Move to Group") {
            Button(project.groupID == nil ? "✓ Ungrouped" : "Ungrouped") { model.moveProject(project, groupID: nil) }
            ForEach(model.workspace.groups) { group in
                Button(project.groupID == group.id ? "✓ \(group.name)" : group.name) { model.moveProject(project, groupID: group.id) }
            }
        }
        Divider()
        Button("Hide List") { _ = model.removeList(id: project.id) }
        Button("Delete List…") { ListActions.delete(project, model: model) }
            .disabled(model.location(for: project.id) == nil || model.issue(for: project.id) != nil)
        if model.issue(for: project.id) != nil {
            Text("Locate or retry the file before deleting.")
        }
    }

    private var folderGlyph: some View {
        Image(systemName: "folder")
            .font(.system(size: 10))
            .foregroundStyle(Mocha.secondary.opacity(0.7))
            .accessibilityHidden(true)
    }

    private func isExternal(_ id: String) -> Bool {
        model.location(for: id).map { !$0.isManaged } ?? false
    }

    private func locationDescription(_ project: Project) -> String {
        guard let location = model.location(for: project.id) else { return project.name }
        return "\(project.name), \(location.isManaged ? "saved in app" : "saved in folder"), \(location.url.path)"
    }

    @ViewBuilder private func groupActions(_ group: ProjectGroup) -> some View {
        Button(model.collapsedGroupIDs.contains(group.id) ? "Expand group" : "Collapse group") { model.toggleGroup(group.id) }
        Menu("New List in Group") {
            NewListDestinationOptions(model: model, groupID: group.id) { onNewList(group.id) }
        }
        Button("Open List in Group…") { ListActions.open(model: model, groupID: group.id) }
        Button("Rename Group…") { show(.renameGroup(group)) }
        Divider()
        Button("Remove Group; Keep Lists", role: .destructive) { model.deleteGroup(group) }
    }

    private func show(_ form: NameForm) {
        name = form.name
        self.form = form
    }

    private func saveName() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let form else { return }
        switch form {
        case .newGroup: model.createGroup(name: clean)
        case .renameProject(let project): model.renameProject(project, name: clean)
        case .renameGroup(let group): model.renameGroup(group, name: clean)
        }
        if model.errorMessage == nil { self.form = nil }
    }
}

private struct HeaderControlFrames: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value.append(contentsOf: nextValue()) }
}

private struct HeaderControlBounds: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: HeaderControlFrames.self,
                value: [geometry.frame(in: .named("project-header"))])
        }
        .allowsHitTesting(false)
    }
}

private enum NameForm {
    case newGroup, renameProject(Project), renameGroup(ProjectGroup)
    var heading: String {
        switch self {
        case .newGroup: return "New Group"
        case .renameProject: return "Rename List"
        case .renameGroup: return "Rename Group"
        }
    }
    var name: String {
        switch self {
        case .renameProject(let project): return project.name
        case .renameGroup(let group): return group.name
        default: return ""
        }
    }
    var isNew: Bool {
        switch self { case .newGroup: return true; default: return false }
    }
}

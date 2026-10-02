import AppKit
import SwiftUI
import TodoCore

/// A stable header keeps the active list and window controls available even
/// when the navigation sidebar is closed.
struct ProjectHeader: View {
    @ObservedObject var model: AppModel
    let sidebarVisible: Bool
    var onToggleSidebar: () -> Void
    var onNewList: (String?) -> Void
    @State private var form: ProjectNameForm?
    @State private var interactiveFrames: [CGRect] = []

    var body: some View {
        let drawerOpen = !model.sidebarIsDocked && model.sidebarDrawerOpen
        HStack(spacing: 3) {
            PanelCloseControl()
                .frame(width: 22, height: Mocha.headerRowHeight)
                .background(HeaderControlBounds())
            Button(action: onToggleSidebar) {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13))
                    .foregroundStyle(sidebarVisible ? Mocha.blue : Mocha.secondary)
                    .frame(width: 26, height: Mocha.headerRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sidebarVisible ? "Hide lists sidebar" : "Show lists sidebar")
            .accessibilityValue(sidebarVisible ? "Expanded" : "Collapsed")
            .help(sidebarVisible ? "Hide lists sidebar" : "Show lists sidebar")
            .background(HeaderControlBounds())
            if LabEnvironment.isEnabled {
                Text("LAB")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Mocha.secondary)
                    .help("Chit Lab · disposable session")
                    .accessibilityLabel("Chit Lab, disposable session")
                    .accessibilityHidden(drawerOpen)
            }
            HStack(spacing: 5) {
                Text(model.selectedProject?.name ?? "Chit")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let project = model.selectedProject {
                    ProjectStatusGlyphs(model: model, project: project, showsLocation: true)
                }
            }
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(model.selectedProject.map { ProjectPresentation.description($0, model: model) } ?? "Chit")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.selectedProject.map {
                "Current list: " + ProjectPresentation.description($0, model: model)
            } ?? "Chit")
            .accessibilityHidden(drawerOpen)
            Menu {
                ProjectManagementMenuItems(model: model, onNewList: onNewList,
                    onNameForm: { form = $0 }, onSelect: { model.selectProject($0.id) })
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(Mocha.blue)
                    .frame(width: 22, height: Mocha.headerRowHeight)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 22, height: Mocha.headerRowHeight)
            .accessibilityLabel("Lists and groups")
            .help("Create and manage lists and groups")
            .disabled(!model.isStoreAvailable || drawerOpen)
            .accessibilityHidden(drawerOpen)
            .background(HeaderControlBounds())
            .modifier(ProjectNameFormPresenter(model: model, form: $form, arrowEdge: .bottom))
        }
        .frame(height: Mocha.headerRowHeight)
        .coordinateSpace(name: "project-header")
        .onPreferenceChange(HeaderControlFrames.self) { interactiveFrames = $0 }
        .background { HeaderDragArea(excludedRects: interactiveFrames) }
        .font(.system(size: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("List header")
    }

}

struct ProjectSidebar: View {
    @ObservedObject var model: AppModel
    var onNewList: (String?) -> Void
    var onSelect: () -> Void
    @StateObject private var dragState = ProjectDragState()
    @State private var form: ProjectNameForm?
    @FocusState private var focusedRow: SidebarFocus?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !model.sidebarIsDocked { drawerHeading }
                    VStack(alignment: .leading, spacing: 2) {
                        if !model.workspace.groups.isEmpty || dragState.payload != nil { ungroupedHeading }
                        ForEach(model.workspace.projects.filter { $0.groupID == nil }) { project in
                            projectRow(project)
                        }
                        if model.workspace.projects.isEmpty && model.workspace.groups.isEmpty {
                            Text("No lists yet")
                                .font(.system(size: 11))
                                .foregroundStyle(Mocha.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                        }
                    }
                    ForEach(model.workspace.groups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            groupHeading(group)
                            if !model.collapsedGroupIDs.contains(group.id) {
                                let projects = model.workspace.projects.filter { $0.groupID == group.id }
                                ForEach(projects) { project in projectRow(project) }
                                if projects.isEmpty {
                                    Text("No lists")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Mocha.secondary)
                                        .padding(.leading, 22)
                                        .padding(.vertical, 5)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 7)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: focusedRow) { _, row in
                if let row { proxy.scrollTo(row) }
            }
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lists sidebar")
        .modifier(ProjectNameFormPresenter(model: model, form: $form, arrowEdge: .trailing))
        .onDisappear { dragState.finish() }
        .onAppear {
            if model.sidebarVisible && !model.sidebarIsDocked && model.sidebarDrawerOpen { focusedRow = preferredFocus }
        }
        .onChange(of: model.sidebarDrawerOpen) { _, open in
            focusedRow = open && model.sidebarVisible ? preferredFocus : nil
        }
        .onChange(of: model.sidebarVisible) { _, visible in
            if !visible { focusedRow = nil }
        }
        .onChange(of: visibleRows) { _, rows in
            if model.sidebarVisible, let focusedRow, !rows.contains(focusedRow) { self.focusedRow = preferredFocus }
        }
    }

    private var drawerHeading: some View {
        HStack {
            Text("Lists").font(.system(size: 12, weight: .semibold))
            Spacer()
            Menu {
                ProjectManagementMenuItems(model: model, onNewList: onNewList,
                    onNameForm: { form = $0 }, onSelect: select)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(Mocha.blue)
                    .frame(width: 22, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 22, height: 26)
            .accessibilityLabel("Lists and groups")
            .help("Create and manage lists and groups")
            .disabled(!model.isStoreAvailable)
            Button("Done", action: onSelect)
                .buttonStyle(.plain)
                .foregroundStyle(Mocha.blue)
                .padding(.horizontal, 5)
                .frame(height: 26)
                .overlay { focusOutline(.done) }
                .focusable(true)
                .focused($focusedRow, equals: .done)
                .onKeyPress(keys: navigationKeys, action: navigate)
                .modifier(SidebarKeyboardActivation(action: onSelect))
                .accessibilityLabel("Close lists sidebar")
                .id(SidebarFocus.done)
        }
        .padding(.horizontal, 8)
    }

    private var ungroupedHeading: some View {
        Text("Ungrouped")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Mocha.secondary)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, 8)
            .background(dragState.hoveredTarget == .group(nil) ? Mocha.selected : Color.clear,
                in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                ProjectDragHandle(model: model, state: dragState, destination: .group(nil), onClick: {},
                    tooltip: "Drop a list here to remove it from its group")
            }
            .accessibilityLabel("Ungrouped lists")
    }

    private func projectRow(_ project: Project) -> some View {
        let selected = model.selectedProjectID == project.id
        let focus = SidebarFocus.project(project.id)
        return HStack(spacing: 0) {
            Button { select(project) } label: {
                HStack(alignment: .top, spacing: 6) {
                    if ProjectPresentation.isExternal(project.id, model: model) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(Mocha.secondary)
                            .frame(width: 13, height: 16)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Mocha.blue : Mocha.text)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let location = model.location(for: project.id), !location.isManaged {
                            Text((location.url.path as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 11))
                                .foregroundStyle(Mocha.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ProjectStatusGlyphs(model: model, project: project)
                        .frame(minHeight: 16)
                }
                .padding(.leading, project.groupID == nil ? 8 : 22)
                .padding(.trailing, 3)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(true)
            .focused($focusedRow, equals: focus)
            .onKeyPress(keys: navigationKeys, action: navigate)
            .modifier(SidebarKeyboardActivation { select(project) })
            .accessibilityLabel(ProjectPresentation.description(project, model: model))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint("Open list")
            .help(ProjectPresentation.description(project, model: model))
            .overlay {
                ProjectDragHandle(model: model, state: dragState, sourceProject: project,
                    destination: .tab(project.id), onClick: { select(project) },
                    tooltip: ProjectPresentation.description(project, model: model))
            }
            Menu {
                ProjectMenuItems(model: model, project: project) { form = $0 }
            } label: { rowMenuGlyph }
            .modifier(SidebarMenuStyle(label: "Manage \(project.name)"))
            .disabled(!model.isStoreAvailable)
        }
        .background(selected ? Mocha.selected : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .overlay { focusOutline(focus) }
        .overlay(alignment: .top) {
            if dragState.hoveredTarget == .before(project.id) { insertionMark }
        }
        .overlay(alignment: .bottom) {
            if dragState.hoveredTarget == .after(project.id) { insertionMark }
        }
        .contextMenu { ProjectMenuItems(model: model, project: project) { form = $0 } }
        .id(focus)
    }

    private func groupHeading(_ group: ProjectGroup) -> some View {
        let focus = SidebarFocus.group(group.id)
        return HStack(spacing: 0) {
            groupDisclosureButton(group)
            Menu {
                ProjectGroupMenuItems(model: model, group: group, onNewList: onNewList) { form = $0 }
            } label: { rowMenuGlyph }
            .modifier(SidebarMenuStyle(label: "Manage group \(group.name)"))
            .disabled(!model.isStoreAvailable)
        }
        .background(dragState.hoveredTarget == .group(group.id) ? Mocha.selected : Color.clear,
            in: RoundedRectangle(cornerRadius: 5))
        .overlay { focusOutline(focus) }
        .contextMenu {
            ProjectGroupMenuItems(model: model, group: group, onNewList: onNewList) { form = $0 }
        }
        .id(focus)
    }

    private func groupDisclosureButton(_ group: ProjectGroup) -> some View {
        let collapsed = model.collapsedGroupIDs.contains(group.id)
        let selected: Project? = model.selectedProject?.groupID == group.id ? model.selectedProject : nil
        let projects = model.workspace.projects.filter { $0.groupID == group.id }
        let hasIssue = collapsed && projects.contains { model.issue(for: $0.id) != nil }
        let hasOverdue = collapsed && projects.contains { model.hasOverdueTasks(projectID: $0.id) }
        let focus = SidebarFocus.group(group.id)
        var accessibilityLabel = group.name
        var tooltip = group.name
        if let selected {
            accessibilityLabel += ", current list: \(selected.name)"
            tooltip += " · " + ProjectPresentation.description(selected, model: model)
        }
        if hasIssue { accessibilityLabel += ", contains lists needing attention" }
        if hasOverdue { accessibilityLabel += ", contains overdue tasks" }
        return Button { toggle(group) } label: {
            ProjectGroupHeadingLabel(group: group, selected: selected, collapsed: collapsed,
                hasIssue: hasIssue, hasOverdue: hasOverdue)
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($focusedRow, equals: focus)
        .onKeyPress(keys: navigationKeys, action: navigate)
        .modifier(SidebarKeyboardActivation { toggle(group) })
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(collapsed ? "Collapsed group" : "Expanded group")
        .accessibilityHint(collapsed ? "Expand to show lists" : "Collapse lists")
        .help(tooltip)
        .overlay {
            ProjectDragHandle(model: model, state: dragState, destination: .group(group.id),
                onClick: { toggle(group) }, tooltip: group.name)
        }
    }

    private var rowMenuGlyph: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Mocha.secondary)
            .frame(width: 24, height: 28)
            .contentShape(Rectangle())
    }

    private var insertionMark: some View {
        Capsule().fill(Mocha.blue).frame(height: 2).padding(.horizontal, 4)
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func focusOutline(_ row: SidebarFocus) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(focusedRow == row ? Mocha.blue : Color.clear, lineWidth: 1)
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func select(_ project: Project) {
        focusedRow = .project(project.id)
        model.selectProject(project.id)
        onSelect()
    }

    private func toggle(_ group: ProjectGroup) {
        focusedRow = .group(group.id)
        model.toggleGroup(group.id)
    }

    private var navigationKeys: Set<KeyEquivalent> { [.upArrow, .downArrow, .leftArrow, .rightArrow, .home, .end] }

    private var visibleRows: [SidebarFocus] {
        var rows: [SidebarFocus] = model.sidebarIsDocked ? [] : [.done]
        rows += model.workspace.projects.filter { $0.groupID == nil }.map { .project($0.id) }
        for group in model.workspace.groups {
            rows.append(.group(group.id))
            if !model.collapsedGroupIDs.contains(group.id) {
                rows += model.workspace.projects.filter { $0.groupID == group.id }.map { .project($0.id) }
            }
        }
        return rows
    }

    private var preferredFocus: SidebarFocus? {
        if let project = model.selectedProject {
            let row = SidebarFocus.project(project.id)
            if visibleRows.contains(row) { return row }
            if let groupID = project.groupID { return .group(groupID) }
        }
        return visibleRows.first
    }

    private func navigate(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty, let row = focusedRow else { return .ignored }
        let rows = visibleRows
        guard let index = rows.firstIndex(of: row) else { return .ignored }
        switch press.key {
        case .upArrow: focusedRow = rows[max(0, index - 1)]
        case .downArrow: focusedRow = rows[min(rows.count - 1, index + 1)]
        case .home: focusedRow = rows.first
        case .end: focusedRow = rows.last
        case .leftArrow:
            switch row {
            case .group(let id):
                if !model.collapsedGroupIDs.contains(id) { model.toggleGroup(id) }
            case .project(let id):
                if let groupID = model.workspace.projects.first(where: { $0.id == id })?.groupID {
                    focusedRow = .group(groupID)
                }
            case .done: return .ignored
            }
        case .rightArrow:
            guard case .group(let id) = row else { return .ignored }
            if model.collapsedGroupIDs.contains(id) { model.toggleGroup(id) }
            else if let project = model.workspace.projects.first(where: { $0.groupID == id }) {
                focusedRow = .project(project.id)
            }
        default: return .ignored
        }
        return .handled
    }
}

private enum SidebarFocus: Hashable {
    case done, project(String), group(String)
}

private struct ProjectGroupHeadingLabel: View {
    let group: ProjectGroup
    let selected: Project?
    let collapsed: Bool
    let hasIssue: Bool
    let hasOverdue: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .medium))
                .frame(width: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if collapsed, let selected {
                    Text(selected.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if selected != nil {
                Circle().fill(Mocha.blue).frame(width: 5, height: 5).accessibilityHidden(true)
            }
            if hasIssue { ProjectStatusGlyphs.issueGlyph }
            if hasOverdue { ProjectStatusGlyphs.overdueGlyph }
        }
        .foregroundStyle(selected != nil ? Mocha.blue : Mocha.secondary)
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SidebarKeyboardActivation: ViewModifier {
    var action: () -> Void
    func body(content: Content) -> some View {
        content.onKeyPress(keys: [.return, .space], phases: .down) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            action()
            return .handled
        }
    }
}

private struct SidebarMenuStyle: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        content.menuStyle(.borderlessButton).menuIndicator(.hidden)
            .fixedSize().frame(width: 26)
            .accessibilityLabel(label).help(label)
    }
}

private struct ProjectStatusGlyphs: View {
    @ObservedObject var model: AppModel
    let project: Project
    var showsLocation = false
    var body: some View {
        HStack(spacing: 4) {
            if showsLocation && ProjectPresentation.isExternal(project.id, model: model) {
                Image(systemName: "folder")
                    .font(.system(size: 11)).foregroundStyle(Mocha.secondary).accessibilityHidden(true)
            }
            if model.issue(for: project.id) != nil { Self.issueGlyph }
            if model.hasOverdueTasks(projectID: project.id) { Self.overdueGlyph }
        }
    }
    static var issueGlyph: some View {
        Image(systemName: "exclamationmark.circle")
            .font(.system(size: 11)).foregroundStyle(Mocha.warning).accessibilityHidden(true)
    }
    static var overdueGlyph: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10)).foregroundStyle(Mocha.warning).accessibilityHidden(true)
    }
}

@MainActor
private enum ProjectPresentation {
    static func isExternal(_ id: String, model: AppModel) -> Bool {
        model.location(for: id).map { !$0.isManaged } ?? false
    }
    static func description(_ project: Project, model: AppModel) -> String {
        var description = project.name
        if let issue = model.issue(for: project.id) {
            description += issue.isMissing ? ", file not found" : ", list needs attention"
        }
        if model.hasOverdueTasks(projectID: project.id) { description += ", contains overdue tasks" }
        guard let location = model.location(for: project.id) else { return description }
        return "\(description), \(location.isManaged ? "saved in app" : "saved in folder"), \(location.url.path)"
    }
}

private struct ProjectManagementMenuItems: View {
    @ObservedObject var model: AppModel
    var onNewList: (String?) -> Void
    var onNameForm: (ProjectNameForm) -> Void
    var onSelect: (Project) -> Void

    var body: some View {
        Menu("New List") {
            NewListDestinationOptions(model: model) { onNewList(nil) }
        }
        Button("Open List…") { ListActions.open(model: model) }
        Button("New Group…") { onNameForm(.newGroup) }
        if !model.workspace.projects.isEmpty {
            Divider()
            Menu("Switch List") {
                ForEach(model.workspace.projects.filter { $0.groupID == nil }) { project in
                    switchListButton(project)
                }
                ForEach(model.workspace.groups) { group in
                    Menu(group.name) {
                        ForEach(model.workspace.projects.filter { $0.groupID == group.id }) { project in
                            switchListButton(project)
                        }
                    }
                }
            }
        }
        if let project = model.selectedProject {
            Divider()
            Menu("Current List: \(project.name)") {
                ProjectMenuItems(model: model, project: project, onNameForm: onNameForm)
            }
        }
        if !model.workspace.groups.isEmpty {
            Menu("Groups") {
                ForEach(model.workspace.groups) { group in
                    Menu(group.name) {
                        ProjectGroupMenuItems(model: model, group: group,
                            onNewList: onNewList, onNameForm: onNameForm)
                    }
                }
            }
        }
        Divider()
        Button("Undo") { model.undo() }.disabled(!model.canUndo)
        Button("Redo") { model.redo() }.disabled(!model.canRedo)
    }

    private func switchListButton(_ project: Project) -> some View {
        Button { onSelect(project) } label: {
            Label(project.name, systemImage: model.selectedProjectID == project.id ? "checkmark" : "list.bullet")
        }
    }
}

/// Header menus, row menus and contextual menus share the same actions.
private struct ProjectMenuItems: View {
    @ObservedObject var model: AppModel
    let project: Project
    var onNameForm: (ProjectNameForm) -> Void
    var body: some View {
        Button("Rename List…") { onNameForm(.renameProject(project)) }
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
        Button("Move Up") { model.moveProject(project, offset: -1) }
            .disabled(!model.canMoveProject(project, offset: -1))
        Button("Move Down") { model.moveProject(project, offset: 1) }
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
        if model.issue(for: project.id) != nil { Text("Locate or retry the file before deleting.") }
    }
}

private struct ProjectGroupMenuItems: View {
    @ObservedObject var model: AppModel
    let group: ProjectGroup
    var onNewList: (String?) -> Void
    var onNameForm: (ProjectNameForm) -> Void
    var body: some View {
        Button(model.collapsedGroupIDs.contains(group.id) ? "Expand group" : "Collapse group") { model.toggleGroup(group.id) }
        Menu("New List in Group") {
            NewListDestinationOptions(model: model, groupID: group.id) { onNewList(group.id) }
        }
        Button("Open List in Group…") { ListActions.open(model: model, groupID: group.id) }
        Button("Rename Group…") { onNameForm(.renameGroup(group)) }
        Divider()
        Button("Remove Group; Keep Lists", role: .destructive) { model.deleteGroup(group) }
    }
}

private struct ProjectNameFormPresenter: ViewModifier {
    @ObservedObject var model: AppModel
    @Binding var form: ProjectNameForm?
    let arrowEdge: Edge
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    func body(content: Content) -> some View {
        content.popover(isPresented: Binding(get: { form != nil }, set: { if !$0 { form = nil } }), arrowEdge: arrowEdge) {
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
                .onAppear { name = form.name; nameFocused = true }
                .onDisappear { nameFocused = false }
            }
        }
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

private enum ProjectNameForm {
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

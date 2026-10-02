import AppKit
import SwiftUI
import TodoCore

/// The current list and navigation toggle stay in place in both sidebar modes.
struct ProjectHeader: View {
    @ObservedObject var model: AppModel
    let sidebarExpanded: Bool
    var onToggleSidebar: () -> Void
    @State private var interactiveFrames: [CGRect] = []

    var body: some View {
        HStack(spacing: 3) {
            PanelCloseControl()
                .frame(width: 24, height: Mocha.headerRowHeight)
                .background(HeaderControlBounds())
            Button(action: onToggleSidebar) {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13))
                    .foregroundStyle(sidebarExpanded ? Mocha.blue : Mocha.secondary)
                    .frame(width: 26, height: Mocha.headerRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sidebarExpanded ? "Collapse lists" : "Expand lists")
            .accessibilityValue(sidebarExpanded ? "Expanded" : "Collapsed")
            .help(sidebarExpanded ? "Collapse lists" : "Expand lists")
            .overlay { SidebarTogglePointerBoundary(onToggle: onToggleSidebar) }
            .background(HeaderControlBounds())
            if LabEnvironment.isEnabled {
                Text("LAB")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Mocha.secondary)
                    .help("Chit Lab · disposable session")
                    .accessibilityLabel("Chit Lab, disposable session")
            }
            HStack(spacing: 5) {
                Text(model.selectedProject?.name ?? "Chit")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let project = model.selectedProject {
                    ProjectStatusGlyphs(model: model, project: project)
                }
            }
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(model.selectedProject.map { ProjectPresentation.description($0, model: model) } ?? "Chit")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.selectedProject.map {
                "Current list: " + ProjectPresentation.description($0, model: model)
            } ?? "Chit")
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
    @StateObject private var dragState = ProjectDragState()
    @State private var form: ProjectNameForm?
    @FocusState private var focusedRow: SidebarFocus?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    createListRow
                    ForEach(model.workspace.projects.filter { $0.groupID == nil }) { project in
                        projectRow(project)
                    }
                    if model.workspace.projects.isEmpty && model.workspace.groups.isEmpty {
                        placeholder("No lists yet")
                    }
                    ForEach(model.workspace.groups) { group in
                        groupHeading(group)
                        if !model.collapsedGroupIDs.contains(group.id) {
                            let projects = model.workspace.projects.filter { $0.groupID == group.id }
                            ForEach(projects) { project in projectRow(project) }
                            if projects.isEmpty { placeholder("No lists") }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SidebarNavigationContentBoundary())
            }
            .onChange(of: focusedRow) { _, row in
                if let row { proxy.scrollTo(row) }
            }
            .onChange(of: model.selectedProjectID) { _, id in
                let row = SidebarFocus.project(id)
                if visibleRows.contains(row) { proxy.scrollTo(row) }
            }
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lists sidebar")
        .modifier(ProjectNameFormPresenter(model: model, form: $form, arrowEdge: .trailing))
        .onDisappear { dragState.finish() }
        .onChange(of: model.sidebarExpanded) { _, expanded in
            if !expanded { dragState.finish() }
        }
        .onChange(of: visibleRows) { _, rows in
            if let focusedRow, !rows.contains(focusedRow) {
                self.focusedRow = replacementFocus(for: focusedRow, in: rows)
            }
        }
    }

    private func placeholder(_ title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "list.bullet")
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
            if model.sidebarExpanded {
                Text(title).font(.system(size: 11)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Mocha.secondary)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .help(title)
    }

    private var createListRow: some View {
        let tooltip = model.sidebarExpanded
            ? "Create List · Drop a list here to remove it from its group"
            : "Create List · Right-click to manage lists and groups"
        return HStack(spacing: 0) {
            Button(action: createList) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(Mocha.blue)
                        .frame(width: 24, height: 24)
                    if model.sidebarExpanded {
                        Text("Create List")
                            .font(.system(size: 12))
                            .foregroundStyle(Mocha.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 6)
                .padding(.trailing, model.sidebarExpanded ? 3 : 6)
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(true)
            .focused($focusedRow, equals: .create)
            .onKeyPress(keys: navigationKeys, action: navigate)
            .modifier(SidebarKeyboardActivation(action: createList))
            .accessibilityIdentifier("create-list")
            .accessibilityLabel("Create List")
            .accessibilityHint("Create a list in Chit")
            .help(tooltip)
            .overlay {
                ProjectDragHandle(model: model, state: dragState, destination: .group(nil),
                    onClick: createList, tooltip: tooltip, draggingEnabled: model.sidebarExpanded)
            }
            .disabled(!model.isStoreAvailable)
            if model.sidebarExpanded {
                Menu {
                    managementMenuItems
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Mocha.secondary)
                        .frame(width: 24, height: 32)
                        .contentShape(Rectangle())
                }
                .modifier(SidebarMenuStyle(label: "Lists and groups"))
                .accessibilityIdentifier("list-management-menu")
                .help("Create and manage lists and groups")
                .disabled(!model.isStoreAvailable)
            }
        }
        .background(dragState.hoveredTarget == .group(nil) ? Mocha.selected : Color.clear,
            in: RoundedRectangle(cornerRadius: 5))
        .overlay { focusOutline(.create) }
        .contextMenu { managementMenuItems }
        .id(SidebarFocus.create)
    }

    private var managementMenuItems: some View {
        ProjectManagementMenuItems(model: model, onNewList: onNewList,
            onNameForm: { form = $0 }, onSelect: select)
            .disabled(!model.isStoreAvailable)
    }

    private func createList() {
        guard model.isStoreAvailable, !hasActiveTextComposition else { return }
        onNewList(nil)
    }

    private var hasActiveTextComposition: Bool {
        (NSApp?.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    private func projectRow(_ project: Project) -> some View {
        let selected = model.selectedProjectID == project.id
        let focus = SidebarFocus.project(project.id)
        let description = ProjectPresentation.description(project, model: model)
        return HStack(spacing: 0) {
            Button { select(project) } label: {
                HStack(spacing: 7) {
                    ProjectBadge(project: project, showsStatus: !model.sidebarExpanded,
                        hasIssue: model.issue(for: project.id) != nil,
                        hasOverdue: model.hasOverdueTasks(projectID: project.id))
                    if model.sidebarExpanded {
                        Text(project.name)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(Mocha.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProjectStatusGlyphs(model: model, project: project)
                    }
                }
                .padding(.leading, 6)
                .padding(.trailing, model.sidebarExpanded ? 3 : 6)
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(true)
            .focused($focusedRow, equals: focus)
            .onKeyPress(keys: navigationKeys, action: navigate)
            .modifier(SidebarKeyboardActivation { select(project) })
            .accessibilityIdentifier("list-row-\(project.id)")
            .accessibilityLabel(description)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint("Open list")
            .help(description)
            .overlay {
                ProjectDragHandle(model: model, state: dragState, sourceProject: project,
                    destination: .tab(project.id), onClick: { select(project) },
                    tooltip: description, draggingEnabled: model.sidebarExpanded)
            }
            if model.sidebarExpanded {
                Menu {
                    ProjectMenuItems(model: model, project: project) { form = $0 }
                } label: { rowMenuGlyph }
                .modifier(SidebarMenuStyle(label: "Manage \(project.name)"))
                .accessibilityIdentifier("list-menu-\(project.id)")
                .disabled(!model.isStoreAvailable)
            }
        }
        .background(selected ? Mocha.selected : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) {
            if selected {
                Capsule().fill(Mocha.blue).frame(width: 2, height: 20)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
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
            if model.sidebarExpanded {
                Menu {
                    ProjectGroupMenuItems(model: model, group: group, onNewList: onNewList) { form = $0 }
                } label: { rowMenuGlyph }
                .modifier(SidebarMenuStyle(label: "Manage group \(group.name)"))
                .disabled(!model.isStoreAvailable)
            }
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
        let hasIssue = (collapsed || !model.sidebarExpanded) && projects.contains { model.issue(for: $0.id) != nil }
        let hasOverdue = (collapsed || !model.sidebarExpanded) && projects.contains { model.hasOverdueTasks(projectID: $0.id) }
        let focus = SidebarFocus.group(group.id)
        var accessibilityLabel = "Group \(group.name)"
        if let selected {
            accessibilityLabel += ", current list: \(selected.name)"
        }
        if hasIssue { accessibilityLabel += ", contains lists needing attention" }
        if hasOverdue { accessibilityLabel += ", contains overdue tasks" }
        let tooltip = accessibilityLabel + (collapsed ? ", collapsed" : ", expanded")
        return Button { toggle(group) } label: {
            ProjectGroupHeadingLabel(group: group, selected: selected, collapsed: collapsed,
                expanded: model.sidebarExpanded, hasIssue: hasIssue, hasOverdue: hasOverdue)
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($focusedRow, equals: focus)
        .onKeyPress(keys: navigationKeys, action: navigate)
        .modifier(SidebarKeyboardActivation { toggle(group) })
        .accessibilityIdentifier("group-row-\(group.id)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(collapsed ? "Collapsed group" : "Expanded group")
        .accessibilityHint(collapsed ? "Expand to show lists" : "Collapse lists")
        .help(tooltip)
        .overlay {
            ProjectDragHandle(model: model, state: dragState, destination: .group(group.id),
                onClick: { toggle(group) }, tooltip: tooltip, draggingEnabled: model.sidebarExpanded)
        }
    }

    private var rowMenuGlyph: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Mocha.secondary)
            .frame(width: 24, height: 32)
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
        // The native row overlay reaches this guard before changing responder
        // or SwiftUI focus, so a marked-text editor can refuse navigation.
        guard model.selectProject(project.id) else { return }
        focusedRow = .project(project.id)
    }

    private func toggle(_ group: ProjectGroup) {
        guard !hasActiveTextComposition else { return }
        focusedRow = .group(group.id)
        model.toggleGroup(group.id)
    }

    private var navigationKeys: Set<KeyEquivalent> { [.upArrow, .downArrow, .leftArrow, .rightArrow, .home, .end] }

    private var visibleRows: [SidebarFocus] {
        var rows: [SidebarFocus] = [.create]
        rows += model.workspace.projects.filter { $0.groupID == nil }.map { .project($0.id) }
        for group in model.workspace.groups {
            rows.append(.group(group.id))
            if !model.collapsedGroupIDs.contains(group.id) {
                rows += model.workspace.projects.filter { $0.groupID == group.id }.map { .project($0.id) }
            }
        }
        return rows
    }

    private func replacementFocus(for row: SidebarFocus, in rows: [SidebarFocus]) -> SidebarFocus? {
        switch row {
        case .create: return .create
        case .project(let id):
            if let groupID = model.workspace.projects.first(where: { $0.id == id })?.groupID,
               rows.contains(.group(groupID)) { return .group(groupID) }
        case .group(let id):
            let projects = model.workspace.projects.filter { $0.groupID == id }
            if let selected = projects.first(where: { $0.id == model.selectedProjectID }),
               rows.contains(.project(selected.id)) {
                return .project(selected.id)
            }
            if let first = projects.first, rows.contains(.project(first.id)) { return .project(first.id) }
        }
        let selected = SidebarFocus.project(model.selectedProjectID)
        return rows.contains(selected) ? selected : rows.first
    }

    private func navigate(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty, !hasActiveTextComposition, let row = focusedRow else { return .ignored }
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
            case .create: return .ignored
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
    case create, project(String), group(String)
}

private struct ProjectBadge: View {
    let project: Project
    let showsStatus: Bool
    let hasIssue: Bool
    let hasOverdue: Bool

    var body: some View {
        Text(ProjectPresentation.monogram(project.name))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Mocha.text)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: 24, height: 24)
            .background(Mocha.listBadgeColor(for: project.id), in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .bottomTrailing) {
                if showsStatus && (hasIssue || hasOverdue) {
                    Image(systemName: hasIssue ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Mocha.warning)
                        .frame(width: 12, height: 12)
                        .background(Mocha.selected, in: Circle())
                        .offset(x: 3, y: 2)
                }
            }
            .accessibilityHidden(true)
    }
}

private struct ProjectGroupHeadingLabel: View {
    let group: ProjectGroup
    let selected: Project?
    let collapsed: Bool
    let expanded: Bool
    let hasIssue: Bool
    let hasOverdue: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: collapsed ? "folder" : "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(selected != nil ? Mocha.blue : Mocha.secondary)
                .frame(width: 24, height: 24)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .frame(width: 9, height: 9)
                }
                .overlay(alignment: .topTrailing) {
                    if !expanded && selected != nil {
                        Circle().fill(Mocha.blue).frame(width: 4, height: 4)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if !expanded && (hasIssue || hasOverdue) {
                        Image(systemName: hasIssue ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Mocha.warning)
                            .frame(width: 12, height: 12)
                            .background(Mocha.selected, in: Circle())
                    }
                }
                .accessibilityHidden(true)
            if expanded {
                Text(group.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected != nil {
                    Circle().fill(Mocha.blue).frame(width: 5, height: 5).accessibilityHidden(true)
                }
                if hasIssue { ProjectStatusGlyphs.issueGlyph }
                if hasOverdue { ProjectStatusGlyphs.overdueGlyph }
            }
        }
        .foregroundStyle(Mocha.secondary)
        .padding(.leading, 6)
        .padding(.trailing, expanded ? 3 : 6)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
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
            .fixedSize().frame(width: 24)
            .accessibilityLabel(label).help(label)
    }
}

private struct ProjectStatusGlyphs: View {
    @ObservedObject var model: AppModel
    let project: Project
    var body: some View {
        HStack(spacing: 4) {
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
    static func monogram(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        guard let first = words.first else { return "?" }
        let initials = words.count > 1
            ? Array(first.prefix(1)) + Array(words[1].prefix(1))
            : Array(first.prefix(2))
        return initials.map { character in
            let uppercase = String(character).uppercased()
            return uppercase.count == 1 ? uppercase : String(character)
        }.joined()
    }

    static func description(_ project: Project, model: AppModel) -> String {
        var description = project.name
        if let groupID = project.groupID,
           let group = model.workspace.groups.first(where: { $0.id == groupID }) {
            description += ", group \(group.name)"
        } else { description += ", ungrouped" }
        if let issue = model.issue(for: project.id) {
            description += issue.isMissing ? ", file not found" : ", list needs attention"
        }
        if model.hasOverdueTasks(projectID: project.id) { description += ", contains overdue tasks" }
        return description
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

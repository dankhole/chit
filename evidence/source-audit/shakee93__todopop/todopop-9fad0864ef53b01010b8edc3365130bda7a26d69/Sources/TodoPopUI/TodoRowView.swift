import SwiftUI
import TodoPopKit

/// A single todo row: a drag handle for reordering, an animated completion toggle, an
/// inline-editable title, hover-reveal delete, and a context menu (move between days,
/// reorder, delete).
struct TodoRowView: View {
    let item: TodoItem
    let store: TodoStore
    var isDragging: Bool = false
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: (CGFloat) -> Void = { _ in }

    @State private var title: String
    @State private var hovering = false
    @FocusState private var editing: Bool

    init(
        item: TodoItem,
        store: TodoStore,
        isDragging: Bool = false,
        onDragChanged: @escaping (CGFloat) -> Void = { _ in },
        onDragEnded: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.item = item
        self.store = store
        self.isDragging = isDragging
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        _title = State(initialValue: item.title)
    }

    var body: some View {
        HStack(spacing: 8) {
            dragHandle

            Checkbox(isOn: item.isCompleted) {
                withAnimation(Theme.pop) { store.toggle(item.id) }
            }

            TextField("", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($editing)
                .strikethrough(item.isCompleted, color: .secondary)
                .foregroundStyle(item.isCompleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .onSubmit { commitRename() }
                .onChange(of: editing) { _, isEditing in
                    if !isEditing { commitRename() }
                }
                // Reflect an external change to this task's title (e.g. renamed on another
                // Mac and synced in) when we're not the one editing it.
                .onChange(of: item.title) { _, newTitle in
                    if !editing { title = newTitle }
                }

            Spacer(minLength: 4)

            if hovering && !isDragging {
                Button {
                    withAnimation(Theme.ease) { store.delete(item.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Theme.fill(0.10)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .help("Delete")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, Theme.rowVPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCorner)
                .fill(isDragging ? Theme.fill(0.14) : (hovering ? Theme.hoverFill : Color.clear))
                .shadow(color: .black.opacity(isDragging ? 0.18 : 0),
                        radius: isDragging ? 6 : 0, y: isDragging ? 3 : 0)
        )
        .scaleEffect(isDragging ? 1.02 : 1)
        .opacity(item.isCompleted && !isDragging ? Theme.completedRowOpacity : 1)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(Theme.ease) { self.hovering = hovering } }
        .onDisappear { commitRename() } // don't lose an in-progress edit if the panel closes
        .contextMenu {
            Button("Move Up") { moveBy(-1) }
            Button("Move Down") { moveBy(1) }
            Divider()
            Button("Move to Yesterday") { moveDay(-1) }
            Button("Move to Today") { store.move(item.id, to: store.today()) }
            Button("Move to Tomorrow") { moveDay(1) }
            Divider()
            Button(item.isCompleted ? "Mark as Not Done" : "Mark as Done") { store.toggle(item.id) }
            Button("Delete", role: .destructive) { store.delete(item.id) }
        }
        .animation(Theme.pop, value: item.isCompleted)
    }

    /// Grab area for reordering. Lives on a dedicated control so it never fights the text
    /// field or checkbox for the mouse.
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .opacity(hovering || isDragging ? 0.9 : 0.3)
            .frame(width: 16, height: 26)
            .contentShape(Rectangle())
            .gesture(
                // Measure in GLOBAL space: the row we drag is itself offset by this
                // translation, so a local coordinate space would move with it and feed back
                // on itself (row lags at half speed + jitters). Global space is stable.
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { onDragChanged($0.translation.height) }
                    .onEnded { onDragEnded($0.translation.height) }
            )
            .help("Drag to reorder")
    }

    private func moveBy(_ delta: Int) {
        let arr = store.items(on: item.day)
        guard let i = arr.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            store.moveItem(item.id, toIndex: i + delta, in: item.day)
        }
    }

    private func moveDay(_ days: Int) {
        store.move(item.id, to: store.addingDays(days, to: store.today()))
    }

    private func commitRename() {
        if title != item.title { store.rename(item.id, to: title) }
    }
}

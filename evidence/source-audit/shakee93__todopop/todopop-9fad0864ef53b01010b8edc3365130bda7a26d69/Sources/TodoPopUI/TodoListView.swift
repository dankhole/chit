import SwiftUI
import TodoPopKit

/// The todos for the selected day, in a scroll view of custom rows. Reordering uses a
/// dedicated drag handle + a SwiftUI drag gesture with live reflow — reliable inside a menu
/// bar popover, where `List`'s row-drag can't get a grip past the inline text field.
struct TodoListView: View {
    let day: Date
    let store: TodoStore

    @State private var draggingID: UUID?
    @State private var dragOffsetY: CGFloat = 0

    private let rowHeight: CGFloat = 34
    private let rowSpacing: CGFloat = 4
    private var stride: CGFloat { rowHeight + rowSpacing }

    private var isToday: Bool { store.dayKey(day) == store.today() }

    var body: some View {
        let items = store.items(on: day)

        if items.isEmpty {
            EmptyDayView(isToday: isToday)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: rowSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let dragging = draggingID == item.id
                        let reflow = reflowOffset(index: index, items: items)
                        TodoRowView(
                            item: item,
                            store: store,
                            isDragging: dragging,
                            onDragChanged: { ty in
                                if draggingID != item.id { draggingID = item.id }
                                dragOffsetY = ty
                            },
                            onDragEnded: { ty in
                                let target = targetIndex(from: index, translation: ty, count: items.count)
                                withAnimation(.snappy(duration: 0.22)) {
                                    store.moveItem(item.id, toIndex: target, in: day)
                                    draggingID = nil
                                    dragOffsetY = 0
                                }
                            }
                        )
                        .frame(height: rowHeight)
                        .offset(y: dragging ? dragOffsetY : reflow)
                        .zIndex(dragging ? 1 : 0)
                        .animation(dragging ? nil : .snappy(duration: 0.22), value: reflow)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.never)
        }
    }

    /// Where the dragged row would land given its current vertical translation.
    private func targetIndex(from: Int, translation: CGFloat, count: Int) -> Int {
        let delta = Int((translation / stride).rounded())
        return min(max(from + delta, 0), count - 1)
    }

    /// Live reflow: non-dragged rows between the origin and the drop target shift to open a gap.
    private func reflowOffset(index j: Int, items: [TodoItem]) -> CGFloat {
        guard let id = draggingID, let f = items.firstIndex(where: { $0.id == id }) else { return 0 }
        let t = targetIndex(from: f, translation: dragOffsetY, count: items.count)
        if f < t && j > f && j <= t { return -stride }
        if t < f && j >= t && j < f { return stride }
        return 0
    }
}

/// Friendly placeholder shown for a day with no tasks.
struct EmptyDayView: View {
    let isToday: Bool

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "checklist")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(isToday ? "No tasks yet" : "Nothing here")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Add one above to get started")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

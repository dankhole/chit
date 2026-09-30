import SwiftUI
import Combine
import TodoPopKit

/// The panel shown when the menu bar item is clicked. Owns the selected day, drives day
/// navigation (chevrons / ⌘[ / ⌘] / swipe), and slides content in the travel direction.
public struct TodoPanelView: View {
    let store: TodoStore

    public init(store: TodoStore, initialDay: Date? = nil) {
        self.store = store
        _selectedDay = State(initialValue: initialDay ?? Calendar.current.startOfDay(for: Date()))
    }

    @State private var selectedDay: Date
    @State private var forward = true // direction of the last day change, for the slide

    private var dayItems: [TodoItem] { store.items(on: selectedDay) }
    private var completion: Double {
        let total = dayItems.count
        guard total > 0 else { return 0 }
        return Double(dayItems.filter(\.isCompleted).count) / Double(total)
    }

    public var body: some View {
        VStack(spacing: 0) {
            DayHeaderView(selectedDay: $selectedDay, forward: $forward, store: store)

            DayProgressBar(fraction: completion)

            QuickAddView(day: selectedDay, store: store)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider().opacity(0.4)

            ZStack {
                TodoListView(day: selectedDay, store: store)
                    .id(selectedDay)
                    .transition(.push(from: forward ? .trailing : .leading))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider().opacity(0.4)

            FooterView(selectedDay: $selectedDay, store: store)
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .background(VisualEffectView(material: .popover).ignoresSafeArea())
        .tint(Theme.accent)
        // The app stays open for days. When the calendar day rolls over, snap to the new
        // "today" if we were sitting on what used to be today — otherwise the panel would
        // show a stale day while the menu bar count (which uses the live date) moves on.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            let today = store.today()
            if store.dayKey(selectedDay) == store.addingDays(-1, to: today) {
                forward = true
                selectedDay = today
            }
        }
    }
}

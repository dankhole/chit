import SwiftUI
import TodoPopKit

/// Footer: progress text for the visible day ("2 of 5 done" / "All done"), plus a roll-over
/// action on Today when unfinished tasks remain on earlier days.
struct FooterView: View {
    @Binding var selectedDay: Date
    let store: TodoStore

    var body: some View {
        let items = store.items(on: selectedDay)
        let done = items.filter(\.isCompleted).count
        let total = items.count
        let isToday = store.dayKey(selectedDay) == store.today()
        let backlog = store.unfinished(before: store.today()).count
        let allDone = total > 0 && done == total

        HStack(spacing: 8) {
            status(done: done, total: total, allDone: allDone)
                .font(.system(size: 11, weight: .medium))

            Spacer()

            if isToday && backlog > 0 {
                Button {
                    withAnimation(Theme.nav) { _ = store.rollOver(into: store.today()) }
                } label: {
                    Label("Roll over \(backlog)", systemImage: "arrow.uturn.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(CapsuleButtonStyle())
                .help("Move \(backlog) unfinished task(s) from earlier days into today")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, Theme.hPadding)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func status(done: Int, total: Int, allDone: Bool) -> some View {
        if total == 0 {
            Text("No tasks").foregroundStyle(.secondary)
        } else if allDone {
            Label("All done", systemImage: "checkmark.seal.fill")
                .foregroundStyle(Theme.accent)
        } else {
            Text("\(done) of \(total) done").foregroundStyle(.secondary)
        }
    }
}

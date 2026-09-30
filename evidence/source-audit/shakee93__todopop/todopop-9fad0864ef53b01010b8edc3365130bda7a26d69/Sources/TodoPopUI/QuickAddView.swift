import SwiftUI
import TodoPopKit

/// Always-focused quick-add field, styled as a rounded input that highlights on focus.
/// Return commits a new task to the visible day.
struct QuickAddView: View {
    let day: Date
    let store: TodoStore

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(focused ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))

            TextField("Add a task…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit(commit)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(focused ? Theme.fieldFillActive : Theme.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.accent.opacity(focused ? 0.55 : 0), lineWidth: 1)
        )
        .padding(.horizontal, Theme.hPadding)
        .animation(Theme.ease, value: focused)
        .onAppear { focused = true }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(Theme.pop) { _ = store.add(title: trimmed, to: day) }
        text = ""
        focused = true
    }
}

import SwiftUI
import AppKit
import TodoPopKit

/// Header: ‹ · day title + date (with a "Today" jump pill when off-today) · › · overflow.
/// Swipe horizontally across the title to change days. ⌘[ / ⌘] also navigate.
struct DayHeaderView: View {
    @Binding var selectedDay: Date
    @Binding var forward: Bool
    let store: TodoStore

    private var isToday: Bool { store.dayKey(selectedDay) == store.today() }

    var body: some View {
        HStack(spacing: 4) {
            IconHoverButton(systemName: "chevron.left") { go(-1) }
                .keyboardShortcut("[", modifiers: .command)

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text(store.relativeTitle(for: selectedDay))
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.numericText())

                HStack(spacing: 6) {
                    Text(store.subtitle(for: selectedDay))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if !isToday {
                        Button(action: jumpToToday) {
                            Text("Today")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.accent.opacity(0.18)))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                        .help("Jump to today (⌘T)")
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(daySwipe)

            Spacer(minLength: 0)

            if store.syncEnabled {
                Image(systemName: "checkmark.icloud")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .help("Synced via iCloud")
                    .transition(.opacity)
            }

            IconHoverButton(systemName: "chevron.right") { go(1) }
                .keyboardShortcut("]", modifiers: .command)

            overflowMenu
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .animation(Theme.ease, value: store.syncEnabled)
    }

    /// Horizontal swipe to change days — scoped to the title area so it never steals taps
    /// from the chevron or overflow buttons.
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                if value.translation.width > 36 { go(-1) }       // swipe right → older
                else if value.translation.width < -36 { go(1) }  // swipe left → newer
            }
    }

    private var overflowMenu: some View {
        Menu {
            // ⌘[ / ⌘] live on the chevrons; keep these as plain menu entries to avoid
            // registering the same shortcut on two controls.
            Button("Previous Day") { go(-1) }
            Button("Next Day") { go(1) }
            Button("Jump to Today") { jumpToToday() }.keyboardShortcut("t", modifiers: .command)
            Divider()
            Button("Clear Completed Here") { store.clearCompleted(on: selectedDay) }
            Divider()
            if store.iCloudAvailable {
                Toggle("Sync via iCloud", isOn: Binding(
                    get: { store.syncEnabled },
                    set: { store.setSyncEnabled($0) }
                ))
            } else {
                Button("iCloud Drive Unavailable") {}.disabled(true)
            }
            Divider()
            Button("Quit TodoPop") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func go(_ delta: Int) {
        withAnimation(Theme.nav) {
            forward = delta > 0
            selectedDay = store.addingDays(delta, to: selectedDay)
        }
    }

    private func jumpToToday() {
        let target = store.today()
        withAnimation(Theme.nav) {
            forward = store.dayKey(selectedDay) < target
            selectedDay = target
        }
    }
}

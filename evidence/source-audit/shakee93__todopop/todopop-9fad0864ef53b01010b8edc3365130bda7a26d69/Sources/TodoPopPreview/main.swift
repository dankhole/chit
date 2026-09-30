import SwiftUI
import AppKit
import TodoPopKit
import TodoPopUI

// Renders the real TodoPanelView in a normal window with seeded sample data so the UI can
// be launched and screenshotted for visual verification. Not shipped in the menu bar app.

@MainActor
func freshStore() -> TodoStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("todopop-preview-\(UUID().uuidString).json")
    return TodoStore(fileURL: url)
}

/// Which UI state to render — selected via the TODOPOP_SCENARIO env var.
@MainActor
func seededStore() -> (store: TodoStore, initialDay: Date) {
    let store = freshStore()
    let today = store.today()
    let yesterday = store.addingDays(-1, to: today)
    let scenario = ProcessInfo.processInfo.environment["TODOPOP_SCENARIO"] ?? "mixed"

    switch scenario {
    case "empty":
        return (store, today) // no items → empty state

    case "alldone":
        let a = store.add(title: "Inbox zero", to: today)
        let b = store.add(title: "Ship the redesign", to: today)
        let c = store.add(title: "Water the plants", to: today)
        [a, b, c].forEach { store.toggle($0.id) }
        return (store, today) // all complete → full bar + "All done"

    case "otherday":
        store.add(title: "Standup notes", to: yesterday)
        let d = store.add(title: "Merge the PR", to: yesterday)
        store.toggle(d.id)
        store.add(title: "Email the client", to: yesterday)
        return (store, yesterday) // off-today → "Yesterday" + Today jump pill

    default: // "mixed"
        store.add(title: "Leftover from yesterday", to: yesterday) // → roll-over action
        store.add(title: "Ship the TodoPop redesign", to: today)
        let done = store.add(title: "Reply to Azeez", to: today)
        store.toggle(done.id)
        store.add(title: "Buy coffee beans", to: today)
        store.add(title: "Review the open PR", to: today)
        return (store, today)
    }
}

final class PreviewDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Once the window exists, tidy it up and publish its id for screenshotting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let window = NSApp.windows.first else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.center()

            let env = ProcessInfo.processInfo.environment
            let dir = env["CLAUDE_JOB_DIR"].map { "\($0)/tmp" } ?? NSTemporaryDirectory()
            let idURL = URL(fileURLWithPath: dir).appendingPathComponent("preview_winid.txt")
            try? "\(window.windowNumber)".write(to: idURL, atomically: true, encoding: .utf8)
            print("preview window id: \(window.windowNumber)")
        }
    }
}

struct PreviewApp: App {
    @NSApplicationDelegateAdaptor(PreviewDelegate.self) private var delegate
    private let seed = seededStore()

    var body: some Scene {
        WindowGroup {
            TodoPanelView(store: seed.store, initialDay: seed.initialDay)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

PreviewApp.main()

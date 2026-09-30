import SwiftUI
import AppKit
import TodoPopKit
import TodoPopUI

/// Forces the app to be menu-bar-only (no Dock icon, no app menu) regardless of how it's
/// launched. Belt-and-suspenders alongside `LSUIElement` in Info.plist.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct TodoPopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = TodoStore()

    var body: some Scene {
        MenuBarExtra {
            TodoPanelView(store: store)
        } label: {
            let count = store.openCount(on: store.today())
            if count > 0 {
                Label("\(count)", systemImage: "checklist")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "checklist")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

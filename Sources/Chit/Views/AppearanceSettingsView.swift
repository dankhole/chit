import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var loginItem: LoginItemController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.system(size: 13, weight: .semibold))
            Toggle("Launch at login", isOn: Binding(get: { loginItem.isOn },
                                                    set: { loginItem.setEnabled($0) }))
                .toggleStyle(.switch)
                .tint(Mocha.blue)
                .disabled(!loginItem.isAvailable)
            if !loginItem.isAvailable {
                Text("Unavailable in Chit Lab and previews.")
                    .font(.system(size: 11))
                    .foregroundStyle(Mocha.secondary)
            } else if loginItem.requiresApproval {
                Text("Allow Chit in System Settings to launch at login.")
                    .font(.system(size: 11))
                    .foregroundStyle(Mocha.secondary)
                Button("Open Login Items…") { loginItem.openSystemSettings() }
            }
            if let error = loginItem.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Mocha.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Login Items…") { loginItem.openSystemSettings() }
            }
            Divider()
            HStack {
                Text("Background opacity")
                Spacer()
                Text("\(Int((model.backgroundOpacity * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(Mocha.secondary)
            }
            Slider(value: Binding(get: { model.backgroundOpacity },
                                  set: { model.setBackgroundOpacity($0) }),
                   in: 0.30...1, step: 0.01)
                .tint(Mocha.blue)
                .accessibilityLabel("Background opacity")
                .accessibilityValue("\(Int((model.backgroundOpacity * 100).rounded())) percent")
        }
        .font(.system(size: 12))
        .foregroundStyle(Mocha.text)
        .padding(14)
        .frame(width: 232)
        .preferredColorScheme(.dark)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }
}

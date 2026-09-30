import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.system(size: 13, weight: .semibold))
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
    }
}

import SwiftUI

/// A circular icon button that lifts on hover — used for header navigation and the overflow.
struct IconHoverButton: View {
    let systemName: String
    var size: CGFloat = 13
    var diameter: CGFloat = 26
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(hovering ? Theme.hoverFill : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Animated completion toggle: an open ring that springs into a filled accent disc with a
/// checkmark when completed.
struct Checkbox: View {
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack {
                Circle()
                    .strokeBorder(
                        isOn ? Theme.accent : Color.secondary.opacity(0.55),
                        lineWidth: 1.6
                    )
                    .frame(width: 18, height: 18)

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 18, height: 18)
                    .opacity(isOn ? 1 : 0)
                    .scaleEffect(isOn ? 1 : 0.4)

                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(isOn ? 1 : 0)
                    .scaleEffect(isOn ? 1 : 0.2)
            }
            .animation(Theme.pop, value: isOn)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A slim day-completion bar that animates as tasks are completed.
struct DayProgressBar: View {
    let fraction: Double // 0...1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.trackFill)
                Rectangle()
                    .fill(Theme.progressGradient)
                    .frame(width: max(0, geo.size.width * fraction))
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: fraction)
            }
        }
        .frame(height: 3)
    }
}

/// Subtle accent capsule used for the roll-over action.
struct CapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Theme.accent.opacity(configuration.isPressed ? 0.30 : 0.16))
            )
            .foregroundStyle(Theme.accent)
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.ease, value: configuration.isPressed)
    }
}

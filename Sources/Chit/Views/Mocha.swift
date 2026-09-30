import AppKit
import SwiftUI

enum Mocha {
    static let text = Color(nsColor: nsText)
    static let secondary = Color(nsColor: nsSecondary)
    static let blue = Color(nsColor: nsBlue)
    static let selected = Color(nsColor: nsSelection)
    static let hover = Color(red: 49 / 255, green: 50 / 255, blue: 68 / 255)
    static let nsText = NSColor(srgbRed: 205 / 255, green: 214 / 255, blue: 244 / 255, alpha: 1)
    static let nsSecondary = NSColor(srgbRed: 186 / 255, green: 194 / 255, blue: 222 / 255, alpha: 1)
    static let nsBlue = NSColor(srgbRed: 137 / 255, green: 180 / 255, blue: 250 / 255, alpha: 1)
    static let nsSelection = NSColor(srgbRed: 65 / 255, green: 67 / 255, blue: 85 / 255, alpha: 1)
}

struct CompletionButton: View {
    var completed: Bool
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(completed ? Mocha.blue : Mocha.secondary)
                .frame(width: 22, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(completed ? "Reopen" : "Complete") \(title)")
        .accessibilityValue(completed ? "Completed" : "Incomplete")
        .help(completed ? "Mark incomplete" : "Mark complete")
    }
}

/// Named tabs keep their natural widths and wrap instead of truncating.
struct WrappingStrip: Layout {
    var spacing: CGFloat = 3
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposedWidth = proposal.width ?? 400
        let width = proposedWidth.isFinite ? proposedWidth : subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width + spacing }
        return arrange(width: width, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(width: result.widths[index], height: nil))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint], widths: [CGFloat]) {
        let available = max(24, width)
        var points: [CGPoint] = [], widths: [CGFloat] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let itemWidth = min(ideal.width, available)
            let size = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            if x > 0 && x + itemWidth > available { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); widths.append(itemWidth)
            x += itemWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: available, height: y + rowHeight), points, widths)
    }
}

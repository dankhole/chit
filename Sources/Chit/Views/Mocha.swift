import AppKit
import SwiftUI

enum Mocha {
    static let textRowHeight: CGFloat = 28
    // Text and SF Symbol line boxes center differently. Shift the text's
    // actual layout inset while keeping the row's total padding unchanged.
    static let textAlignmentAdjustment: CGFloat = 1
    static func textRowInset(fontSize: CGFloat) -> CGFloat {
        let lineHeight = NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: fontSize))
        return max(0, (textRowHeight - lineHeight) / 2)
    }
    static func textRowTopInset(fontSize: CGFloat) -> CGFloat {
        max(0, textRowInset(fontSize: fontSize) - textAlignmentAdjustment)
    }
    static func textRowBottomInset(fontSize: CGFloat) -> CGFloat {
        textRowInset(fontSize: fontSize) + textAlignmentAdjustment
    }
    static let text = Color(nsColor: nsText)
    static let secondary = Color(nsColor: nsSecondary)
    static let blue = Color(nsColor: nsBlue)
    static let selected = Color(nsColor: nsSelection)
    static let hover = Color(red: 49 / 255, green: 50 / 255, blue: 68 / 255)
    static let taskStripe = hover.opacity(0.45)
    static let taskStripeFeather: CGFloat = 6
    static let nsText = NSColor(srgbRed: 205 / 255, green: 214 / 255, blue: 244 / 255, alpha: 1)
    static let nsSecondary = NSColor(srgbRed: 186 / 255, green: 194 / 255, blue: 222 / 255, alpha: 1)
    static let nsBlue = NSColor(srgbRed: 137 / 255, green: 180 / 255, blue: 250 / 255, alpha: 1)
    static let nsSelection = NSColor(srgbRed: 65 / 255, green: 67 / 255, blue: 85 / 255, alpha: 1)
}

/// Only the background feathers; row content and its hit areas stay opaque.
struct TaskStripeBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let feather = min(Mocha.taskStripeFeather / max(1, geometry.size.height), 0.5)
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Mocha.taskStripe, location: feather),
                .init(color: Mocha.taskStripe, location: 1 - feather),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
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
                .frame(width: 22, height: Mocha.textRowHeight)
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

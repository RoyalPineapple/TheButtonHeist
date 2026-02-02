import SwiftUI
import AccraCore

struct ElementOverlayView: View {
    let elements: [AccessibilityElementData]
    let selectedElement: AccessibilityElementData?
    let imageSize: CGSize
    let viewSize: CGSize
    let onElementTapped: (AccessibilityElementData) -> Void
    let onElementDoubleTapped: (AccessibilityElementData) -> Void

    private var scale: CGFloat {
        viewSize.width / imageSize.width
    }

    var body: some View {
        Canvas { context, size in
            for element in elements {
                let isSelected = selectedElement?.traversalIndex == element.traversalIndex
                let rect = scaledRect(for: element)
                let color = colorFor(element: element, isSelected: isSelected)

                // Fill
                context.fill(
                    Path(rect),
                    with: .color(color.opacity(isSelected ? 0.3 : 0.1))
                )

                // Stroke
                context.stroke(
                    Path(rect),
                    with: .color(isSelected ? .yellow : color),
                    lineWidth: isSelected ? 3 : 1
                )
            }
        }
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2)
                .onEnded { _ in }
                .simultaneously(with: SpatialTapGesture(count: 2))
                .onEnded { value in
                    if let location = value.second?.location,
                       let element = elementAt(location) {
                        onElementDoubleTapped(element)
                    }
                }
        )
        .onTapGesture { location in
            if let element = elementAt(location) {
                onElementTapped(element)
            }
        }
    }

    private func scaledRect(for element: AccessibilityElementData) -> CGRect {
        CGRect(
            x: element.frameX * scale,
            y: element.frameY * scale,
            width: element.frameWidth * scale,
            height: element.frameHeight * scale
        )
    }

    private func elementAt(_ point: CGPoint) -> AccessibilityElementData? {
        // Search in reverse order (topmost elements first)
        for element in elements.reversed() {
            let rect = scaledRect(for: element)
            if rect.contains(point) {
                return element
            }
        }
        return nil
    }

    private func colorFor(element: AccessibilityElementData, isSelected: Bool) -> Color {
        if isSelected { return .yellow }
        let traits = element.traits
        if traits.contains("button") { return .blue }
        if traits.contains("link") { return .purple }
        if traits.contains("textField") || traits.contains("searchField") { return .green }
        if traits.contains("adjustable") { return .orange }
        if traits.contains("staticText") { return .gray }
        if traits.contains("image") { return .pink }
        if traits.contains("header") { return .red }
        return .cyan
    }
}

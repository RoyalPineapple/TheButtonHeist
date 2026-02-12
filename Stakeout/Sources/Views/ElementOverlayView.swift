import SwiftUI
import ButtonHeist

struct ElementOverlayView: View {
    let elements: [UIElement]
    let selectedElement: UIElement?
    let imageSize: CGSize
    let viewSize: CGSize
    let onElementTapped: (UIElement) -> Void
    let onElementDoubleTapped: (UIElement) -> Void

    private var scale: CGFloat {
        viewSize.width / imageSize.width
    }

    var body: some View {
        Canvas { context, _ in
            for element in elements {
                let isSelected = selectedElement?.order == element.order
                let rect = scaledRect(for: element)
                let color = ElementStyling.color(for: element)

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

    private func scaledRect(for element: UIElement) -> CGRect {
        CGRect(
            x: element.frameX * scale,
            y: element.frameY * scale,
            width: element.frameWidth * scale,
            height: element.frameHeight * scale
        )
    }

    private func elementAt(_ point: CGPoint) -> UIElement? {
        // Search in reverse order (topmost elements first)
        for element in elements.reversed() {
            let rect = scaledRect(for: element)
            if rect.contains(point) {
                return element
            }
        }
        return nil
    }

}

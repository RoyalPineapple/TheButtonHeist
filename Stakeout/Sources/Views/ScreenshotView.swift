import SwiftUI
import AppKit
import ButtonHeist

struct ScreenshotView: View {
    let screenshotPayload: ScreenshotPayload?
    let elements: [UIElement]
    @Binding var selectedElement: UIElement?
    let onActivate: (UIElement) -> Void

    @State private var showingActionFeedback = false

    var body: some View {
        if let payload = screenshotPayload,
           let image = decodeScreenshot(payload) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .overlay {
                    GeometryReader { geo in
                        ElementOverlayView(
                            elements: elements,
                            selectedElement: selectedElement,
                            imageSize: CGSize(width: payload.width, height: payload.height),
                            viewSize: geo.size,
                            onElementTapped: { element in
                                selectedElement = element
                            },
                            onElementDoubleTapped: { element in
                                selectedElement = element
                                withAnimation(.easeOut(duration: 0.1)) {
                                    showingActionFeedback = true
                                }
                                onActivate(element)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation(.easeIn(duration: 0.1)) {
                                        showingActionFeedback = false
                                    }
                                }
                            }
                        )
                    }
                }
                .overlay {
                    if showingActionFeedback {
                        Color.yellow.opacity(0.3)
                            .transition(.opacity)
                    }
                }
        } else {
            ContentUnavailableView(
                "No Screenshot",
                systemImage: "photo",
                description: Text("Waiting for screenshot from device...")
            )
        }
    }

    private func decodeScreenshot(_ payload: ScreenshotPayload) -> NSImage? {
        guard let data = Data(base64Encoded: payload.pngData) else { return nil }
        return NSImage(data: data)
    }
}

#Preview {
    @Previewable @State var selectedElement: UIElement? = nil
    ScreenshotView(
        screenshotPayload: nil,
        elements: [],
        selectedElement: $selectedElement,
        onActivate: { _ in }
    )
}

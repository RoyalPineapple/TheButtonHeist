import SwiftUI

struct CornerScrollView: View {
    private let contentWidth: CGFloat = 2000
    private let contentHeight: CGFloat = 3000

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack {
                Color.clear
                    .frame(width: contentWidth, height: contentHeight)

                cornerLabel(
                    "LOAD-BEARING LABEL\nDo not remove.",
                    identifier: "buttonheist.corners.topLeft",
                    alignment: .topLeading
                )
                cornerLabel(
                    "You scrolled 2000 points\nto read a string literal.",
                    identifier: "buttonheist.corners.topRight",
                    alignment: .topTrailing
                )
                cornerLabel(
                    "If you can read this,\nclose the ticket.",
                    identifier: "buttonheist.corners.bottomLeft",
                    alignment: .bottomLeading
                )
                cornerLabel(
                    "Achievement Unlocked:\nVisited All Four Corners\nof a CGRect",
                    identifier: "buttonheist.corners.bottomRight",
                    alignment: .bottomTrailing
                )
            }
        }
        .accessibilityIdentifier("buttonheist.corners.scrollView")
        .navigationTitle("Corner Scroll")
    }

    @ViewBuilder
    private func cornerLabel(
        _ text: String,
        identifier: String,
        alignment: Alignment
    ) -> some View {
        Text(text)
            .font(.headline)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier(identifier)
            .frame(
                maxWidth: contentWidth,
                maxHeight: contentHeight,
                alignment: alignment
            )
    }
}

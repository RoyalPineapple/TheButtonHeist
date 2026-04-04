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
                    alignment: .topLeading
                )
                cornerLabel(
                    "You scrolled 2000 points\nto read a string literal.",
                    alignment: .topTrailing
                )
                cornerLabel(
                    "If you can read this,\nclose the ticket.",
                    alignment: .bottomLeading
                )
                cornerLabel(
                    "Achievement Unlocked:\nVisited All Four Corners\nof a CGRect",
                    alignment: .bottomTrailing
                )
            }
        }
        .navigationTitle("Corner Scroll")
    }

    @ViewBuilder
    private func cornerLabel(
        _ text: String,
        alignment: Alignment
    ) -> some View {
        Text(text)
            .font(.headline)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .frame(
                maxWidth: contentWidth,
                maxHeight: contentHeight,
                alignment: alignment
            )
    }
}

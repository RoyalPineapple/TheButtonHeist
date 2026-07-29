import SwiftUI
import UIKit

struct AccessibilityNotificationProbeView: View {
    private struct Page: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let color: Color
    }

    private let pages = [
        Page(id: 0, title: "Page One", detail: "Crimson", color: .red),
        Page(id: 1, title: "Page Two", detail: "Emerald", color: .green),
        Page(id: 2, title: "Page Three", detail: "Cobalt", color: .blue),
    ]

    @State private var selectedPage = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Hand-Rolled UIKit Values")
                        .font(.headline)

                    Text("Tap each bare NSObject to mutate its accessibilityValue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    UIKitAccessibilityValueProbe()
                        .frame(height: 390)
                }
                .padding(.horizontal)

                Divider()

                Text("Page \(selectedPage + 1) of \(pages.count)")
                    .font(.headline)

                TabView(selection: $selectedPage) {
                    ForEach(pages) { page in
                        VStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(page.color.gradient)
                                .frame(height: 320)
                                .overlay {
                                    Text(page.title)
                                        .font(.largeTitle.bold())
                                        .foregroundStyle(.white)
                                }
                                .accessibilityLabel("\(page.title), \(page.detail)")

                            Text("Swipe horizontally to cross a page boundary.")
                        }
                        .padding(.horizontal)
                        .tag(page.id)
                    }
                }
                .frame(height: 400)
                .tabViewStyle(.page(indexDisplayMode: .always))

                HStack {
                    Button("Previous Page") {
                        selectedPage -= 1
                    }
                    .disabled(selectedPage == pages.startIndex)

                    Spacer()

                    Button("Next Page") {
                        selectedPage += 1
                    }
                    .disabled(selectedPage == pages.index(before: pages.endIndex))
                }
                .padding(.horizontal)

                Button("Post Page Scrolled") {
                    UIAccessibility.post(
                        notification: .pageScrolled,
                        argument: "Page \(selectedPage + 1) of \(pages.count)"
                    )
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Notification Probe")
    }
}

#Preview {
    NavigationStack {
        AccessibilityNotificationProbeView()
    }
}

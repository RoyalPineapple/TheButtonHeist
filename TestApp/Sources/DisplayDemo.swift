import SwiftUI

struct DisplayDemo: View {
    private static let appleAccessibilityURL = URL(string: "https://developer.apple.com/accessibility/")

    var body: some View {
        Form {
            Section("Display") {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .imageScale(.large)
                    .accessibilityLabel("Favorite star")

                Label("Information", systemImage: "info.circle")

                if let url = Self.appleAccessibilityURL {
                    Link("Apple Accessibility", destination: url)
                }

                Text("Section Header Style")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text("Static informational text that describes the demo app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Display")
    }
}

#Preview {
    DisplayDemo()
}

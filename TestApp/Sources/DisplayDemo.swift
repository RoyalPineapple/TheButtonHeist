import SwiftUI

struct DisplayDemo: View {
    var body: some View {
        Form {
            Section("Display") {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .imageScale(.large)
                    .accessibilityLabel("Favorite star")
                    .accessibilityIdentifier("buttonheist.display.starImage")

                Label("Information", systemImage: "info.circle")
                    .accessibilityIdentifier("buttonheist.display.infoLabel")

                Link("Apple Accessibility", destination: URL(string: "https://developer.apple.com/accessibility/")!)
                    .accessibilityIdentifier("buttonheist.display.learnMoreLink")

                Text("Section Header Style")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("buttonheist.display.headerText")

                Text("Static informational text that describes the demo app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("buttonheist.display.staticText")
            }
        }
        .navigationTitle("Display")
    }
}

#Preview {
    DisplayDemo()
}

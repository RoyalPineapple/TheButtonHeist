import SwiftUI

struct DisclosureGroupingDemo: View {
    @State private var isAdvancedExpanded = false

    var body: some View {
        Form {
            Section("Disclosure & Grouping") {
                DisclosureGroup("Advanced Settings", isExpanded: $isAdvancedExpanded) {
                    Toggle("Enable notifications", isOn: .constant(true))
                        .accessibilityIdentifier("buttonheist.disclosure.notifToggle")

                    Toggle("Dark mode", isOn: .constant(false))
                        .accessibilityIdentifier("buttonheist.disclosure.darkModeToggle")
                }
                .accessibilityIdentifier("buttonheist.disclosure.advancedGroup")

                LabeledContent("Version", value: "0.0.1")
                    .accessibilityIdentifier("buttonheist.disclosure.versionLabel")

                LabeledContent("Build", value: "42")
                    .accessibilityIdentifier("buttonheist.disclosure.buildLabel")
            }
        }
        .navigationTitle("Disclosure & Grouping")
    }
}

#Preview {
    DisclosureGroupingDemo()
}

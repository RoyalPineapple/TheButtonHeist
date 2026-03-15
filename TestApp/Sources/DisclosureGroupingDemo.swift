import SwiftUI

struct DisclosureGroupingDemo: View {
    @State private var isAdvancedExpanded = false
    @State private var notificationsEnabled = true
    @State private var darkModeEnabled = false

    var body: some View {
        Form {
            Section("Disclosure & Grouping") {
                DisclosureGroup("Advanced Settings", isExpanded: $isAdvancedExpanded) {
                    Toggle("Enable notifications", isOn: $notificationsEnabled)
                        .accessibilityIdentifier("buttonheist.disclosure.notifToggle")

                    Toggle("Dark mode", isOn: $darkModeEnabled)
                        .accessibilityIdentifier("buttonheist.disclosure.darkModeToggle")
                }
                // Note: Do NOT set accessibilityIdentifier on DisclosureGroup —
                // SwiftUI propagates it to children, overriding their own identifiers.

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

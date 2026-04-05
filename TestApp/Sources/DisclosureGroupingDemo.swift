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

                    Toggle("Dark mode", isOn: $darkModeEnabled)
                }

                LabeledContent("Version", value: "2026.04.05")

                LabeledContent("Build", value: "42")
            }
        }
        .navigationTitle("Disclosure & Grouping")
    }
}

#Preview {
    DisclosureGroupingDemo()
}

import SwiftUI

struct ControlsDemoView: View {
    var body: some View {
        List {
            NavigationLink("Text Input") { TextInputDemo() }
            NavigationLink("Toggles & Pickers") { TogglePickerDemo() }
            NavigationLink("Buttons & Actions") { ButtonsActionsDemo() }
            NavigationLink("Adjustable Controls") { AdjustableControlsDemo() }
            NavigationLink("Disclosure & Grouping") { DisclosureGroupingDemo() }
            NavigationLink("Alerts & Sheets") { AlertsSheetDemo() }
            NavigationLink("Display") { DisplayDemo() }
        }
        .navigationTitle("Controls Demo")
    }
}

#Preview {
    NavigationStack {
        ControlsDemoView()
    }
}

import SwiftUI

struct ButtonsActionsDemo: View {
    @State private var tapCount = 0
    @State private var lastAction = "None"

    var body: some View {
        Form {
            Section("Buttons & Actions") {
                Text("Tap count: \(tapCount)")
                    .accessibilityIdentifier("buttonheist.actions.tapCountLabel")

                Text("Last action: \(lastAction)")
                    .accessibilityIdentifier("buttonheist.actions.lastActionLabel")

                Button("Primary Button") {
                    tapCount += 1
                    lastAction = "Primary tapped"
                    NSLog("[ControlsDemo] Primary button tapped, count: %d", tapCount)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("buttonheist.actions.primaryButton")

                Button("Bordered Button") {
                    tapCount += 1
                    lastAction = "Bordered tapped"
                    NSLog("[ControlsDemo] Bordered button tapped")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("buttonheist.actions.borderedButton")

                Button("Destructive Button", role: .destructive) {
                    lastAction = "Destructive tapped"
                    NSLog("[ControlsDemo] Destructive button tapped")
                }
                .accessibilityIdentifier("buttonheist.actions.destructiveButton")

                Button("Disabled Button") { }
                    .disabled(true)
                    .accessibilityIdentifier("buttonheist.actions.disabledButton")

                Menu("Options Menu") {
                    Button("Option A") {
                        lastAction = "Menu: Option A"
                        NSLog("[ControlsDemo] Menu option A selected")
                    }
                    Button("Option B") {
                        lastAction = "Menu: Option B"
                        NSLog("[ControlsDemo] Menu option B selected")
                    }
                    Button("Delete", role: .destructive) {
                        lastAction = "Menu: Delete"
                        NSLog("[ControlsDemo] Menu delete selected")
                    }
                }
                .accessibilityIdentifier("buttonheist.actions.optionsMenu")

                Text("Swipe actions item")
                    .accessibilityIdentifier("buttonheist.actions.customActionsItem")
                    .accessibilityAction(named: "Favorite") {
                        lastAction = "Custom action: Favorite"
                        NSLog("[ControlsDemo] Custom action: Favorite")
                    }
                    .accessibilityAction(named: "Share") {
                        lastAction = "Custom action: Share"
                        NSLog("[ControlsDemo] Custom action: Share")
                    }
            }
        }
        .navigationTitle("Buttons & Actions")
    }
}

#Preview {
    ButtonsActionsDemo()
}

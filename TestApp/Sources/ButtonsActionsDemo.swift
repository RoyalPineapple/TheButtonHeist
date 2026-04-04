import SwiftUI

struct ButtonsActionsDemo: View {
    @State private var tapCount = 0
    @State private var lastAction = "None"

    var body: some View {
        Form {
            Section("Buttons & Actions") {
                Text("Tap count: \(tapCount)")

                Text("Last action: \(lastAction)")

                Button("Primary Button") {
                    tapCount += 1
                    lastAction = "Primary tapped"
                    NSLog("[ControlsDemo] Primary button tapped, count: %d", tapCount)
                }
                .buttonStyle(.borderedProminent)

                Button("Bordered Button") {
                    tapCount += 1
                    lastAction = "Bordered tapped"
                    NSLog("[ControlsDemo] Bordered button tapped")
                }
                .buttonStyle(.bordered)

                Button("Destructive Button", role: .destructive) {
                    lastAction = "Destructive tapped"
                    NSLog("[ControlsDemo] Destructive button tapped")
                }

                Button("Disabled Button") { }
                    .disabled(true)

                // Menu temporarily replaced with a Button that shows a confirmation dialog
                // to work around AccessibilitySnapshotParser hanging on SwiftUI Menu internals
                Button("Options Menu") {
                    lastAction = "Menu tapped"
                    NSLog("[ControlsDemo] Options menu tapped")
                }
                .contextMenu {
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

                Text("Swipe actions item")
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

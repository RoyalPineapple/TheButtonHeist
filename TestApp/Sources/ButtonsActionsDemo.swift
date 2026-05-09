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
                }
                .buttonStyle(.borderedProminent)

                Button("Bordered Button") {
                    tapCount += 1
                    lastAction = "Bordered tapped"
                }
                .buttonStyle(.bordered)

                Button("Destructive Button", role: .destructive) {
                    lastAction = "Destructive tapped"
                }

                Button("Disabled Button") { }
                    .disabled(true)

                Button("Options Menu") {
                    lastAction = "Menu tapped"
                }
                .contextMenu {
                    Button("Option A") {
                        lastAction = "Menu: Option A"
                    }
                    Button("Option B") {
                        lastAction = "Menu: Option B"
                    }
                    Button("Delete", role: .destructive) {
                        lastAction = "Menu: Delete"
                    }
                }

                Text("Swipe actions item")
                    .accessibilityAction(named: "Favorite") {
                        lastAction = "Custom action: Favorite"
                    }
                    .accessibilityAction(named: "Share") {
                        lastAction = "Custom action: Share"
                    }
            }
        }
        .navigationTitle("Buttons & Actions")
    }
}

#Preview {
    ButtonsActionsDemo()
}

import SwiftUI

struct AlertsSheetDemo: View {
    @State private var showAlert = false
    @State private var showConfirmation = false
    @State private var showSheet = false
    @State private var lastAction = "None"

    var body: some View {
        Form {
            Section("Alerts & Sheets") {
                Button("Show Alert") {
                    showAlert = true
                    lastAction = "Alert shown"
                    NSLog("[ControlsDemo] Alert presented")
                }
                .accessibilityIdentifier("buttonheist.presentation.alertButton")

                Button("Show Confirmation") {
                    showConfirmation = true
                    lastAction = "Confirmation shown"
                    NSLog("[ControlsDemo] Confirmation dialog presented")
                }
                .accessibilityIdentifier("buttonheist.presentation.confirmButton")

                Button("Show Sheet") {
                    showSheet = true
                    lastAction = "Sheet shown"
                    NSLog("[ControlsDemo] Sheet presented")
                }
                .accessibilityIdentifier("buttonheist.presentation.sheetButton")
            }
            .alert("Alert Title", isPresented: $showAlert) {
                Button("OK") {
                    lastAction = "Alert: OK"
                    NSLog("[ControlsDemo] Alert OK tapped")
                }
            } message: {
                Text("This is an alert message.")
            }
            .confirmationDialog("Choose Action", isPresented: $showConfirmation) {
                Button("Save") {
                    lastAction = "Confirmation: Save"
                    NSLog("[ControlsDemo] Confirmation: Save")
                }
                Button("Discard", role: .destructive) {
                    lastAction = "Confirmation: Discard"
                    NSLog("[ControlsDemo] Confirmation: Discard")
                }
                Button("Cancel", role: .cancel) {
                    lastAction = "Confirmation: Cancel"
                }
            }
            .sheet(isPresented: $showSheet) {
                VStack(spacing: 20) {
                    Text("Sheet Content")
                        .font(.headline)
                        .accessibilityIdentifier("buttonheist.presentation.sheetTitle")

                    Button("Dismiss") {
                        showSheet = false
                        lastAction = "Sheet dismissed"
                        NSLog("[ControlsDemo] Sheet dismissed")
                    }
                    .accessibilityIdentifier("buttonheist.presentation.sheetDismiss")
                }
                .padding()
            }

            Section {
                Text("Last action: \(lastAction)")
                    .accessibilityIdentifier("buttonheist.presentation.lastActionLabel")
            }
        }
        .navigationTitle("Alerts & Sheets")
    }
}

#Preview {
    AlertsSheetDemo()
}

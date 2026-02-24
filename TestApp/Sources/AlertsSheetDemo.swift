import SwiftUI

struct AlertsSheetDemo: View {
    @State private var showAlert = false
    @State private var showTwoButtonAlert = false
    @State private var showDestructiveAlert = false
    @State private var showTextFieldAlert = false
    @State private var showConfirmation = false
    @State private var showSheet = false
    @State private var lastAction = "None"
    @State private var alertTextInput = ""

    var body: some View {
        Form {
            Section("Simple Alerts") {
                Button("Show Alert") {
                    showAlert = true
                    lastAction = "Alert shown"
                    NSLog("[AlertsDemo] Alert presented")
                }
                .accessibilityIdentifier("buttonheist.alert.simple")

                Button("Show Two-Button Alert") {
                    showTwoButtonAlert = true
                    lastAction = "Two-button alert shown"
                    NSLog("[AlertsDemo] Two-button alert presented")
                }
                .accessibilityIdentifier("buttonheist.alert.twoButton")

                Button("Show Destructive Alert") {
                    showDestructiveAlert = true
                    lastAction = "Destructive alert shown"
                    NSLog("[AlertsDemo] Destructive alert presented")
                }
                .accessibilityIdentifier("buttonheist.alert.destructive")

                Button("Show Text Field Alert") {
                    alertTextInput = ""
                    showTextFieldAlert = true
                    lastAction = "Text field alert shown"
                    NSLog("[AlertsDemo] Text field alert presented")
                }
                .accessibilityIdentifier("buttonheist.alert.textField")
            }
            .alert("Alert Title", isPresented: $showAlert) {
                Button("OK") {
                    lastAction = "Alert: OK"
                    NSLog("[AlertsDemo] Alert OK tapped")
                }
            } message: {
                Text("This is a simple alert with one button.")
            }
            .alert("Confirm Action", isPresented: $showTwoButtonAlert) {
                Button("Cancel", role: .cancel) {
                    lastAction = "Two-button: Cancel"
                    NSLog("[AlertsDemo] Two-button Cancel tapped")
                }
                Button("Confirm") {
                    lastAction = "Two-button: Confirm"
                    NSLog("[AlertsDemo] Two-button Confirm tapped")
                }
            } message: {
                Text("Do you want to proceed with this action?")
            }
            .alert("Delete Item", isPresented: $showDestructiveAlert) {
                Button("Cancel", role: .cancel) {
                    lastAction = "Destructive: Cancel"
                    NSLog("[AlertsDemo] Destructive Cancel tapped")
                }
                Button("Delete", role: .destructive) {
                    lastAction = "Destructive: Delete"
                    NSLog("[AlertsDemo] Destructive Delete tapped")
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Enter Name", isPresented: $showTextFieldAlert) {
                TextField("Name", text: $alertTextInput)
                    .accessibilityIdentifier("buttonheist.alert.textFieldInput")
                Button("Cancel", role: .cancel) {
                    lastAction = "TextField: Cancel"
                    NSLog("[AlertsDemo] TextField Cancel tapped")
                }
                Button("Submit") {
                    lastAction = "TextField: Submit (\(alertTextInput))"
                    NSLog("[AlertsDemo] TextField Submit tapped: \(alertTextInput)")
                }
            } message: {
                Text("Please enter your name.")
            }

            Section("Dialogs & Sheets") {
                Button("Show Confirmation Dialog") {
                    showConfirmation = true
                    lastAction = "Confirmation shown"
                    NSLog("[AlertsDemo] Confirmation dialog presented")
                }
                .accessibilityIdentifier("buttonheist.alert.confirmation")

                Button("Show Sheet") {
                    showSheet = true
                    lastAction = "Sheet shown"
                    NSLog("[AlertsDemo] Sheet presented")
                }
                .accessibilityIdentifier("buttonheist.alert.sheet")
            }
            .confirmationDialog("Choose Action", isPresented: $showConfirmation) {
                Button("Save") {
                    lastAction = "Confirmation: Save"
                    NSLog("[AlertsDemo] Confirmation: Save")
                }
                Button("Discard", role: .destructive) {
                    lastAction = "Confirmation: Discard"
                    NSLog("[AlertsDemo] Confirmation: Discard")
                }
                Button("Cancel", role: .cancel) {
                    lastAction = "Confirmation: Cancel"
                }
            }
            .sheet(isPresented: $showSheet) {
                VStack(spacing: 20) {
                    Text("Sheet Content")
                        .font(.headline)
                        .accessibilityIdentifier("buttonheist.alert.sheetTitle")

                    Button("Dismiss") {
                        showSheet = false
                        lastAction = "Sheet dismissed"
                        NSLog("[AlertsDemo] Sheet dismissed")
                    }
                    .accessibilityIdentifier("buttonheist.alert.sheetDismiss")
                }
                .padding()
            }

            Section {
                Text("Last action: \(lastAction)")
                    .accessibilityIdentifier("buttonheist.alert.lastAction")
            }
        }
        .navigationTitle("Alerts & Sheets")
    }
}

#Preview {
    AlertsSheetDemo()
}

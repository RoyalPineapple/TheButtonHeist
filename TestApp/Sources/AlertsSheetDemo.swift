import SwiftUI

struct AlertsSheetDemo: View {
    @State private var activePresentation: Presentation?
    @State private var lastAction = "None"
    @State private var alertTextInput = ""

    enum Presentation {
        case simpleAlert
        case twoButtonAlert
        case destructiveAlert
        case textFieldAlert
        case confirmationDialog
        case sheet
    }

    private func isPresented(_ kind: Presentation) -> Binding<Bool> {
        Binding(
            get: { activePresentation == kind },
            set: { if !$0 { activePresentation = nil } }
        )
    }

    var body: some View {
        Form {
            Section("Simple Alerts") {
                Button("Show Alert") {
                    activePresentation = .simpleAlert
                    lastAction = "Alert shown"
                }

                Button("Show Two-Button Alert") {
                    activePresentation = .twoButtonAlert
                    lastAction = "Two-button alert shown"
                }

                Button("Show Destructive Alert") {
                    activePresentation = .destructiveAlert
                    lastAction = "Destructive alert shown"
                }

                Button("Show Text Field Alert") {
                    alertTextInput = ""
                    activePresentation = .textFieldAlert
                    lastAction = "Text field alert shown"
                }
            }
            .alert("Alert Title", isPresented: isPresented(.simpleAlert)) {
                Button("OK") {
                    lastAction = "Alert: OK"
                }
            } message: {
                Text("This is a simple alert with one button.")
            }
            .alert("Confirm Action", isPresented: isPresented(.twoButtonAlert)) {
                Button("Cancel", role: .cancel) {
                    lastAction = "Two-button: Cancel"
                }
                Button("Confirm") {
                    lastAction = "Two-button: Confirm"
                }
            } message: {
                Text("Do you want to proceed with this action?")
            }
            .alert("Delete Item", isPresented: isPresented(.destructiveAlert)) {
                Button("Cancel", role: .cancel) {
                    lastAction = "Destructive: Cancel"
                }
                Button("Delete", role: .destructive) {
                    lastAction = "Destructive: Delete"
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Enter Name", isPresented: isPresented(.textFieldAlert)) {
                TextField("Name", text: $alertTextInput)
                Button("Cancel", role: .cancel) {
                    lastAction = "TextField: Cancel"
                }
                Button("Submit") {
                    lastAction = "TextField: Submit (\(alertTextInput))"
                }
            } message: {
                Text("Please enter your name.")
            }

            Section("Dialogs & Sheets") {
                Button("Show Confirmation Dialog") {
                    activePresentation = .confirmationDialog
                    lastAction = "Confirmation shown"
                }

                Button("Show Sheet") {
                    activePresentation = .sheet
                    lastAction = "Sheet shown"
                }
            }
            .confirmationDialog("Choose Action", isPresented: isPresented(.confirmationDialog)) {
                Button("Save") {
                    lastAction = "Confirmation: Save"
                }
                Button("Discard", role: .destructive) {
                    lastAction = "Confirmation: Discard"
                }
                Button("Cancel", role: .cancel) {
                    lastAction = "Confirmation: Cancel"
                }
            }
            .sheet(isPresented: isPresented(.sheet)) {
                VStack(spacing: 20) {
                    Text("Sheet Content")
                        .font(.headline)

                    Button("Dismiss") {
                        activePresentation = nil
                        lastAction = "Sheet dismissed"
                    }
                }
                .padding()
            }

            Section {
                Text("Last action: \(lastAction)")
            }
        }
        .navigationTitle("Alerts & Sheets")
    }
}

#Preview {
    AlertsSheetDemo()
}

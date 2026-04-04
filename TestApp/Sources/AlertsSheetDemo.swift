import SwiftUI

struct AlertsSheetDemo: View {
    @State private var activePresentation: Presentation?
    @State private var lastAction = "None"
    @State private var alertTextInput = ""

    enum Presentation: Identifiable {
        case simpleAlert
        case twoButtonAlert
        case destructiveAlert
        case textFieldAlert
        case confirmationDialog
        case sheet

        var id: String {
            switch self {
            case .simpleAlert: return "simple"
            case .twoButtonAlert: return "twoButton"
            case .destructiveAlert: return "destructive"
            case .textFieldAlert: return "textField"
            case .confirmationDialog: return "confirmation"
            case .sheet: return "sheet"
            }
        }
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
                    NSLog("[AlertsDemo] Alert presented")
                }

                Button("Show Two-Button Alert") {
                    activePresentation = .twoButtonAlert
                    lastAction = "Two-button alert shown"
                    NSLog("[AlertsDemo] Two-button alert presented")
                }

                Button("Show Destructive Alert") {
                    activePresentation = .destructiveAlert
                    lastAction = "Destructive alert shown"
                    NSLog("[AlertsDemo] Destructive alert presented")
                }

                Button("Show Text Field Alert") {
                    alertTextInput = ""
                    activePresentation = .textFieldAlert
                    lastAction = "Text field alert shown"
                    NSLog("[AlertsDemo] Text field alert presented")
                }
            }
            .alert("Alert Title", isPresented: isPresented(.simpleAlert)) {
                Button("OK") {
                    lastAction = "Alert: OK"
                    NSLog("[AlertsDemo] Alert OK tapped")
                }
            } message: {
                Text("This is a simple alert with one button.")
            }
            .alert("Confirm Action", isPresented: isPresented(.twoButtonAlert)) {
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
            .alert("Delete Item", isPresented: isPresented(.destructiveAlert)) {
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
            .alert("Enter Name", isPresented: isPresented(.textFieldAlert)) {
                TextField("Name", text: $alertTextInput)
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
                    activePresentation = .confirmationDialog
                    lastAction = "Confirmation shown"
                    NSLog("[AlertsDemo] Confirmation dialog presented")
                }

                Button("Show Sheet") {
                    activePresentation = .sheet
                    lastAction = "Sheet shown"
                    NSLog("[AlertsDemo] Sheet presented")
                }
            }
            .confirmationDialog("Choose Action", isPresented: isPresented(.confirmationDialog)) {
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
            .sheet(isPresented: isPresented(.sheet)) {
                VStack(spacing: 20) {
                    Text("Sheet Content")
                        .font(.headline)

                    Button("Dismiss") {
                        activePresentation = nil
                        lastAction = "Sheet dismissed"
                        NSLog("[AlertsDemo] Sheet dismissed")
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

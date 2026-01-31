import SwiftUI

struct ContentView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var isSubscribed = false
    @State private var selectedOption = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("nameField")

                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .accessibilityIdentifier("emailField")
                }

                Section("Preferences") {
                    Toggle("Subscribe to newsletter", isOn: $isSubscribed)
                        .accessibilityIdentifier("subscribeToggle")

                    Picker("Notification frequency", selection: $selectedOption) {
                        Text("Daily").tag(0)
                        Text("Weekly").tag(1)
                        Text("Monthly").tag(2)
                    }
                    .accessibilityIdentifier("frequencyPicker")
                }

                Section {
                    Button("Submit") {
                        // Action
                    }
                    .accessibilityIdentifier("submitButton")

                    Button("Cancel", role: .destructive) {
                        // Action
                    }
                    .accessibilityIdentifier("cancelButton")
                }

                Section("Information") {
                    Label("This is a demo app for testing accessibility inspection.", systemImage: "info.circle")
                        .accessibilityIdentifier("infoLabel")

                    Link("Learn more about accessibility", destination: URL(string: "https://developer.apple.com/accessibility/")!)
                        .accessibilityIdentifier("learnMoreLink")
                }
            }
            .navigationTitle("Accessibility Demo")
        }
    }
}

#Preview {
    ContentView()
}

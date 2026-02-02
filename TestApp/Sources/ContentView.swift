import SwiftUI

struct ContentView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var isSubscribed = false
    @State private var selectedOption = 0
    @State private var sliderValue = 50.0
    @State private var stepperValue = 0
    @State private var tapCount = 0
    @State private var lastAction = "None"

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("accra.form.nameTextField")

                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .accessibilityIdentifier("accra.form.emailTextField")
                }

                Section("Preferences") {
                    Toggle("Subscribe to newsletter", isOn: $isSubscribed)
                        .accessibilityIdentifier("accra.prefs.subscribeToggle")
                        .onChange(of: isSubscribed) { _, newValue in
                            NSLog("[ContentView] 🔀 Toggle CHANGED to: %@", newValue ? "ON" : "OFF")
                        }

                    Picker("Notification frequency", selection: $selectedOption) {
                        Text("Daily").tag(0)
                        Text("Weekly").tag(1)
                        Text("Monthly").tag(2)
                    }
                    .accessibilityIdentifier("accra.prefs.frequencyPicker")
                }

                Section("Action Testing") {
                    Text("Tap count: \(tapCount)")
                        .accessibilityIdentifier("accra.action.tapCountLabel")

                    Text("Last action: \(lastAction)")
                        .accessibilityIdentifier("accra.action.lastActionLabel")

                    Button("Test Button") {
                        tapCount += 1
                        lastAction = "Button tapped"
                        NSLog("[ContentView] 🔘 Test Button TAPPED! Count: %d", tapCount)
                    }
                    .accessibilityIdentifier("accra.action.testButton")

                    Slider(value: $sliderValue, in: 0...100, step: 10) {
                        Text("Volume")
                    }
                    .accessibilityIdentifier("accra.action.volumeSlider")
                    .accessibilityValue("\(Int(sliderValue))")
                    .onChange(of: sliderValue) { _, newValue in
                        lastAction = "Slider changed to \(Int(newValue))"
                        NSLog("[ContentView] 🎚️ Slider CHANGED to: %d", Int(newValue))
                    }

                    Stepper("Quantity: \(stepperValue)", value: $stepperValue, in: 0...10)
                        .accessibilityIdentifier("accra.action.quantityStepper")
                        .onChange(of: stepperValue) { _, newValue in
                            lastAction = "Stepper changed to \(newValue)"
                            NSLog("[ContentView] ➕ Stepper CHANGED to: %d", newValue)
                        }
                }

                Section {
                    Button("Submit") {
                        lastAction = "Submit tapped"
                        NSLog("[ContentView] ✅ Submit Button TAPPED!")
                    }
                    .accessibilityIdentifier("accra.buttons.submitButton")

                    Button("Cancel", role: .destructive) {
                        lastAction = "Cancel tapped"
                    }
                    .accessibilityIdentifier("accra.buttons.cancelButton")
                }

                Section("Information") {
                    Label("This is a demo app for testing accessibility inspection.", systemImage: "info.circle")
                        .accessibilityIdentifier("accra.info.infoLabel")

                    Link("Learn more about accessibility", destination: URL(string: "https://developer.apple.com/accessibility/")!)
                        .accessibilityIdentifier("accra.info.learnMoreLink")
                }
            }
            .navigationTitle("Accessibility Demo")
        }
    }
}

#Preview {
    ContentView()
}

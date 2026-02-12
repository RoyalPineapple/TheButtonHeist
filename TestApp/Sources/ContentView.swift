import SwiftUI
import UIKit

struct ContentView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var isSubscribed = false
    @State private var selectedOption = 0
    @State private var sliderValue = 50.0
    @State private var stepperValue = 0
    @State private var tapCount = 0
    @State private var lastAction = "None"
    @State private var isButtonPressed = false

    var body: some View {
        Form {
                Section("Personal Information") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("buttonheist.form.nameTextField")

                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .accessibilityIdentifier("buttonheist.form.emailTextField")
                }

                Section("Preferences") {
                    Toggle("Subscribe to newsletter", isOn: $isSubscribed)
                        .accessibilityIdentifier("buttonheist.prefs.subscribeToggle")
                        .onChange(of: isSubscribed) { _, newValue in
                            NSLog("[ContentView] 🔀 Toggle CHANGED to: %@", newValue ? "ON" : "OFF")
                        }

                    Picker("Notification frequency", selection: $selectedOption) {
                        Text("Daily").tag(0)
                        Text("Weekly").tag(1)
                        Text("Monthly").tag(2)
                    }
                    .accessibilityIdentifier("buttonheist.prefs.frequencyPicker")
                }

                Section("Action Testing") {
                    Text("Tap count: \(tapCount)")
                        .accessibilityIdentifier("buttonheist.action.tapCountLabel")

                    Text("Last action: \(lastAction)")
                        .accessibilityIdentifier("buttonheist.action.lastActionLabel")

                    Button {
                        withAnimation(.easeOut(duration: 0.1)) {
                            isButtonPressed = true
                        }
                        tapCount += 1
                        lastAction = "Button tapped"
                        NSLog("[ContentView] 🔘 Test Button TAPPED! Count: %d", tapCount)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeIn(duration: 0.2)) {
                                isButtonPressed = false
                            }
                        }
                    } label: {
                        Text("Test Button")
                    }
                    .font(.headline)
                    .foregroundStyle(isButtonPressed ? .green : .blue)
                    .scaleEffect(isButtonPressed ? 1.1 : 1.0)
                    .accessibilityIdentifier("buttonheist.action.testButton")

                    Slider(value: $sliderValue, in: 0...100, step: 10) {
                        Text("Volume")
                    }
                    .accessibilityIdentifier("buttonheist.action.volumeSlider")
                    .accessibilityValue("\(Int(sliderValue))")
                    .onChange(of: sliderValue) { _, newValue in
                        lastAction = "Slider changed to \(Int(newValue))"
                        NSLog("[ContentView] 🎚️ Slider CHANGED to: %d", Int(newValue))
                    }

                    Stepper("Quantity: \(stepperValue)", value: $stepperValue, in: 0...10)
                        .accessibilityIdentifier("buttonheist.action.quantityStepper")
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
                    .accessibilityIdentifier("buttonheist.buttons.submitButton")

                    Button("Cancel", role: .destructive) {
                        lastAction = "Cancel tapped"
                    }
                    .accessibilityIdentifier("buttonheist.buttons.cancelButton")
                }

                Section("Accessibility Notifications") {
                    Button("Post Layout Changed") {
                        UIAccessibility.post(notification: .layoutChanged, argument: nil)
                        lastAction = "Posted layoutChanged"
                        NSLog("[ContentView] 📢 Posted layoutChanged notification")
                    }
                    .accessibilityIdentifier("buttonheist.notifications.layoutChanged")

                    Button("Post Screen Changed") {
                        UIAccessibility.post(notification: .screenChanged, argument: nil)
                        lastAction = "Posted screenChanged"
                        NSLog("[ContentView] 📢 Posted screenChanged notification")
                    }
                    .accessibilityIdentifier("buttonheist.notifications.screenChanged")

                    Button("Post Announcement") {
                        UIAccessibility.post(notification: .announcement, argument: "Hello from ButtonHeist!")
                        lastAction = "Posted announcement"
                        NSLog("[ContentView] 📢 Posted announcement notification")
                    }
                    .accessibilityIdentifier("buttonheist.notifications.announcement")

                    Button("Post Page Scrolled") {
                        UIAccessibility.post(notification: .pageScrolled, argument: "Page 1 of 3")
                        lastAction = "Posted pageScrolled"
                        NSLog("[ContentView] 📢 Posted pageScrolled notification")
                    }
                    .accessibilityIdentifier("buttonheist.notifications.pageScrolled")
                }

                Section("Information") {
                    Label("This is a demo app for testing accessibility inspection.", systemImage: "info.circle")
                        .accessibilityIdentifier("buttonheist.info.infoLabel")

                    Link("Learn more about accessibility", destination: URL(string: "https://developer.apple.com/accessibility/")!)
                        .accessibilityIdentifier("buttonheist.info.learnMoreLink")
                }
            }
        .navigationTitle("Accessibility Demo")
    }
}

#Preview {
    ContentView()
}

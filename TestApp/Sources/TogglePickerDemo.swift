import SwiftUI

struct TogglePickerDemo: View {
    @State private var isSubscribed = false
    @State private var selectedFrequency = 0
    @State private var selectedPriority = 0
    @State private var selectedDate = Date()
    @State private var pickedColor = Color.blue
    @State private var lastAction = "None"

    var body: some View {
        Form {
            Section("Toggles & Pickers") {
                Toggle("Subscribe to newsletter", isOn: $isSubscribed)
                    .onChange(of: isSubscribed) { _, newValue in
                        lastAction = "Toggle: \(newValue ? "ON" : "OFF")"
                    }

                Picker("Frequency", selection: $selectedFrequency) {
                    Text("Daily").tag(0)
                    Text("Weekly").tag(1)
                    Text("Monthly").tag(2)
                }

                Picker("Priority", selection: $selectedPriority) {
                    Text("Low").tag(0)
                    Text("Medium").tag(1)
                    Text("High").tag(2)
                }
                .pickerStyle(.segmented)

                DatePicker("Date", selection: $selectedDate, displayedComponents: [.date])
                    .onChange(of: selectedDate) { _, _ in
                        lastAction = "Date changed"
                    }

                ColorPicker("Accent color", selection: $pickedColor)
            }

            Section {
                Text("Last action: \(lastAction)")
            }
        }
        .navigationTitle("Toggles & Pickers")
    }
}

#Preview {
    TogglePickerDemo()
}

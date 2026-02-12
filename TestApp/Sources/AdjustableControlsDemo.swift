import SwiftUI

struct AdjustableControlsDemo: View {
    @State private var sliderValue = 50.0
    @State private var stepperValue = 0
    @State private var progressValue = 0.4
    @State private var lastAction = "None"

    var body: some View {
        Form {
            Section("Adjustable Controls") {
                Slider(value: $sliderValue, in: 0...100, step: 10) {
                    Text("Volume")
                }
                .accessibilityIdentifier("buttonheist.adjustable.slider")
                .accessibilityValue("\(Int(sliderValue))")
                .onChange(of: sliderValue) { _, newValue in
                    lastAction = "Slider: \(Int(newValue))"
                    NSLog("[ControlsDemo] Slider changed to: %d", Int(newValue))
                }

                Stepper("Quantity: \(stepperValue)", value: $stepperValue, in: 0...10)
                    .accessibilityIdentifier("buttonheist.adjustable.stepper")
                    .onChange(of: stepperValue) { _, newValue in
                        lastAction = "Stepper: \(newValue)"
                        NSLog("[ControlsDemo] Stepper changed to: %d", newValue)
                    }

                Gauge(value: sliderValue, in: 0...100) {
                    Text("Level")
                } currentValueLabel: {
                    Text("\(Int(sliderValue))")
                }
                .gaugeStyle(.accessoryLinear)
                .accessibilityIdentifier("buttonheist.adjustable.gauge")

                ProgressView("Uploading…", value: progressValue)
                    .accessibilityIdentifier("buttonheist.adjustable.linearProgress")

                ProgressView("Loading…")
                    .accessibilityIdentifier("buttonheist.adjustable.spinnerProgress")
            }

            Section {
                Text("Last action: \(lastAction)")
                    .accessibilityIdentifier("buttonheist.adjustable.lastActionLabel")
            }
        }
        .navigationTitle("Adjustable Controls")
    }
}

#Preview {
    AdjustableControlsDemo()
}

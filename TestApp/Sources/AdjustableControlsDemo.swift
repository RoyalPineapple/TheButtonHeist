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
                .accessibilityValue("\(Int(sliderValue))")
                .onChange(of: sliderValue) { _, newValue in
                    lastAction = "Slider: \(Int(newValue))"
                }

                Stepper("Quantity: \(stepperValue)", value: $stepperValue, in: 0...10)
                    .onChange(of: stepperValue) { _, newValue in
                        lastAction = "Stepper: \(newValue)"
                    }

                Gauge(value: sliderValue, in: 0...100) {
                    Text("Level")
                } currentValueLabel: {
                    Text("\(Int(sliderValue))")
                }
                .gaugeStyle(.accessoryLinear)

                ProgressView("Uploading…", value: progressValue)

                ProgressView("Loading…")
            }

            Section {
                Text("Last action: \(lastAction)")
            }
        }
        .navigationTitle("Adjustable Controls")
    }
}

#Preview {
    AdjustableControlsDemo()
}

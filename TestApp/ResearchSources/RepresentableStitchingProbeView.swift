import SwiftUI
import UIKit

// MARK: - Representables

private struct UILabelOnlyRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.text = "UIKitLabel visual"
        label.isAccessibilityElement = true
        label.accessibilityLabel = "UIKitLabel"
        label.accessibilityIdentifier = "buttonheist.representable.uikitLabelOnly.inner"
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {}
}

private struct OverlappingLabelRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.text = "Overlapping visual"
        label.isAccessibilityElement = true
        label.accessibilityLabel = "UIKitLabel"
        label.accessibilityIdentifier = "buttonheist.representable.overlappingLabel.inner"
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {}
}

private struct UISwitchWrapRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UISwitch {
        let toggle = UISwitch()
        toggle.isOn = false
        toggle.accessibilityIdentifier = "buttonheist.representable.uiswitchWrap.inner"
        return toggle
    }

    func updateUIView(_ uiView: UISwitch, context: Context) {}
}

// MARK: - Probe View

struct RepresentableStitchingProbeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Fixture 1: UIKit-only label
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fixture 1: uikitLabelOnly")
                    UILabelOnlyRepresentable()
                        .frame(height: 44)
                        .accessibilityIdentifier("buttonheist.representable.uikitLabelOnly")
                }

                // Fixture 2: overlapping label (UIKit + SwiftUI modifier)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fixture 2: overlappingLabel")
                    OverlappingLabelRepresentable()
                        .frame(height: 44)
                        .accessibilityLabel("SwiftUILabel")
                        .accessibilityIdentifier("buttonheist.representable.overlappingLabel")
                }

                // Fixture 3: UISwitch + SwiftUI addTraits(.isHeader)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fixture 3: uiswitchWrap")
                    UISwitchWrapRepresentable()
                        .frame(width: 60, height: 44)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("buttonheist.representable.uiswitchWrap")
                }
            }
            .padding()
        }
        .accessibilityIdentifier("buttonheist.representable.probeRoot")
    }
}

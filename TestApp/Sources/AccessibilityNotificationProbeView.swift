import SwiftUI

struct AccessibilityNotificationProbeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hand-Rolled UIKit Values")
                    .font(.headline)

                Text("Tap each bare NSObject to mutate its accessibilityValue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                UIKitAccessibilityValueProbe()
                    .frame(height: 390)
            }
            .padding()
        }
        .navigationTitle("UIKit Value Probe")
    }
}

#Preview {
    NavigationStack {
        AccessibilityNotificationProbeView()
    }
}

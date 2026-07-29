import SwiftUI

struct AccessibilityNotificationProbeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hand-Rolled UIKit Values")
                    .font(.headline)

                Text("Tap the counter, or use the button to update the separate remote object.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                UIKitAccessibilityValueProbe()
                    .frame(height: 230)
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

import SwiftUI
import UIKit

struct EvidenceContinuityDemo: View {
    @State private var activity = "Ready"
    @State private var isToastVisible = false
    @State private var pendingEvidence: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            Text(activity)
                .font(.headline)

            if isToastVisible {
                Text("Transfer complete")
                    .font(.body)
                    .padding()
                    .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            }

            Button("Emit transient evidence") {
                emitTransientEvidence()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .navigationTitle("Evidence Continuity")
        .onDisappear {
            pendingEvidence?.cancel()
            pendingEvidence = nil
        }
    }

    private func emitTransientEvidence() {
        pendingEvidence?.cancel()
        activity = "Evidence activity 0"
        isToastVisible = true
        UIAccessibility.post(
            notification: .announcement,
            argument: "Transfer confirmed"
        )
        pendingEvidence = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                for tick in 1...12 {
                    try await Task.sleep(for: .milliseconds(50))
                    activity = "Evidence activity \(tick)"
                    if tick == 4 {
                        isToastVisible = false
                    }
                }
                activity = "Evidence settled"
            } catch {
                return
            }
        }
    }
}

#Preview {
    NavigationStack {
        EvidenceContinuityDemo()
    }
}

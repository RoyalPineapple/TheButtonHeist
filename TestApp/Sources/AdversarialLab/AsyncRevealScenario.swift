import SwiftUI
import UIKit

internal struct AsyncRevealScenarioView: View {
    private enum Phase: Equatable {
        case idle
        case pending
        case revealed
    }

    @State private var phase: Phase = .idle
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Button("Reveal with notification") { reveal(postNotification: true) }
                Button("Reveal silently") { reveal(postNotification: false) }
            }

            Section("Destination") {
                switch phase {
                case .idle:
                    Text("Destination hidden")
                case .pending:
                    Text("Waiting for destination")
                case .revealed:
                    Text("Delayed code: 7429")
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .navigationTitle("Async Reveal")
        .onAppear(perform: reset)
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
    }

    private func reset() {
        revealTask?.cancel()
        revealTask = nil
        phase = .idle
    }

    private func reveal(postNotification: Bool) {
        revealTask?.cancel()
        phase = .pending
        revealTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return
            }
            phase = .revealed
            if postNotification {
                UIAccessibility.post(notification: .screenChanged, argument: "Delayed code: 7429")
            }
        }
    }
}

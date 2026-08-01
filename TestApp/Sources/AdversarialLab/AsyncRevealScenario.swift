import SwiftUI
import UIKit

internal struct AsyncRevealScenarioView: View {
    private enum Phase: Equatable {
        case idle
        case pending
        case revealed
        case settled
    }

    @State private var phase: Phase = .idle
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Button("Reveal with notification") { reveal(.notificationBurst) }
                Button("Reveal silently") { reveal(.silent) }
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
                case .settled:
                    Text("Delayed code: 7429")
                        .accessibilityAddTraits(.isHeader)
                    Text("Silent terminal state")
                        .accessibilityValue("Generation 2")
                    Text("Burst notification order: layout, announcement, screen")
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

    private enum RevealMode: Equatable {
        case notificationBurst
        case silent
    }

    private func reveal(_ mode: RevealMode) {
        revealTask?.cancel()
        phase = .pending
        revealTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return
            }
            phase = .revealed
            if mode == .notificationBurst {
                UIAccessibility.post(notification: .layoutChanged, argument: "Async reveal layout updated")
                UIAccessibility.post(notification: .announcement, argument: "Delayed code: 7429")
                UIAccessibility.post(notification: .screenChanged, argument: "Async reveal screen updated")
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
                phase = .settled
            }
        }
    }
}

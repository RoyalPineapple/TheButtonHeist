import SwiftUI

struct ProgressButtonDemo: View {
    @State private var percent: Int?
    @State private var completedRuns = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            if let percent {
                Text("Loading")
                    .accessibilityElement()
                    .accessibilityLabel("Loading")
                    .accessibilityValue("\(percent)%")
            } else {
                Button("Ready") { start() }
            }

            Text("Completed runs: \(completedRuns)")
                .accessibilityElement()
                .accessibilityLabel("Completed runs")
                .accessibilityValue("\(completedRuns)")
        }
        .padding()
        .navigationTitle("Progress Button")
        .onDisappear { task?.cancel() }
    }

    private func start() {
        guard task == nil else { return }
        task = Task {
            do {
                for step in stride(from: 0, through: 100, by: 25) {
                    percent = step
                    try await Task.sleep(for: .milliseconds(120))
                }
            } catch {
                percent = nil
                task = nil
                return
            }
            percent = nil
            completedRuns += 1
            task = nil
        }
    }
}

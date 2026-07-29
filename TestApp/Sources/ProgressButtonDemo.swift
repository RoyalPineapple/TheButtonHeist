import SwiftUI

/// A button that dies and is reborn as it works.
///
/// Element identity is content-derived — the first non-empty of identifier,
/// label, description — so this button deliberately carries **no identifier**.
/// Its label is its identity, and changing the label is therefore not an update
/// but a disappearance and an appearance.
///
/// One tap walks Ready → Loading → Ready, which is the smallest interaction
/// that produces every element fact in one ordered run:
///
///   disappeared "Ready"          identity dies
///   appeared    "Loading"        new identity
///   updated     "Loading"        same identity, value climbs 0% → 100%
///   disappeared "Loading"        identity dies again
///   appeared    "Ready"          the label that was true at the start, again
///
/// The last line is the point. "Ready" was present before the tap, so a model
/// that asks "was this ever true" gets it wrong. Only an ordered drain can say
/// that this Ready is a *different* arrival from the one at the beginning.
struct ProgressButtonDemo: View {
    @State private var percent: Int?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            if let percent {
                // Label is stable while the value climbs, so the middle of the
                // run is a genuine `updated` on one identity rather than a
                // string of births and deaths.
                Text("Loading")
                    .accessibilityElement()
                    .accessibilityLabel("Loading")
                    .accessibilityValue("\(percent)%")
            } else {
                Button("Ready") { start() }
            }
        }
        .padding()
        .navigationTitle("Progress Button")
        .onDisappear { task?.cancel() }
    }

    private func start() {
        guard task == nil else { return }
        task = Task {
            for step in stride(from: 0, through: 100, by: 25) {
                percent = step
                try? await Task.sleep(for: .milliseconds(120))
            }
            percent = nil
            task = nil
        }
    }
}

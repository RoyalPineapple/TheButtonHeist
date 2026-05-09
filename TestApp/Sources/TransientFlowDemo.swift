import SwiftUI

/// Multi-step transition flow used to verify auto-settle and transient
/// capture end-to-end:
///   tap Submit → loading spinner → success indicator → confirmation
///   panel with two option buttons → auto-dismiss back to the original
///   screen ~3.5s later.
///
/// A caller using auto-settle should see one response with `settled: true`
/// and an `interfaceDelta` whose `transient` array carries the loading,
/// success, and confirmation elements — even though the visible state at
/// response time is identical to the pre-action state.
struct TransientFlowDemo: View {

    enum Phase: Equatable {
        case idle
        case loading
        case success
        case confirmation
        var label: String {
            switch self {
            case .idle: return "Idle"
            case .loading: return "Processing"
            case .success: return "Complete"
            case .confirmation: return "Transaction complete"
            }
        }
    }

    @State private var phase: Phase = .idle
    @State private var lastOutcome: String = "No flow run yet"
    @State private var pendingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            statusCard

            Group {
                switch phase {
                case .idle:
                    submitButton
                case .loading:
                    loadingView
                case .success:
                    successView
                case .confirmation:
                    confirmationView
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .padding()
        .navigationTitle("Transient Flow")
        .onDisappear {
            pendingTask?.cancel()
            pendingTask = nil
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last outcome")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(lastOutcome)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Phase Views

    private var submitButton: some View {
        Button("Submit") {
            runFlow()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(Phase.loading.label)
                .font(.headline)
        }
    }

    private var successView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(Phase.success.label)
                .font(.headline)
        }
    }

    private var confirmationView: some View {
        VStack(spacing: 16) {
            Text(Phase.confirmation.label)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 12) {
                Button("Email receipt") { /* no-op for fixture */ }
                    .buttonStyle(.bordered)
                Button("No thanks") { /* no-op for fixture */ }
                    .buttonStyle(.bordered)
            }

            Button("Done") { /* no-op — flow auto-dismisses */ }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Flow

    /// Run loading → success → confirmation → auto-dismiss with
    /// approximately the timing of a real network-backed payment flow.
    private func runFlow() {
        pendingTask?.cancel()
        pendingTask = Task {
            do {
                phase = .loading
                try await Task.sleep(for: .milliseconds(900))
                phase = .success
                try await Task.sleep(for: .milliseconds(700))
                phase = .confirmation
                try await Task.sleep(for: .milliseconds(1500))
            } catch {
                return
            }
            phase = .idle
            lastOutcome = "Flow completed at \(Date().formatted(date: .omitted, time: .standard))"
        }
    }
}

#Preview {
    NavigationStack {
        TransientFlowDemo()
    }
}

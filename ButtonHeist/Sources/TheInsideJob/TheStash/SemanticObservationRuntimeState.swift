#if canImport(UIKit)
#if DEBUG

import TheScore

/// Owns the stream lifecycle and the position of its next publication.
internal struct SemanticObservationRuntimeState {
    // MARK: - Nested Types

    internal typealias DiscoveryObservation = @MainActor () async -> Navigation.ExploredScreen?

    internal struct RunningObservation {
        let task: Task<Void, Never>
        var discovery: DiscoveryObservation
        var settledReading: TheTripwire.PulseReading?
    }

    internal enum Lifecycle {
        case stopped
        case running(RunningObservation)
    }

    internal enum Lineage: Equatable {
        case continuous(ObservationGeneration)
        case replacementRequired(ObservationGeneration)

        internal var generation: ObservationGeneration {
            switch self {
            case .continuous(let value), .replacementRequired(let value): value
            }
        }

        internal func admitting(_ classification: ScreenClassifier.Classification) -> ScreenClassifier.Classification {
            switch self {
            case .continuous: classification
            case .replacementRequired: .screenChangedNotification
            }
        }
    }

    // MARK: - Properties

    internal private(set) var lifecycle: Lifecycle = .stopped
    internal private(set) var sequence: SettledObservationSequence = 0
    internal private(set) var lineage: Lineage = .continuous(.initial)
    internal private(set) var notificationCursor = AccessibilityNotificationCursor.origin
    internal private(set) var scopedScreenChangedSequence: UInt64 = 0
    internal private(set) var settleFailureDiagnostic: String?

    internal var isRunning: Bool {
        if case .running = lifecycle { true } else { false }
    }

    internal var discovery: DiscoveryObservation? {
        if case .running(let observation) = lifecycle { observation.discovery } else { nil }
    }

    internal var settledReading: TheTripwire.PulseReading? {
        if case .running(let observation) = lifecycle { observation.settledReading } else { nil }
    }

    // MARK: - Lifecycle

    internal mutating func start(task: Task<Void, Never>, discovery: @escaping DiscoveryObservation) {
        precondition(!isRunning, "semantic observation is already running")
        lifecycle = .running(RunningObservation(task: task, discovery: discovery, settledReading: nil))
    }

    internal mutating func replaceDiscoveryIfRunning(_ discovery: @escaping DiscoveryObservation) -> Bool {
        guard case .running(var observation) = lifecycle else { return false }
        observation.discovery = discovery
        lifecycle = .running(observation)
        return true
    }

    internal mutating func stop() -> Task<Void, Never>? {
        guard case .running(let observation) = lifecycle else { return nil }
        lifecycle = .stopped
        return observation.task
    }

    // MARK: - Settlement

    internal mutating func requireReplacement() {
        lineage = .replacementRequired(lineage.generation)
        updateSettledReading(nil)
        settleFailureDiagnostic = nil
    }

    internal mutating func commit(
        _ publication: SemanticObservationPublication,
        notificationBatch: AccessibilityNotificationBatch,
        settledReading: TheTripwire.PulseReading?
    ) {
        precondition(publication.sourceEvent.sequence == sequence + 1)
        sequence = publication.sourceEvent.sequence
        lineage = .continuous(publication.generation)
        notificationCursor = notificationBatch.through
        scopedScreenChangedSequence = notificationBatch.scopedScreenChangedThrough
        settleFailureDiagnostic = nil
        updateSettledReading(settledReading)
    }

    internal mutating func recordSettleFailure(_ diagnostic: String?) {
        settleFailureDiagnostic = diagnostic
    }

    private mutating func updateSettledReading(_ reading: TheTripwire.PulseReading?) {
        guard case .running(var observation) = lifecycle else { return }
        observation.settledReading = reading
        lifecycle = .running(observation)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

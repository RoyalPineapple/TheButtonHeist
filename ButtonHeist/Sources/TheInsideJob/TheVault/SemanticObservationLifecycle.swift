#if canImport(UIKit)
#if DEBUG

/// Owns only the stream task lifecycle.
internal enum SemanticObservationLifecycle {
    // MARK: - Nested Types

    internal typealias DiscoveryObservation = @MainActor () async -> Navigation.InterfaceExplorationResult?

    internal struct RunningObservation {
        let task: Task<Void, Never>
        var discovery: DiscoveryObservation
    }

    case stopped
    case running(RunningObservation)

    internal var isRunning: Bool {
        if case .running = self { true } else { false }
    }

    internal var discovery: DiscoveryObservation? {
        if case .running(let observation) = self { observation.discovery } else { nil }
    }

    // MARK: - Lifecycle

    internal mutating func start(task: Task<Void, Never>, discovery: @escaping DiscoveryObservation) {
        precondition(!isRunning, "semantic observation is already running")
        self = .running(RunningObservation(task: task, discovery: discovery))
    }

    internal mutating func replaceDiscoveryIfRunning(_ discovery: @escaping DiscoveryObservation) -> Bool {
        guard case .running(var observation) = self else { return false }
        observation.discovery = discovery
        self = .running(observation)
        return true
    }

    internal mutating func stop() -> Task<Void, Never>? {
        guard case .running(let observation) = self else { return nil }
        self = .stopped
        return observation.task
    }

}

#endif // DEBUG
#endif // canImport(UIKit)

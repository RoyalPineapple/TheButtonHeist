#if canImport(UIKit)
#if DEBUG

/// Owns only the stream task lifecycle.
internal enum SemanticObservationLifecycle {
    // MARK: - Nested Types

    internal typealias DiscoveryObservation = @MainActor () async -> Navigation.InterfaceExplorationResult?

    case stopped
    case running(task: Task<Void, Never>, discovery: DiscoveryObservation)

    internal var isRunning: Bool {
        if case .running = self { true } else { false }
    }

    internal var discovery: DiscoveryObservation? {
        if case .running(_, let discovery) = self { discovery } else { nil }
    }

    // MARK: - Lifecycle

    internal mutating func start(task: Task<Void, Never>, discovery: @escaping DiscoveryObservation) {
        precondition(!isRunning, "semantic observation is already running")
        self = .running(task: task, discovery: discovery)
    }

    internal mutating func replaceDiscoveryIfRunning(_ discovery: @escaping DiscoveryObservation) -> Bool {
        guard case .running(let task, _) = self else { return false }
        self = .running(task: task, discovery: discovery)
        return true
    }

    internal mutating func stop() -> Task<Void, Never>? {
        guard case .running(let task, _) = self else { return nil }
        self = .stopped
        return task
    }

}

#endif // DEBUG
#endif // canImport(UIKit)

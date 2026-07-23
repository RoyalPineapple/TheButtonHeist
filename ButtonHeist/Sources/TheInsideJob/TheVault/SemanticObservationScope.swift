#if canImport(UIKit)
#if DEBUG
import Foundation

enum SemanticObservationScope: Int, Comparable, Sendable {
    case visible
    case discovery

    static func < (lhs: SemanticObservationScope, rhs: SemanticObservationScope) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func canFulfill(_ requested: SemanticObservationScope) -> Bool {
        switch (self, requested) {
        case (.visible, .visible),
             (.discovery, .visible),
             (.discovery, .discovery):
            return true
        case (.visible, .discovery):
            return false
        }
    }

    var fulfilledScopes: [SemanticObservationScope] {
        switch self {
        case .visible:
            return [.visible]
        case .discovery:
            return [.discovery, .visible]
        }
    }
}

@MainActor
final class SemanticObservationSubscription {
    let id: UInt64
    let scope: SemanticObservationScope
    private weak var stream: Observation.Stream?
    private var isCancelled = false

    init(id: UInt64, scope: SemanticObservationScope, stream: Observation.Stream) {
        self.id = id
        self.scope = scope
        self.stream = stream
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        stream?.removeSubscription(id)
        stream = nil
    }

    deinit {
        MainActor.assumeIsolated {
            guard !isCancelled else { return }
            stream?.removeSubscription(id)
        }
    }
}

@MainActor
final class SemanticObservationDemand {
    let id: UInt64
    private weak var stream: Observation.Stream?
    private var isCancelled = false

    init(id: UInt64, stream: Observation.Stream) {
        self.id = id
        self.stream = stream
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        stream?.removeActiveObservationDemand(id)
        stream = nil
    }

    deinit {
        MainActor.assumeIsolated {
            guard !isCancelled else { return }
            stream?.removeActiveObservationDemand(id)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

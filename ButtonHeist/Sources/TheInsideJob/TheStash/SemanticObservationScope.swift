#if canImport(UIKit)
#if DEBUG
import Foundation

enum SemanticObservationScope: Int, Comparable, Sendable {
    case visible
    case discovery

    static func < (lhs: SemanticObservationScope, rhs: SemanticObservationScope) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@MainActor
final class SemanticObservationSubscription {
    let id: UInt64
    let scope: SemanticObservationScope
    private weak var stream: SemanticObservationStream?

    init(id: UInt64, scope: SemanticObservationScope, stream: SemanticObservationStream) {
        self.id = id
        self.scope = scope
        self.stream = stream
    }

    deinit {
        MainActor.assumeIsolated {
            stream?.removeSubscription(id)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

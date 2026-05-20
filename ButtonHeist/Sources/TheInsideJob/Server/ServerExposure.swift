import Foundation

import TheScore

/// Typed exposure policy for the server listener and discovery surface.
///
/// `ConnectionScope` decides who may connect. `ServerExposure` decides which
/// surfaces are allowed to become visible before a connection reaches scope
/// classification.
struct ServerExposure: Equatable, Sendable {
    let allowedScopes: Set<ConnectionScope>

    var publishesBonjour: Bool {
        allowedScopes.contains(.network)
    }

    var bindsToLoopbackOnly: Bool {
        allowedScopes == [.simulator]
    }

    var bonjourDisabledReason: String? {
        publishesBonjour ? nil : "network-scope-not-enabled"
    }
}

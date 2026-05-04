import Foundation

// MARK: - SettleConfig

/// Two knobs that control how long the server waits for the accessibility
/// tree to stabilise after an action.
///
/// **Inter-screen stability** (this struct's domain) is gated on
/// accessibility-tree stability *only*. CALayer animations on a stable
/// screen — analog clock hands, animated gradients, Lottie loops — do not
/// block settle. Button Heist is an accessibility tool and the AX tree is
/// the source of truth for what the user perceives.
///
/// **Screen transitions** (push, modal present, view-controller swap) are
/// still detected via `TheTripwire`'s layer-animation pulse, separately
/// from this loop. When a screen transition is in flight, the existing
/// repopulation handler in `TheBrains` waits for animations to quiet and
/// the new VC's tree to populate before SettleSession's AX-tree loop is
/// trusted.
///
/// Spinner exclusion is fixed behaviour, not a knob: any element whose value
/// oscillates within the snapshot timeline, or which carries the
/// `UIAccessibilityTraits.updatesFrequently` trait, is allowed to keep
/// changing without blocking settle. Respecting `updatesFrequently` is the
/// iOS accessibility contract for "I update constantly, ignore me" — agents
/// do not get to override accessibility semantics.
///
/// Provided two ways:
///  - On the `ConnectRequest` handshake to set per-session defaults.
///  - On the `RequestEnvelope` of an individual action as `settleOverride`,
///    which wins for that action only.
public struct SettleConfig: Codable, Sendable, Equatable {

    /// Number of consecutive stable AX-tree cycles required before the
    /// server considers the UI settled. Higher values trade latency for
    /// confidence that no further changes are coming.
    public var cycles: Int

    /// Hard upper bound on settle wait time, in milliseconds. If hit, the
    /// server returns whatever state it has with `settled: false` rather
    /// than hanging.
    public var timeoutMs: Int

    public init(cycles: Int = 3, timeoutMs: Int = 10_000) {
        self.cycles = cycles
        self.timeoutMs = timeoutMs
    }

    /// Server-side built-in defaults. Used when neither connect-time config
    /// nor per-action override has been provided.
    public static let builtInDefaults = SettleConfig()

    /// `effectiveConfig = perAction ?? session ?? builtInDefaults`.
    public static func resolve(
        perAction: SettleConfig?,
        session: SettleConfig?
    ) -> SettleConfig {
        perAction ?? session ?? .builtInDefaults
    }
}

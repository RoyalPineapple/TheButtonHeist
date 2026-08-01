#if canImport(UIKit)
#if DEBUG
import UIKit

extension TheTripwire {
    /// Snapshot of the display-link facts consumed by one observation cycle.
    ///
    /// `elapsed` is monotonic time since the pulse began. It is sampled by the
    /// display-link adapter in production and authored directly by deterministic
    /// callers, so no delivery recipient needs to read a clock.
    struct PulseReading: Sendable, Equatable {
        let tick: UInt64
        let elapsed: Duration
        let tripwireSignal: TripwireSignal
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import UIKit

extension TheTripwire {
    /// Snapshot of all monitored UI signals at a single tick.
    struct PulseReading {
        let tick: UInt64
        let timestamp: CFAbsoluteTime

        let topmostVC: ObjectIdentifier?
        let tripwireSignal: TripwireSignal
        let windowCount: Int
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

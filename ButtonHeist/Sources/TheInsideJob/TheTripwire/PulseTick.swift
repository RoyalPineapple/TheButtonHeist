#if canImport(UIKit)
#if DEBUG
import UIKit

/// Weak-referencing target for the persistent CADisplayLink.
/// Auto-invalidates the link if TheTripwire is deallocated.
@MainActor
final class PulseTick: NSObject {
    weak var tripwire: TheTripwire?

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
    }

    @objc func handleTick(_ link: CADisplayLink) {
        guard let tripwire else {
            link.invalidate()
            return
        }
        tripwire.onTick()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

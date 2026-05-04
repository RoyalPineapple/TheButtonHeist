#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

@MainActor
extension InterfaceDelta {

    /// Return a copy of this delta with `transient` and `flicker` arrays
    /// populated from a `TimelineClassification`. Returns `self` unchanged
    /// when the classification has no transients or flickers — avoids
    /// allocating a new struct in the common case.
    ///
    /// Categories are mutually exclusive with `added`/`removed`/`updated`:
    /// transient elements were never in baseline or final (so they cannot
    /// also appear in added/removed), and flicker elements were in both
    /// (so they cannot also appear in added/removed). Property-level
    /// updates between baseline and final remain in `updated`.
    func enriching(with classification: TimelineClassification) -> InterfaceDelta {
        guard classification.hasAnyTransientOrFlicker else { return self }

        let transientWire = classification.transientElements.map { TheStash.WireConversion.toWireWithoutHeistId($0) }
        let flickerWire = classification.flickerElements.map { TheStash.WireConversion.toWireWithoutHeistId($0) }

        return InterfaceDelta(
            kind: kind,
            elementCount: elementCount,
            added: added,
            removed: removed,
            updated: updated,
            treeInserted: treeInserted,
            treeRemoved: treeRemoved,
            treeMoved: treeMoved,
            transient: transientWire.isEmpty ? nil : transientWire,
            flicker: flickerWire.isEmpty ? nil : flickerWire,
            newInterface: newInterface
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

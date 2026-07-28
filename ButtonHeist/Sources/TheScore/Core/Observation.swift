import ThePlans

/// Canonical values produced while observing an accessibility interface.
package enum Observation {}

package extension Observation {
    /// One semantic fact admitted by the vault.
    enum Fact: Sendable, Equatable {
        case elementsChanged(AccessibilityTrace.Capture)
        case screenChanged(ScreenFacts)
        case announcement(CapturedAnnouncement)
        case noChange

        /// The tree read by this fact, when it carries one.
        var interface: Interface? {
            guard case .elementsChanged(let capture) = self else { return nil }
            return capture.interface
        }
    }
}

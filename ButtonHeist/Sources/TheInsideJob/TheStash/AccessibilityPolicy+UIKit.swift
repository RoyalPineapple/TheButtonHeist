#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - AccessibilityPolicy UIKit Derivations

/// UIKit-bitmask projections of `AccessibilityPolicy` policy sets.
///
/// Each `*Bitmask` value is derived from the corresponding `Set<HeistTrait>`
/// via `UIAccessibilityTraits.fromNames` so the two forms cannot drift.
/// Consumers that work with `UIAccessibilityTraits` (Interactivity,
/// IdAssignment, TheBurglar) read these directly instead of building
/// their own.
extension AccessibilityPolicy {

    /// Bitmask form of `transientTraits`. Consumed by
    /// `TheBurglar.stableTraitNames`.
    static let transientTraitsBitmask: UIAccessibilityTraits =
        UIAccessibilityTraits.fromNames(transientTraits.map(\.rawValue))

    /// Set of trait *names* in `transientTraits`. Consumed by
    /// `TheBurglar.stableTraitNames` for `Set<String>` subtraction.
    static let transientTraitNames: Set<String> =
        Set(transientTraits.map(\.rawValue))

    /// Bitmask form of `interactiveTraits`. Consumed by
    /// `TheStash.Interactivity.hasInteractiveTraits`.
    static let interactiveTraitsBitmask: UIAccessibilityTraits =
        UIAccessibilityTraits.fromNames(interactiveTraits.map(\.rawValue))

    /// Bitmask form of `staticOnlyTraits`. Consumed by
    /// `TheStash.Interactivity.checkInteractivity` for subset checks.
    static let staticOnlyTraitsBitmask: UIAccessibilityTraits =
        UIAccessibilityTraits.fromNames(staticOnlyTraits.map(\.rawValue))

    /// Synthesis priority resolved to `(name, bitmask)` pairs in priority
    /// order. Consumed by `TheStash.IdAssignment.synthesizeBaseId` to find
    /// the first matching trait an element carries.
    static let synthesisPriorityWithMasks: [(name: String, mask: UIAccessibilityTraits)] =
        synthesisPriority.map { trait in
            (name: trait.rawValue, mask: UIAccessibilityTraits.fromNames([trait.rawValue]))
        }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheScore

/// Shared `AccessibilityElement` factory for tests.
///
/// Subsumes the per-file `makeElement` / `element` / `dummyElement` helpers
/// that used to live in every test file. Defaults match the most common
/// fixture shape — empty description, no traits, zero frame, default
/// activation point, `respondsToUserInteraction: true` — and individual
/// parameters can be overridden as needed.
///
/// Use `.make(label:traits:...)` for the common case and
/// `.make(label:heistTraits:...)` when traits should be expressed as
/// `[HeistTrait]` (mapped through `UIAccessibilityTraits.fromNames`).
extension AccessibilityElement {

    static func make(
        description: String? = nil,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: UIAccessibilityTraits = .none,
        shape: Shape = .frame(.zero),
        activationPoint: CGPoint = .zero,
        usesDefaultActivationPoint: Bool = true,
        customActions: [CustomAction] = [],
        customContent: [CustomContent] = [],
        respondsToUserInteraction: Bool = true
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: description ?? label ?? "",
            label: label,
            value: value,
            traits: traits,
            identifier: identifier,
            hint: hint,
            userInputLabels: nil,
            shape: shape,
            activationPoint: activationPoint,
            usesDefaultActivationPoint: usesDefaultActivationPoint,
            customActions: customActions,
            customContent: customContent,
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: respondsToUserInteraction
        )
    }

    /// Convenience that takes `[HeistTrait]` and maps via
    /// `UIAccessibilityTraits.fromNames`. Useful in trait-policy and
    /// id-assignment tests that drive traits from the wire enum.
    static func make(
        description: String? = nil,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        heistTraits: [HeistTrait],
        shape: Shape = .frame(.zero),
        activationPoint: CGPoint = .zero,
        usesDefaultActivationPoint: Bool = true,
        customActions: [CustomAction] = [],
        customContent: [CustomContent] = [],
        respondsToUserInteraction: Bool = true
    ) -> AccessibilityElement {
        make(
            description: description,
            label: label,
            value: value,
            identifier: identifier,
            traits: UIAccessibilityTraits.fromNames(heistTraits.map(\.rawValue)),
            shape: shape,
            activationPoint: activationPoint,
            usesDefaultActivationPoint: usesDefaultActivationPoint,
            customActions: customActions,
            customContent: customContent,
            respondsToUserInteraction: respondsToUserInteraction
        )
    }

    /// Convenience for the common pattern of building an element with a
    /// frame and an activation point at the frame's center.
    static func make(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none,
        frame: CGRect,
        respondsToUserInteraction: Bool = true
    ) -> AccessibilityElement {
        make(
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            shape: .frame(frame),
            activationPoint: CGPoint(x: frame.midX, y: frame.midY),
            respondsToUserInteraction: respondsToUserInteraction
        )
    }
}

#endif

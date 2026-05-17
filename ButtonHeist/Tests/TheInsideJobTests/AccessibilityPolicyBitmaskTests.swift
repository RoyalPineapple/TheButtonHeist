#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Tests for the parser-bitmask derivations of `AccessibilityPolicy`.
///
/// The `*Bitmask` and `*Names` values are computed from `Set<HeistTrait>`
/// policy at static-let initialization time. If the conversion ever drops
/// a trait (e.g. an unknown name silently swallowed by
/// `AccessibilityTraits.fromNames`), the consumer's behavior becomes
/// inconsistent with policy. These tests catch that.
final class AccessibilityPolicyBitmaskTests: XCTestCase {

    // MARK: - Bitmask round-trip

    func testTransientTraitsBitmaskRoundTrips() {
        let bitmask = AccessibilityPolicy.transientTraitsBitmask
        let recoveredNames = Set(bitmask.traitNames)
        let expectedNames = Set(AccessibilityPolicy.transientTraits.map(\.rawValue))
        XCTAssertEqual(recoveredNames, expectedNames,
                       "transientTraitsBitmask must round-trip the trait names")
    }

    func testInteractiveTraitsBitmaskRoundTrips() {
        let bitmask = AccessibilityPolicy.interactiveTraitsBitmask
        let recoveredNames = Set(bitmask.traitNames)
        let expectedNames = Set(AccessibilityPolicy.interactiveTraits.map(\.rawValue))
        XCTAssertEqual(recoveredNames, expectedNames,
                       "interactiveTraitsBitmask must round-trip the trait names")
    }

    func testStaticOnlyTraitsBitmaskRoundTrips() {
        let bitmask = AccessibilityPolicy.staticOnlyTraitsBitmask
        let recoveredNames = Set(bitmask.traitNames)
        let expectedNames = Set(AccessibilityPolicy.staticOnlyTraits.map(\.rawValue))
        XCTAssertEqual(recoveredNames, expectedNames,
                       "staticOnlyTraitsBitmask must round-trip the trait names")
    }

    // MARK: - Name set agreement

    func testTransientTraitNamesAgreesWithTraitSet() {
        let derived = Set(AccessibilityPolicy.transientTraits.map(\.rawValue))
        XCTAssertEqual(AccessibilityPolicy.transientTraitNames, derived,
                       "transientTraitNames must agree with transientTraits.map(\\.rawValue)")
    }

    // MARK: - Synthesis priority pairs

    func testSynthesisPriorityWithMasksMatchesOrdering() {
        let masksNames = AccessibilityPolicy.synthesisPriorityWithMasks.map(\.name)
        let traitNames = AccessibilityPolicy.synthesisPriority.map(\.rawValue)
        XCTAssertEqual(masksNames, traitNames,
                       "synthesisPriorityWithMasks must preserve synthesisPriority ordering")
    }

    func testSynthesisPriorityMasksResolveToNonEmptyBits() {
        // Every trait in the priority list must be a name the parser
        // recognises — otherwise `fromNames` returns `.none` and the
        // synthesiser silently skips that trait.
        for pair in AccessibilityPolicy.synthesisPriorityWithMasks {
            XCTAssertNotEqual(pair.mask, AccessibilityTraits(),
                              "Synthesis priority entry \(pair.name) resolves to no bits — parser does not know this trait")
        }
    }

    // MARK: - Known-trait gate

    func testAllTransientTraitNamesAreKnownToParser() {
        let known = AccessibilityTraits.knownTraitNames
        for name in AccessibilityPolicy.transientTraitNames {
            XCTAssertTrue(known.contains(name),
                          "transientTrait \(name) is not in the parser's knownTraitNames")
        }
    }

    func testAllInteractiveTraitNamesAreKnownToParser() {
        let known = AccessibilityTraits.knownTraitNames
        for trait in AccessibilityPolicy.interactiveTraits {
            XCTAssertTrue(known.contains(trait.rawValue),
                          "interactiveTrait \(trait.rawValue) is not in the parser's knownTraitNames")
        }
    }
}

#endif // canImport(UIKit)

import XCTest
@testable import TheScore

/// Sanity tests for `AccessibilityPolicy` — the single source of truth for
/// trait-related policy. These tests assert that:
/// - Every policy set is non-empty (a regression to "policy was deleted"
///   would not be silent).
/// - The policy sets carry only known `HeistTrait` cases (no `.unknown`).
/// - `synthesisPriority` is duplicate-free and contains only traits that
///   appear in `HeistTrait.allCases`.
/// - `transientTraits` and `interactiveTraits` are disjoint — a trait
///   cannot simultaneously mark "state, not identity" and "user interacts
///   with this".
final class AccessibilityPolicyTests: XCTestCase {

    // MARK: - Non-emptiness

    func testTransientTraitsIsNonEmpty() {
        XCTAssertFalse(AccessibilityPolicy.transientTraits.isEmpty)
    }

    func testInteractiveTraitsIsNonEmpty() {
        XCTAssertFalse(AccessibilityPolicy.interactiveTraits.isEmpty)
    }

    func testStaticOnlyTraitsIsNonEmpty() {
        XCTAssertFalse(AccessibilityPolicy.staticOnlyTraits.isEmpty)
    }

    func testSynthesisPriorityIsNonEmpty() {
        XCTAssertFalse(AccessibilityPolicy.synthesisPriority.isEmpty)
    }

    // MARK: - Known traits only

    func testTransientTraitsContainsNoUnknowns() {
        for trait in AccessibilityPolicy.transientTraits {
            XCTAssertTrue(HeistTrait.allCases.contains(trait),
                          "transientTraits contains a trait outside HeistTrait.allCases: \(trait)")
        }
    }

    func testInteractiveTraitsContainsNoUnknowns() {
        for trait in AccessibilityPolicy.interactiveTraits {
            XCTAssertTrue(HeistTrait.allCases.contains(trait),
                          "interactiveTraits contains a trait outside HeistTrait.allCases: \(trait)")
        }
    }

    func testStaticOnlyTraitsContainsNoUnknowns() {
        for trait in AccessibilityPolicy.staticOnlyTraits {
            XCTAssertTrue(HeistTrait.allCases.contains(trait),
                          "staticOnlyTraits contains a trait outside HeistTrait.allCases: \(trait)")
        }
    }

    func testSynthesisPriorityContainsNoUnknowns() {
        for trait in AccessibilityPolicy.synthesisPriority {
            XCTAssertTrue(HeistTrait.allCases.contains(trait),
                          "synthesisPriority contains a trait outside HeistTrait.allCases: \(trait)")
        }
    }

    // MARK: - Structural invariants

    func testSynthesisPriorityHasNoDuplicates() {
        let unique = Set(AccessibilityPolicy.synthesisPriority)
        XCTAssertEqual(unique.count, AccessibilityPolicy.synthesisPriority.count,
                       "synthesisPriority has duplicate entries")
    }

    func testTransientAndInteractiveAreDisjoint() {
        let overlap = AccessibilityPolicy.transientTraits
            .intersection(AccessibilityPolicy.interactiveTraits)
        XCTAssertTrue(overlap.isEmpty,
                      "transientTraits and interactiveTraits must be disjoint; overlap: \(overlap)")
    }

    func testStaticOnlyAndInteractiveAreDisjoint() {
        let overlap = AccessibilityPolicy.staticOnlyTraits
            .intersection(AccessibilityPolicy.interactiveTraits)
        XCTAssertTrue(overlap.isEmpty,
                      "staticOnlyTraits and interactiveTraits must be disjoint; overlap: \(overlap)")
    }

    // MARK: - Locked contents (regression guard)

    /// `transientTraits` is wire-format-adjacent: it determines what
    /// fields appear in `ElementIdentitySignature` (functional-move
    /// pairing) and what gets stripped from minimal matchers in heists.
    /// Changes here ripple into recorded `.heist` files.
    func testTransientTraitsContentLocked() {
        XCTAssertEqual(AccessibilityPolicy.transientTraits, [
            .selected,
            .notEnabled,
            .isEditing,
            .inactive,
            .visited,
            .updatesFrequently,
        ])
    }

    /// `synthesisPriority` ordering is wire-format: it determines the
    /// suffix of every synthesised `heistId`. Reordering breaks recorded
    /// heists. Locked by `SynthesisDeterminismTests` on the iOS side; this
    /// test pins the contents byte-for-byte.
    func testSynthesisPriorityOrderLocked() {
        XCTAssertEqual(AccessibilityPolicy.synthesisPriority, [
            .backButton,
            .tabBarItem,
            .searchField,
            .textEntry,
            .switchButton,
            .adjustable,
            .header,
            .button,
            .link,
            .image,
            .tabBar,
        ])
    }

    // MARK: - Tab Switch Persistence Threshold

    /// The threshold is a ratio in `(0, 1)` — values outside that range
    /// would either disable the tab-switch heuristic entirely (>= 1) or
    /// make it impossible to trigger (<= 0).
    func testTabSwitchPersistThresholdIsRatio() {
        XCTAssertGreaterThan(AccessibilityPolicy.tabSwitchPersistThreshold, 0.0)
        XCTAssertLessThan(AccessibilityPolicy.tabSwitchPersistThreshold, 1.0)
    }

    /// Locks the current value at `0.4`. Changing this threshold alters
    /// screen-change semantics consumed by `TheBurglar.isTopologyChanged`
    /// and downstream delta computation in `TheBrains`. Any change should
    /// have a clear empirical justification documented in the PR.
    func testTabSwitchPersistThresholdValueLocked() {
        XCTAssertEqual(AccessibilityPolicy.tabSwitchPersistThreshold, 0.4)
    }
}

import XCTest
import ThePlans
@testable import TheScore

/// Sanity tests for `AccessibilityPolicy` — the single source of truth for
/// trait-related policy. These tests assert that:
/// - The policy sets carry only known `HeistTrait` cases (no `.unknown`).
/// - `synthesisPriority` is duplicate-free and contains only traits that
///   appear in `HeistTrait.allCases`.
/// - identity and state partition every trait: each one is exactly one of
///   the two, and together they account for all of `HeistTrait.allCases`.
/// - `staticOnlyTraits` and `interactiveTraits` are disjoint — "static only"
///   means "not interactive", so membership in both is a contradiction.
///
/// Interaction is a third axis, orthogonal to the identity/state partition. See
/// `AccessibilityPolicy` for how the axes cut across each other.
final class AccessibilityPolicyTests: XCTestCase {

    // MARK: - Known traits only

    func testStateTraitsContainsNoUnknowns() {
        for trait in AccessibilityPolicy.stateTraits {
            XCTAssertTrue(HeistTrait.allCases.contains(trait),
                          "stateTraits contains a trait outside HeistTrait.allCases: \(trait)")
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

    func testTextInputTraitsContainsNoUnknowns() {
        for trait in AccessibilityPolicy.textInputTraits {
            XCTAssertTrue(HeistTrait.allCases.contains(trait),
                          "textInputTraits contains a trait outside HeistTrait.allCases: \(trait)")
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

    // MARK: - Every trait is identity or state, and never both

    /// The two kinds partition the traits: a trait either contributes to what
    /// an element *is* or to what state it is *in*, and every trait is one of
    /// them. Asked through the classifier rather than by set arithmetic, because
    /// the classifier is what callers consult — `stateTraits` is the only set
    /// written down, and identity is everything else, so a trait the classifier
    /// mishandles is invisible to a test that only compares the sets.
    func testEveryTraitIsEitherIdentityOrState() {
        var identity: Set<HeistTrait> = []
        var state: Set<HeistTrait> = []

        for trait in HeistTrait.allCases {
            switch AccessibilityPolicy.matcherFactStability(.trait(trait)) {
            case .identity:
                identity.insert(trait)
            case .state:
                state.insert(trait)
            case nil:
                XCTFail("\(trait) is neither identity nor state")
            }
        }

        XCTAssertTrue(
            identity.isDisjoint(with: state),
            "a trait cannot be both: \(identity.intersection(state))"
        )
        XCTAssertEqual(
            identity.union(state), Set(HeistTrait.allCases),
            "every trait must be classified"
        )
        XCTAssertFalse(identity.isEmpty, "no trait establishes identity")
        XCTAssertFalse(state.isEmpty, "no trait carries state")
    }

    /// The set that is written down is the state half, exactly.
    func testStateTraitsAreTheStateHalfOfThePartition() {
        let classified = Set(HeistTrait.allCases.filter {
            AccessibilityPolicy.matcherFactStability(.trait($0)) == .state
        })
        XCTAssertEqual(classified, AccessibilityPolicy.stateTraits)
    }

    func testStaticOnlyAndInteractiveAreDisjoint() {
        let overlap = AccessibilityPolicy.staticOnlyTraits
            .intersection(AccessibilityPolicy.interactiveTraits)
        XCTAssertTrue(overlap.isEmpty,
                      "staticOnlyTraits and interactiveTraits must be disjoint; overlap: \(overlap)")
    }

    func testTextInputTraitsIdentifyEveryTextInputShape() {
        for trait in [.textEntry, .searchField, .secureTextField, .textArea] as [HeistTrait] {
            XCTAssertTrue(AccessibilityPolicy.supportsTextEntry([trait]))
        }
        XCTAssertFalse(AccessibilityPolicy.supportsTextEntry([.button]))
        XCTAssertFalse(AccessibilityPolicy.supportsTextEntry([.isEditing]))
        XCTAssertFalse(AccessibilityPolicy.supportsTextEntry([.textOperationsAvailable]))
    }

    // MARK: - Locked contents (regression guard)

    /// `stateTraits` is wire-format-adjacent: it determines what
    /// fields appear in `ElementIdentitySignature` (functional-move
    /// pairing) and what gets stripped from minimal matchers in heists.
    /// Changes here ripple into generated `.heist` artifacts.
    func testStateTraitsContentLocked() {
        XCTAssertEqual(AccessibilityPolicy.stateTraits, [
            .selected,
            .notEnabled,
            .isEditing,
            .inactive,
            .visited,
            .updatesFrequently,
        ])
    }

    /// `synthesisPriority` ordering is wire-format: it determines the
    /// suffix of every synthesised `heistId`. Reordering breaks stable
    /// heist identity. Locked by `SynthesisDeterminismTests` on the iOS side; this
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
    /// screen-change semantics consumed by trace projection. Any change
    /// should have a clear empirical justification documented in the PR.
    func testTabSwitchPersistThresholdValueLocked() {
        XCTAssertEqual(AccessibilityPolicy.tabSwitchPersistThreshold, 0.4)
    }
}

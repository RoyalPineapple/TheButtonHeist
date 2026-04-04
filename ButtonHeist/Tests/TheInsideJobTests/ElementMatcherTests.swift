#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class ElementMatcherTests: XCTestCase {

    // MARK: - Test Fixtures

    private func element(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none,
        hint: String? = nil
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
            label: label,
            value: value,
            traits: traits,
            identifier: identifier,
            hint: hint,
            userInputLabels: nil,
            shape: .frame(.zero),
            activationPoint: .zero,
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
        )
    }

    // MARK: - Label Matching

    func testMatchByLabelExact() {
        let element = element(label: "Save")
        let matcher = ElementMatcher(label: "Save")
        XCTAssertTrue(element.matches(matcher))
    }

    func testLabelMismatch() {
        let element = element(label: "Save")
        let matcher = ElementMatcher(label: "Cancel")
        XCTAssertFalse(element.matches(matcher))
    }

    func testLabelIsCaseInsensitive() {
        let element = element(label: "Save")
        XCTAssertTrue(element.matches(ElementMatcher(label: "save")))
        XCTAssertTrue(element.matches(ElementMatcher(label: "SAVE")))
        XCTAssertTrue(element.matches(ElementMatcher(label: "sAvE")))
    }

    func testLabelSubstringMatch() {
        let element = element(label: "Save Changes")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save")))
        XCTAssertTrue(element.matches(ElementMatcher(label: "Changes")))
        XCTAssertTrue(element.matches(ElementMatcher(label: "save changes")))
        XCTAssertFalse(element.matches(ElementMatcher(label: "Delete")))
    }

    func testLabelNilOnElementDoesNotMatchEmptyString() {
        let element = element(label: nil)
        let matcher = ElementMatcher(label: "")
        XCTAssertFalse(element.matches(matcher))
    }

    func testLabelEmptyStringMatches() {
        // Empty matcher label is a substring of any label — always matches
        let element = element(label: "")
        let matcher = ElementMatcher(label: "")
        // "".localizedCaseInsensitiveContains("") is false per Foundation
        // semantics, so empty-string matcher against empty-string label
        // does not match. Use a nil matcher label to match any element.
        XCTAssertFalse(element.matches(matcher))
    }

    func testLabelWithUnicode() {
        let element = element(label: "🔴 Error")
        let matcher = ElementMatcher(label: "🔴 Error")
        XCTAssertTrue(element.matches(matcher))
    }

    func testLabelWithNewline() {
        let element = element(label: "Line 1\nLine 2")
        let matcher = ElementMatcher(label: "Line 1\nLine 2")
        XCTAssertTrue(element.matches(matcher))
    }

    func testLabelWithLeadingTrailingWhitespace() {
        // Substring matching — "Save" is found inside " Save "
        let element = element(label: " Save ")
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save")))
        XCTAssertTrue(element.matches(ElementMatcher(label: " Save ")))
    }

    // MARK: - Identifier Matching

    func testMatchByIdentifierExact() {
        let element = element(identifier: "com.app.saveButton")
        let matcher = ElementMatcher(identifier: "com.app.saveButton")
        XCTAssertTrue(element.matches(matcher))
    }

    func testIdentifierMismatch() {
        let element = element(identifier: "com.app.saveButton")
        let matcher = ElementMatcher(identifier: "com.app.cancelButton")
        XCTAssertFalse(element.matches(matcher))
    }

    func testIdentifierNilOnElement() {
        let element = element(identifier: nil)
        let matcher = ElementMatcher(identifier: "anything")
        XCTAssertFalse(element.matches(matcher))
    }

    func testIdentifierIsCaseInsensitive() {
        let element = element(identifier: "SaveBtn")
        XCTAssertTrue(element.matches(ElementMatcher(identifier: "savebtn")))
        XCTAssertTrue(element.matches(ElementMatcher(identifier: "SAVEBTN")))
        XCTAssertFalse(element.matches(ElementMatcher(identifier: "OtherBtn")))
    }

    // MARK: - Value Matching

    func testMatchByValueExact() {
        let element = element(value: "50%")
        let matcher = ElementMatcher(value: "50%")
        XCTAssertTrue(element.matches(matcher))
    }

    func testValueMismatch() {
        let element = element(value: "50%")
        let matcher = ElementMatcher(value: "75%")
        XCTAssertFalse(element.matches(matcher))
    }

    func testValueNilOnElementDoesNotMatchEmptyString() {
        let element = element(value: nil)
        let matcher = ElementMatcher(value: "")
        XCTAssertFalse(element.matches(matcher))
    }

    func testValueEmptyStringMatchesEmptyString() {
        // Foundation: "".localizedCaseInsensitiveContains("") is false
        let element = element(value: "")
        let matcher = ElementMatcher(value: "")
        XCTAssertFalse(element.matches(matcher))
    }

    // MARK: - Trait Matching (Required)

    func testSingleTraitPresent() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(traits: [.button])
        XCTAssertTrue(element.matches(matcher))
    }

    func testSingleTraitAbsent() {
        let element = element(traits: .staticText)
        let matcher = ElementMatcher(traits: [.button])
        XCTAssertFalse(element.matches(matcher))
    }

    func testMultipleTraitsAllPresent() {
        let element = element(traits: [.button, .selected])
        let matcher = ElementMatcher(traits: [.button, .selected])
        XCTAssertTrue(element.matches(matcher))
    }

    func testMultipleTraitsOneAbsent() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(traits: [.button, .selected])
        XCTAssertFalse(element.matches(matcher))
    }

    func testTraitOrderDoesNotMatter() {
        let element = element(traits: [.header, .button])
        let matcherAB = ElementMatcher(traits: [.button, .header])
        let matcherBA = ElementMatcher(traits: [.header, .button])
        XCTAssertTrue(element.matches(matcherAB))
        XCTAssertTrue(element.matches(matcherBA))
    }

    func testElementHasExtraTraitsStillMatches() {
        let element = element(traits: [.button, .selected, .header])
        let matcher = ElementMatcher(traits: [.button])
        XCTAssertTrue(element.matches(matcher))
    }

    func testEmptyTraitsArrayMatchesAnything() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(traits: [])
        XCTAssertTrue(element.matches(matcher))
    }

    func testTraitsNilMatchesAnything() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(traits: nil)
        XCTAssertTrue(element.matches(matcher))
    }

    func testNoTraitsDoesNotMatchRequiredTrait() {
        let element = element(traits: .none)
        let matcher = ElementMatcher(traits: [.button])
        XCTAssertFalse(element.matches(matcher))
    }

    func testBackButtonTrait() {
        let element = element(traits: UIAccessibilityTraits(rawValue: 0x8000000))
        let matcher = ElementMatcher(traits: [.backButton])
        XCTAssertTrue(element.matches(matcher))
    }

    func testAdjustableTrait() {
        let element = element(traits: .adjustable)
        let matcher = ElementMatcher(traits: [.adjustable])
        XCTAssertTrue(element.matches(matcher))
    }

    func testSearchFieldTrait() {
        let element = element(traits: .searchField)
        let matcher = ElementMatcher(traits: [.searchField])
        XCTAssertTrue(element.matches(matcher))
    }

    func testNotEnabledTrait() {
        let element = element(traits: .notEnabled)
        let matcher = ElementMatcher(traits: [.notEnabled])
        XCTAssertTrue(element.matches(matcher))
    }

    // MARK: - Trait Exclusion

    func testExcludeSingleTraitAbsent() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(excludeTraits: [.selected])
        XCTAssertTrue(element.matches(matcher))
    }

    func testExcludeSingleTraitPresent() {
        let element = element(traits: [.button, .selected])
        let matcher = ElementMatcher(excludeTraits: [.selected])
        XCTAssertFalse(element.matches(matcher))
    }

    func testExcludeMultipleTraitsNonePresent() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(excludeTraits: [.selected, .notEnabled])
        XCTAssertTrue(element.matches(matcher))
    }

    func testExcludeMultipleTraitsOnePresent() {
        let element = element(traits: [.button, .notEnabled])
        let matcher = ElementMatcher(excludeTraits: [.selected, .notEnabled])
        XCTAssertFalse(element.matches(matcher))
    }

    func testExcludeEmptyArrayMatchesAnything() {
        let element = element(traits: [.button, .selected])
        let matcher = ElementMatcher(excludeTraits: [])
        XCTAssertTrue(element.matches(matcher))
    }

    func testExcludeNilMatchesAnything() {
        let element = element(traits: [.button, .selected])
        let matcher = ElementMatcher(excludeTraits: nil)
        XCTAssertTrue(element.matches(matcher))
    }

    // MARK: - Combined Trait Include + Exclude

    func testIncludeAndExcludeBothSatisfied() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(traits: [.button], excludeTraits: [.selected])
        XCTAssertTrue(element.matches(matcher))
    }

    func testIncludeSatisfiedButExcludeViolated() {
        let element = element(traits: [.button, .selected])
        let matcher = ElementMatcher(traits: [.button], excludeTraits: [.selected])
        XCTAssertFalse(element.matches(matcher))
    }

    func testIncludeViolatedExcludeSatisfied() {
        let element = element(traits: .staticText)
        let matcher = ElementMatcher(traits: [.button], excludeTraits: [.selected])
        XCTAssertFalse(element.matches(matcher))
    }

    func testSameTraitInIncludeAndExcludeAlwaysFails() {
        let element = element(traits: .button)
        let matcher = ElementMatcher(traits: [.button], excludeTraits: [.button])
        XCTAssertFalse(element.matches(matcher))
    }

    // MARK: - Compound Predicate (Multiple Fields)

    func testLabelAndIdentifier() {
        let element = element(label: "Save", identifier: "saveBtn")
        XCTAssertTrue(element.matches(
            ElementMatcher(label: "Save", identifier: "saveBtn")))
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Save", identifier: "cancelBtn")))
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Cancel", identifier: "saveBtn")))
    }

    func testLabelAndValue() {
        let element = element(label: "Volume", value: "50%")
        XCTAssertTrue(element.matches(
            ElementMatcher(label: "Volume", value: "50%")))
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Volume", value: "75%")))
    }

    func testLabelAndTraits() {
        let element = element(label: "Settings", traits: .header)
        XCTAssertTrue(element.matches(
            ElementMatcher(label: "Settings", traits: [.header])))
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Settings", traits: [.button])))
    }

    func testLabelIdentifierValueTraits() {
        let element = element(label: "Dark Mode", value: "ON", identifier: "darkModeToggle", traits: [.button, .selected])
        let matcher = ElementMatcher(
            label: "Dark Mode", identifier: "darkModeToggle",
            value: "ON", traits: [.button, .selected]
        )
        XCTAssertTrue(element.matches(matcher))
    }

    func testAllFieldsMustMatchAndOneDoesNot() {
        let element = element(label: "Dark Mode", value: "ON", identifier: "darkModeToggle", traits: [.button, .selected])
        // Wrong value
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Dark Mode", identifier: "darkModeToggle", value: "OFF", traits: [.button, .selected])
        ))
    }

    func testLabelAndExcludeTraits() {
        let enabled = element(label: "Submit", traits: .button)
        let disabled = element(label: "Submit", traits: [.button, .notEnabled])
        let matcher = ElementMatcher(label: "Submit", excludeTraits: [.notEnabled])
        XCTAssertTrue(enabled.matches(matcher))
        XCTAssertFalse(disabled.matches(matcher))
    }

    // MARK: - Wildcard Fields (nil = match anything)

    func testEmptyMatcherMatchesEverything() {
        let matcher = ElementMatcher()
        XCTAssertTrue(element(label: "Save", traits: .button).matches(matcher))
        XCTAssertTrue(element(label: nil, traits: .none).matches(matcher))
        XCTAssertTrue(element(value: "100%", identifier: "slider").matches(matcher))
    }

    func testNilFieldsAreWildcards() {
        let element = element(label: "Save", value: "draft", identifier: "btn", traits: .button)
        // Only label specified — value, identifier, traits are wildcards
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save")))
        // Only identifier specified
        XCTAssertTrue(element.matches(ElementMatcher(identifier: "btn")))
        // Only value specified
        XCTAssertTrue(element.matches(ElementMatcher(value: "draft")))
        // Only traits specified
        XCTAssertTrue(element.matches(ElementMatcher(traits: [.button])))
    }

    func testHasPredicatesIgnoresEmptyTraitArrays() {
        XCTAssertFalse(ElementMatcher(traits: []).hasPredicates)
        XCTAssertFalse(ElementMatcher(excludeTraits: []).hasPredicates)
        XCTAssertFalse(ElementMatcher(traits: [], excludeTraits: []).hasPredicates)
        XCTAssertTrue(ElementMatcher(label: "Save", traits: []).hasPredicates)
    }

    func testNonEmptyReturnsNilForEmptyMatcher() {
        XCTAssertNil(ElementMatcher().nonEmpty)
        XCTAssertNil(ElementMatcher(traits: []).nonEmpty)
        XCTAssertEqual(ElementMatcher(label: "Save").nonEmpty, ElementMatcher(label: "Save"))
    }

    func testElementTargetMatcherInitializerDropsEmptyMatcher() {
        XCTAssertNil(ElementTarget(matcher: ElementMatcher()))

        let target = ElementTarget(heistId: "save_button", matcher: ElementMatcher())
        guard case .heistId(let id) = target else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "save_button")
    }

    func testScrollToVisibleTargetWithElementTarget() {
        let empty = ScrollToVisibleTarget()
        XCTAssertNil(empty.elementTarget)

        let withId = ScrollToVisibleTarget(elementTarget: .heistId("save_button"))
        guard case .heistId(let id) = withId.elementTarget else {
            return XCTFail("Expected .heistId")
        }
        XCTAssertEqual(id, "save_button")
    }

    // MARK: - Unknown Trait Names

    func testUnknownTraitNameNeverMatches() {
        let element = element(traits: [.button, .selected, .header])
        let matcher = ElementMatcher(traits: [.unknown("madeUpTrait")])
        XCTAssertFalse(element.matches(matcher))
    }

    func testUnknownExcludeTraitNeverMatches() {
        let element = element(traits: [.button, .selected])
        let matcher = ElementMatcher(excludeTraits: [.unknown("madeUpTrait")])
        XCTAssertFalse(element.matches(matcher))
    }

    // MARK: - Edge Cases

    func testVeryLongLabel() {
        let longLabel = String(repeating: "a", count: 10_000)
        let element = element(label: longLabel)
        let matcher = ElementMatcher(label: longLabel)
        XCTAssertTrue(element.matches(matcher))
    }

    func testLabelWithNullCharacter() {
        let element = element(label: "before\0after")
        let matcher = ElementMatcher(label: "before\0after")
        XCTAssertTrue(element.matches(matcher))
        // Substring matching — "before" is found inside "before\0after"
        XCTAssertTrue(element.matches(ElementMatcher(label: "before")))
    }

    func testAllFieldsNilOnElement() {
        let element = element()
        XCTAssertTrue(element.matches(ElementMatcher()))
        XCTAssertFalse(element.matches(ElementMatcher(label: "anything")))
        XCTAssertFalse(element.matches(ElementMatcher(identifier: "anything")))
        XCTAssertFalse(element.matches(ElementMatcher(value: "anything")))
    }

    // MARK: - Hierarchy Matching

    private func group(children: [AccessibilityHierarchy]) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(type: .semanticGroup(label: nil, value: nil, identifier: nil), frame: .zero),
            children: children
        )
    }

    func testHierarchyMatchFindsLeaf() {
        let leaf = AccessibilityHierarchy.element(element(label: "Target", traits: .button), traversalIndex: 3)
        let matcher = ElementMatcher(label: "Target")
        let result = [leaf].firstMatch(matcher)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Target")
    }

    func testHierarchyMatchSkipsContainer() {
        let container = group(children: [
            .element(element(label: "Child", traits: .button), traversalIndex: 0)
        ])
        let matcher = ElementMatcher(label: "Child")
        let result = [container].firstMatch(matcher)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Child")
    }

    func testHierarchyMatchReturnsNilWhenNoMatch() {
        let leaf = AccessibilityHierarchy.element(element(label: "Other"), traversalIndex: 0)
        let matcher = ElementMatcher(label: "Target")
        XCTAssertNil([leaf].firstMatch(matcher))
    }

    func testHierarchyArrayFirstMatch() {
        let tree: [AccessibilityHierarchy] = [
            .element(element(label: "First", traits: .header), traversalIndex: 0),
            .element(element(label: "Second", traits: .button), traversalIndex: 1),
            .element(element(label: "Third", traits: .button), traversalIndex: 2),
        ]
        let matcher = ElementMatcher(traits: [.button])
        let result = tree.firstMatch(matcher)
        XCTAssertEqual(result?.element.label, "Second")
    }

    func testHierarchyArrayAllMatches() {
        let tree: [AccessibilityHierarchy] = [
            .element(element(label: "A", traits: .button), traversalIndex: 0),
            .element(element(label: "B", traits: .header), traversalIndex: 1),
            .element(element(label: "C", traits: .button), traversalIndex: 2),
        ]
        let results = tree.allMatches(ElementMatcher(traits: [.button]))
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].element.label, "A")
        XCTAssertEqual(results[1].element.label, "C")
    }

    func testHierarchyNestedContainerSearch() {
        let tree: [AccessibilityHierarchy] = [
            group(children: [
                group(children: [
                    .element(element(label: "Deep Target", identifier: "deep"), traversalIndex: 5)
                ])
            ])
        ]
        let result = tree.firstMatch(ElementMatcher(identifier: "deep"))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Deep Target")
    }

    func testHierarchyContainerLabelDoesNotMatch() {
        // Container has label "Settings" but only leaf elements should match
        let tree: [AccessibilityHierarchy] = [
            .container(
                AccessibilityContainer(type: .semanticGroup(label: "Settings", value: nil, identifier: nil), frame: .zero),
                children: [
                    .element(element(label: "Volume"), traversalIndex: 0)
                ]
            )
        ]
        let result = tree.firstMatch(ElementMatcher(label: "Settings"))
        XCTAssertNil(result)
    }

    func testHierarchyHasMatchOnEmptyTree() {
        let tree: [AccessibilityHierarchy] = []
        XCTAssertFalse(tree.hasMatch(ElementMatcher(label: "Anything")))
    }

    // MARK: - StableKey

    func testStableKeyEqualForSameProperties() {
        let a = element(label: "Save", value: "draft", identifier: "btn", traits: .button)
        let b = element(label: "Save", value: "draft", identifier: "btn", traits: .button)
        XCTAssertEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyDiffersOnLabel() {
        let a = element(label: "Save")
        let b = element(label: "Cancel")
        XCTAssertNotEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyDiffersOnIdentifier() {
        let a = element(label: "Save", identifier: "a")
        let b = element(label: "Save", identifier: "b")
        XCTAssertNotEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyDiffersOnValue() {
        let a = element(label: "Slider", value: "50%")
        let b = element(label: "Slider", value: "75%")
        XCTAssertNotEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyDiffersOnTraits() {
        let a = element(label: "Save", traits: .button)
        let b = element(label: "Save", traits: [.button, .selected])
        XCTAssertNotEqual(a.stableKey, b.stableKey)
    }

    func testStableKeySetDeduplicates() {
        let elements = [
            element(label: "Save", traits: .button),
            element(label: "Save", traits: .button),
            element(label: "Cancel", traits: .button),
        ]
        let keys = Set(elements.map(\.stableKey))
        XCTAssertEqual(keys.count, 2)
    }

    func testStableKeyFallsBackToFrameWhenNoSemanticIdentity() {
        let a = AccessibilityElement(
            description: "", label: nil, value: nil, traits: .none,
            identifier: nil, hint: nil, userInputLabels: nil,
            shape: .frame(CGRect(x: 0, y: 0, width: 44, height: 44)),
            activationPoint: CGPoint(x: 22, y: 22),
            usesDefaultActivationPoint: true,
            customActions: [], customContent: [], customRotors: [],
            accessibilityLanguage: nil, respondsToUserInteraction: true
        )
        let b = AccessibilityElement(
            description: "", label: nil, value: nil, traits: .none,
            identifier: nil, hint: nil, userInputLabels: nil,
            shape: .frame(CGRect(x: 0, y: 200, width: 44, height: 44)),
            activationPoint: CGPoint(x: 22, y: 222),
            usesDefaultActivationPoint: true,
            customActions: [], customContent: [], customRotors: [],
            accessibilityLanguage: nil, respondsToUserInteraction: true
        )
        XCTAssertNotEqual(a.stableKey, b.stableKey, "Unlabeled elements at different positions must hash differently")
    }

    func testStableKeySameFrameSameKeyWhenNoSemanticIdentity() {
        let a = AccessibilityElement(
            description: "", label: nil, value: nil, traits: .none,
            identifier: nil, hint: nil, userInputLabels: nil,
            shape: .frame(CGRect(x: 10, y: 10, width: 44, height: 44)),
            activationPoint: CGPoint(x: 32, y: 32),
            usesDefaultActivationPoint: true,
            customActions: [], customContent: [], customRotors: [],
            accessibilityLanguage: nil, respondsToUserInteraction: true
        )
        let b = AccessibilityElement(
            description: "", label: nil, value: nil, traits: .none,
            identifier: nil, hint: nil, userInputLabels: nil,
            shape: .frame(CGRect(x: 10, y: 10, width: 44, height: 44)),
            activationPoint: CGPoint(x: 32, y: 32),
            usesDefaultActivationPoint: true,
            customActions: [], customContent: [], customRotors: [],
            accessibilityLanguage: nil, respondsToUserInteraction: true
        )
        XCTAssertEqual(a.stableKey, b.stableKey, "Same frame + no semantics = same key")
    }

    // MARK: - Absent Flag

    // absent is handled at the wait_for level (WaitForTarget.absent),
    // not on ElementMatcher itself. See WaitForTarget tests in TheScoreTests.

    // MARK: - Hierarchy Tree Matching

    private func labeledGroup(
        label: String,
        children: [AccessibilityHierarchy]
    ) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(
                type: .semanticGroup(label: label, value: nil, identifier: nil),
                frame: .zero
            ),
            children: children
        )
    }

    func testHierarchyMatchesLeafElement() {
        let tree: [AccessibilityHierarchy] = [
            .element(element(label: "Save"), traversalIndex: 0)
        ]
        let result = tree.firstMatch(ElementMatcher(label: "Save"))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Save")
    }

    func testHierarchySkipsContainers() {
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Nav", children: [
                .element(element(label: "Item"), traversalIndex: 0)
            ])
        ]
        // Container label "Nav" should not match — only leaf elements match
        XCTAssertNil(tree.firstMatch(ElementMatcher(label: "Nav")))
    }

    func testHierarchyRecursesIntoContainersToFindLeaves() {
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Section", children: [
                .element(element(label: "Target"), traversalIndex: 0)
            ])
        ]
        let result = tree.firstMatch(ElementMatcher(label: "Target"))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Target")
    }

    func testHierarchyDeepNesting() {
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Outer", children: [
                labeledGroup(label: "Inner", children: [
                    .element(element(label: "Leaf"), traversalIndex: 0)
                ])
            ])
        ]
        let result = tree.firstMatch(ElementMatcher(label: "Leaf"))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Leaf")
    }

    func testAllMatchesFindsMultipleLeaves() {
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Section", children: [
                .element(element(label: "Item"), traversalIndex: 0),
                .element(element(label: "Item"), traversalIndex: 1),
            ])
        ]
        let results = tree.allMatches(ElementMatcher(label: "Item"))
        XCTAssertEqual(results.count, 2)
    }
}

#endif

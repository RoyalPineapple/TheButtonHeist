#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class ElementMatcherTests: XCTestCase {

    // MARK: - Test Fixtures

    private func el(
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
        let element = el(label: "Save")
        let matcher = ElementMatcher(label: "Save")
        XCTAssertTrue(element.matches(matcher))
    }

    func testLabelMismatch() {
        let element = el(label: "Save")
        let matcher = ElementMatcher(label: "Cancel")
        XCTAssertFalse(element.matches(matcher))
    }

    func testLabelIsCaseSensitive() {
        let element = el(label: "Save")
        XCTAssertFalse(element.matches(ElementMatcher(label: "save")))
        XCTAssertFalse(element.matches(ElementMatcher(label: "SAVE")))
        XCTAssertFalse(element.matches(ElementMatcher(label: "sAvE")))
    }

    func testLabelNoSubstringMatch() {
        let element = el(label: "Save Changes")
        XCTAssertFalse(element.matches(ElementMatcher(label: "Save")))
        XCTAssertFalse(element.matches(ElementMatcher(label: "Changes")))
    }

    func testLabelNilOnElementDoesNotMatchEmptyString() {
        let element = el(label: nil)
        let matcher = ElementMatcher(label: "")
        XCTAssertFalse(element.matches(matcher))
    }

    func testLabelEmptyStringMatches() {
        let element = el(label: "")
        let matcher = ElementMatcher(label: "")
        XCTAssertTrue(element.matches(matcher))
    }

    func testLabelWithUnicode() {
        let element = el(label: "🔴 Error")
        let matcher = ElementMatcher(label: "🔴 Error")
        XCTAssertTrue(element.matches(matcher))
    }

    func testLabelWithNewline() {
        let element = el(label: "Line 1\nLine 2")
        let matcher = ElementMatcher(label: "Line 1\nLine 2")
        XCTAssertTrue(element.matches(matcher))
    }

    func testLabelWithLeadingTrailingWhitespace() {
        let element = el(label: " Save ")
        XCTAssertFalse(element.matches(ElementMatcher(label: "Save")))
        XCTAssertTrue(element.matches(ElementMatcher(label: " Save ")))
    }

    // MARK: - Identifier Matching

    func testMatchByIdentifierExact() {
        let element = el(identifier: "com.app.saveButton")
        let matcher = ElementMatcher(identifier: "com.app.saveButton")
        XCTAssertTrue(element.matches(matcher))
    }

    func testIdentifierMismatch() {
        let element = el(identifier: "com.app.saveButton")
        let matcher = ElementMatcher(identifier: "com.app.cancelButton")
        XCTAssertFalse(element.matches(matcher))
    }

    func testIdentifierNilOnElement() {
        let element = el(identifier: nil)
        let matcher = ElementMatcher(identifier: "anything")
        XCTAssertFalse(element.matches(matcher))
    }

    func testIdentifierIsCaseSensitive() {
        let element = el(identifier: "SaveBtn")
        XCTAssertFalse(element.matches(ElementMatcher(identifier: "savebtn")))
    }

    // MARK: - Value Matching

    func testMatchByValueExact() {
        let element = el(value: "50%")
        let matcher = ElementMatcher(value: "50%")
        XCTAssertTrue(element.matches(matcher))
    }

    func testValueMismatch() {
        let element = el(value: "50%")
        let matcher = ElementMatcher(value: "75%")
        XCTAssertFalse(element.matches(matcher))
    }

    func testValueNilOnElementDoesNotMatchEmptyString() {
        let element = el(value: nil)
        let matcher = ElementMatcher(value: "")
        XCTAssertFalse(element.matches(matcher))
    }

    func testValueEmptyStringMatchesEmptyString() {
        let element = el(value: "")
        let matcher = ElementMatcher(value: "")
        XCTAssertTrue(element.matches(matcher))
    }

    // MARK: - Trait Matching (Required)

    func testSingleTraitPresent() {
        let element = el(traits: .button)
        let matcher = ElementMatcher(traits: ["button"])
        XCTAssertTrue(element.matches(matcher))
    }

    func testSingleTraitAbsent() {
        let element = el(traits: .staticText)
        let matcher = ElementMatcher(traits: ["button"])
        XCTAssertFalse(element.matches(matcher))
    }

    func testMultipleTraitsAllPresent() {
        let element = el(traits: [.button, .selected])
        let matcher = ElementMatcher(traits: ["button", "selected"])
        XCTAssertTrue(element.matches(matcher))
    }

    func testMultipleTraitsOneAbsent() {
        let element = el(traits: .button)
        let matcher = ElementMatcher(traits: ["button", "selected"])
        XCTAssertFalse(element.matches(matcher))
    }

    func testTraitOrderDoesNotMatter() {
        let element = el(traits: [.header, .button])
        let matcherAB = ElementMatcher(traits: ["button", "header"])
        let matcherBA = ElementMatcher(traits: ["header", "button"])
        XCTAssertTrue(element.matches(matcherAB))
        XCTAssertTrue(element.matches(matcherBA))
    }

    func testElementHasExtraTraitsStillMatches() {
        let element = el(traits: [.button, .selected, .header])
        let matcher = ElementMatcher(traits: ["button"])
        XCTAssertTrue(element.matches(matcher))
    }

    func testEmptyTraitsArrayMatchesAnything() {
        let element = el(traits: .button)
        let matcher = ElementMatcher(traits: [])
        XCTAssertTrue(element.matches(matcher))
    }

    func testTraitsNilMatchesAnything() {
        let element = el(traits: .button)
        let matcher = ElementMatcher(traits: nil)
        XCTAssertTrue(element.matches(matcher))
    }

    func testNoTraitsDoesNotMatchRequiredTrait() {
        let element = el(traits: .none)
        let matcher = ElementMatcher(traits: ["button"])
        XCTAssertFalse(element.matches(matcher))
    }

    func testBackButtonTrait() {
        let element = el(traits: UIAccessibilityTraits(rawValue: 0x8000000))
        let matcher = ElementMatcher(traits: ["backButton"])
        XCTAssertTrue(element.matches(matcher))
    }

    func testAdjustableTrait() {
        let element = el(traits: .adjustable)
        let matcher = ElementMatcher(traits: ["adjustable"])
        XCTAssertTrue(element.matches(matcher))
    }

    func testSearchFieldTrait() {
        let element = el(traits: .searchField)
        let matcher = ElementMatcher(traits: ["searchField"])
        XCTAssertTrue(element.matches(matcher))
    }

    func testNotEnabledTrait() {
        let element = el(traits: .notEnabled)
        let matcher = ElementMatcher(traits: ["notEnabled"])
        XCTAssertTrue(element.matches(matcher))
    }

    // MARK: - Trait Exclusion

    func testExcludeSingleTraitAbsent() {
        let element = el(traits: .button)
        let matcher = ElementMatcher(excludeTraits: ["selected"])
        XCTAssertTrue(element.matches(matcher))
    }

    func testExcludeSingleTraitPresent() {
        let element = el(traits: [.button, .selected])
        let matcher = ElementMatcher(excludeTraits: ["selected"])
        XCTAssertFalse(element.matches(matcher))
    }

    func testExcludeMultipleTraitsNonePresent() {
        let element = el(traits: .button)
        let matcher = ElementMatcher(excludeTraits: ["selected", "notEnabled"])
        XCTAssertTrue(element.matches(matcher))
    }

    func testExcludeMultipleTraitsOnePresent() {
        let element = el(traits: [.button, .notEnabled])
        let matcher = ElementMatcher(excludeTraits: ["selected", "notEnabled"])
        XCTAssertFalse(element.matches(matcher))
    }

    func testExcludeEmptyArrayMatchesAnything() {
        let element = el(traits: [.button, .selected])
        let matcher = ElementMatcher(excludeTraits: [])
        XCTAssertTrue(element.matches(matcher))
    }

    func testExcludeNilMatchesAnything() {
        let element = el(traits: [.button, .selected])
        let matcher = ElementMatcher(excludeTraits: nil)
        XCTAssertTrue(element.matches(matcher))
    }

    // MARK: - Combined Trait Include + Exclude

    func testIncludeAndExcludeBothSatisfied() {
        let element = el(traits: .button)
        let matcher = ElementMatcher(traits: ["button"], excludeTraits: ["selected"])
        XCTAssertTrue(element.matches(matcher))
    }

    func testIncludeSatisfiedButExcludeViolated() {
        let element = el(traits: [.button, .selected])
        let matcher = ElementMatcher(traits: ["button"], excludeTraits: ["selected"])
        XCTAssertFalse(element.matches(matcher))
    }

    func testIncludeViolatedExcludeSatisfied() {
        let element = el(traits: .staticText)
        let matcher = ElementMatcher(traits: ["button"], excludeTraits: ["selected"])
        XCTAssertFalse(element.matches(matcher))
    }

    func testSameTraitInIncludeAndExcludeAlwaysFails() {
        let element = el(traits: .button)
        let matcher = ElementMatcher(traits: ["button"], excludeTraits: ["button"])
        XCTAssertFalse(element.matches(matcher))
    }

    // MARK: - Compound Predicate (Multiple Fields)

    func testLabelAndIdentifier() {
        let element = el(label: "Save", identifier: "saveBtn")
        XCTAssertTrue(element.matches(
            ElementMatcher(label: "Save", identifier: "saveBtn")))
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Save", identifier: "cancelBtn")))
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Cancel", identifier: "saveBtn")))
    }

    func testLabelAndValue() {
        let element = el(label: "Volume", value: "50%")
        XCTAssertTrue(element.matches(
            ElementMatcher(label: "Volume", value: "50%")))
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Volume", value: "75%")))
    }

    func testLabelAndTraits() {
        let element = el(label: "Settings", traits: .header)
        XCTAssertTrue(element.matches(
            ElementMatcher(label: "Settings", traits: ["header"])))
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Settings", traits: ["button"])))
    }

    func testLabelIdentifierValueTraits() {
        let element = el(label: "Dark Mode", value: "ON", identifier: "darkModeToggle", traits: [.button, .selected])
        let matcher = ElementMatcher(
            label: "Dark Mode", identifier: "darkModeToggle",
            value: "ON", traits: ["button", "selected"]
        )
        XCTAssertTrue(element.matches(matcher))
    }

    func testAllFieldsMustMatchAndOneDoesNot() {
        let element = el(label: "Dark Mode", value: "ON", identifier: "darkModeToggle", traits: [.button, .selected])
        // Wrong value
        XCTAssertFalse(element.matches(
            ElementMatcher(label: "Dark Mode", identifier: "darkModeToggle", value: "OFF", traits: ["button", "selected"])
        ))
    }

    func testLabelAndExcludeTraits() {
        let enabled = el(label: "Submit", traits: .button)
        let disabled = el(label: "Submit", traits: [.button, .notEnabled])
        let matcher = ElementMatcher(label: "Submit", excludeTraits: ["notEnabled"])
        XCTAssertTrue(enabled.matches(matcher))
        XCTAssertFalse(disabled.matches(matcher))
    }

    // MARK: - Wildcard Fields (nil = match anything)

    func testEmptyMatcherMatchesEverything() {
        let matcher = ElementMatcher()
        XCTAssertTrue(el(label: "Save", traits: .button).matches(matcher))
        XCTAssertTrue(el(label: nil, traits: .none).matches(matcher))
        XCTAssertTrue(el(value: "100%", identifier: "slider").matches(matcher))
    }

    func testNilFieldsAreWildcards() {
        let element = el(label: "Save", value: "draft", identifier: "btn", traits: .button)
        // Only label specified — value, identifier, traits are wildcards
        XCTAssertTrue(element.matches(ElementMatcher(label: "Save")))
        // Only identifier specified
        XCTAssertTrue(element.matches(ElementMatcher(identifier: "btn")))
        // Only value specified
        XCTAssertTrue(element.matches(ElementMatcher(value: "draft")))
        // Only traits specified
        XCTAssertTrue(element.matches(ElementMatcher(traits: ["button"])))
    }

    // MARK: - heistId Is Ignored at Hierarchy Level

    func testHeistIdFieldIsIgnored() {
        let element = el(label: "Save", identifier: "saveBtn")
        let matcher = ElementMatcher(heistId: "button_save")
        // heistId is a wire-level concept — hierarchy matching ignores it
        XCTAssertTrue(element.matches(matcher))
    }

    // MARK: - Unknown Trait Names

    func testUnknownTraitNameNeverMatches() {
        let element = el(traits: [.button, .selected, .header])
        let matcher = ElementMatcher(traits: ["madeUpTrait"])
        XCTAssertFalse(element.matches(matcher))
    }

    func testUnknownExcludeTraitAlwaysPasses() {
        let element = el(traits: [.button, .selected])
        let matcher = ElementMatcher(excludeTraits: ["madeUpTrait"])
        XCTAssertTrue(element.matches(matcher))
    }

    // MARK: - Edge Cases

    func testVeryLongLabel() {
        let longLabel = String(repeating: "a", count: 10_000)
        let element = el(label: longLabel)
        let matcher = ElementMatcher(label: longLabel)
        XCTAssertTrue(element.matches(matcher))
    }

    func testLabelWithNullCharacter() {
        let element = el(label: "before\0after")
        let matcher = ElementMatcher(label: "before\0after")
        XCTAssertTrue(element.matches(matcher))
        XCTAssertFalse(element.matches(ElementMatcher(label: "before")))
    }

    func testAllFieldsNilOnElement() {
        let element = el()
        XCTAssertTrue(element.matches(ElementMatcher()))
        XCTAssertFalse(element.matches(ElementMatcher(label: "anything")))
        XCTAssertFalse(element.matches(ElementMatcher(identifier: "anything")))
        XCTAssertFalse(element.matches(ElementMatcher(value: "anything")))
    }

    // MARK: - Array Matching: firstMatch

    func testFirstMatchFindsFirst() {
        let elements = [
            el(label: "Alpha", traits: .button),
            el(label: "Beta", traits: .button),
            el(label: "Gamma", traits: .header),
        ]
        let matcher = ElementMatcher(traits: ["button"])
        let result = elements.firstMatch(matcher)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.element.label, "Alpha")
        XCTAssertEqual(result?.index, 0)
    }

    func testFirstMatchFindsSecond() {
        let elements = [
            el(label: "Alpha", traits: .header),
            el(label: "Beta", traits: .button),
            el(label: "Gamma", traits: .button),
        ]
        let matcher = ElementMatcher(traits: ["button"])
        let result = elements.firstMatch(matcher)
        XCTAssertEqual(result?.element.label, "Beta")
        XCTAssertEqual(result?.index, 1)
    }

    func testFirstMatchReturnsNilWhenNoMatch() {
        let elements = [el(label: "Alpha"), el(label: "Beta")]
        let matcher = ElementMatcher(label: "Gamma")
        XCTAssertNil(elements.firstMatch(matcher))
    }

    func testFirstMatchOnEmptyArray() {
        let elements: [AccessibilityElement] = []
        let matcher = ElementMatcher(label: "Anything")
        XCTAssertNil(elements.firstMatch(matcher))
    }

    // MARK: - Array Matching: hasMatch

    func testHasMatchTrue() {
        let elements = [el(label: "Alpha"), el(label: "Beta")]
        XCTAssertTrue(elements.hasMatch(ElementMatcher(label: "Beta")))
    }

    func testHasMatchFalse() {
        let elements = [el(label: "Alpha"), el(label: "Beta")]
        XCTAssertFalse(elements.hasMatch(ElementMatcher(label: "Gamma")))
    }

    func testHasMatchEmptyArray() {
        let elements: [AccessibilityElement] = []
        XCTAssertFalse(elements.hasMatch(ElementMatcher()))
    }

    // MARK: - Hierarchy Matching

    private func group(children: [AccessibilityHierarchy]) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(type: .semanticGroup(label: nil, value: nil, identifier: nil), frame: .zero),
            children: children
        )
    }

    func testHierarchyMatchFindsLeaf() {
        let leaf = AccessibilityHierarchy.element(el(label: "Target", traits: .button), traversalIndex: 3)
        let matcher = ElementMatcher(label: "Target")
        let result = leaf.matches(matcher)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.label, "Target")
        XCTAssertEqual(result?.traversalIndex, 3)
    }

    func testHierarchyMatchSkipsContainer() {
        let container = group(children: [
            .element(el(label: "Child", traits: .button), traversalIndex: 0)
        ])
        let matcher = ElementMatcher(label: "Child")
        let result = container.matches(matcher)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.label, "Child")
    }

    func testHierarchyMatchReturnsNilWhenNoMatch() {
        let leaf = AccessibilityHierarchy.element(el(label: "Other"), traversalIndex: 0)
        let matcher = ElementMatcher(label: "Target")
        XCTAssertNil(leaf.matches(matcher))
    }

    func testHierarchyArrayFirstMatch() {
        let tree: [AccessibilityHierarchy] = [
            .element(el(label: "First", traits: .header), traversalIndex: 0),
            .element(el(label: "Second", traits: .button), traversalIndex: 1),
            .element(el(label: "Third", traits: .button), traversalIndex: 2),
        ]
        let matcher = ElementMatcher(traits: ["button"])
        let result = tree.firstMatch(matcher)
        XCTAssertEqual(result?.label, "Second")
        XCTAssertEqual(result?.traversalIndex, 1)
    }

    func testHierarchyArrayAllMatches() {
        let tree: [AccessibilityHierarchy] = [
            .element(el(label: "A", traits: .button), traversalIndex: 0),
            .element(el(label: "B", traits: .header), traversalIndex: 1),
            .element(el(label: "C", traits: .button), traversalIndex: 2),
        ]
        let results = tree.allMatches(ElementMatcher(traits: ["button"]))
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].label, "A")
        XCTAssertEqual(results[1].label, "C")
    }

    func testHierarchyNestedContainerSearch() {
        let tree: [AccessibilityHierarchy] = [
            group(children: [
                group(children: [
                    .element(el(label: "Deep Target", identifier: "deep"), traversalIndex: 5)
                ])
            ])
        ]
        let result = tree.firstMatch(ElementMatcher(identifier: "deep"))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.label, "Deep Target")
        XCTAssertEqual(result?.traversalIndex, 5)
    }

    func testHierarchyContainerLabelDoesNotMatch() {
        // Container has label "Settings" but only leaf elements should match
        let tree: [AccessibilityHierarchy] = [
            .container(
                AccessibilityContainer(type: .semanticGroup(label: "Settings", value: nil, identifier: nil), frame: .zero),
                children: [
                    .element(el(label: "Volume"), traversalIndex: 0)
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
        let a = el(label: "Save", value: "draft", identifier: "btn", traits: .button)
        let b = el(label: "Save", value: "draft", identifier: "btn", traits: .button)
        XCTAssertEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyDiffersOnLabel() {
        let a = el(label: "Save")
        let b = el(label: "Cancel")
        XCTAssertNotEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyDiffersOnIdentifier() {
        let a = el(label: "Save", identifier: "a")
        let b = el(label: "Save", identifier: "b")
        XCTAssertNotEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyDiffersOnValue() {
        let a = el(label: "Slider", value: "50%")
        let b = el(label: "Slider", value: "75%")
        XCTAssertNotEqual(a.stableKey, b.stableKey)
    }

    func testStableKeyDiffersOnTraits() {
        let a = el(label: "Save", traits: .button)
        let b = el(label: "Save", traits: [.button, .selected])
        XCTAssertNotEqual(a.stableKey, b.stableKey)
    }

    func testStableKeySetDeduplicates() {
        let elements = [
            el(label: "Save", traits: .button),
            el(label: "Save", traits: .button),
            el(label: "Cancel", traits: .button),
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

    // MARK: - Absent Flag (Semantic Only)

    func testAbsentDoesNotAffectMatching() {
        let element = el(label: "Save", traits: .button)
        let matcher = ElementMatcher(label: "Save", absent: true)
        // absent is a caller-level concern — propertiesMatch still returns true
        XCTAssertTrue(element.matches(matcher))
    }

    func testIsAbsentConvenience() {
        XCTAssertFalse(ElementMatcher().isAbsent)
        XCTAssertFalse(ElementMatcher(absent: nil).isAbsent)
        XCTAssertFalse(ElementMatcher(absent: false).isAbsent)
        XCTAssertTrue(ElementMatcher(absent: true).isAbsent)
    }

    // MARK: - MatchScope: Hierarchy

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

    func testScopeElementsSkipsContainers() {
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Nav", children: [
                .element(el(label: "Item"), traversalIndex: 0)
            ])
        ]
        // Default scope (.elements) should not match the container
        let result = tree.firstMatch(ElementMatcher(label: "Nav"))
        XCTAssertNil(result)
    }

    func testScopeContainersMatchesContainer() {
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Nav", children: [
                .element(el(label: "Item"), traversalIndex: 0)
            ])
        ]
        let matcher = ElementMatcher(label: "Nav", scope: .containers)
        let result = tree.firstMatch(matcher)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.label, "Nav")
        XCTAssertNil(result?.element)
        XCTAssertNotNil(result?.container)
    }

    func testScopeContainersSkipsLeaves() {
        let tree: [AccessibilityHierarchy] = [
            .element(el(label: "Leaf"), traversalIndex: 0)
        ]
        let matcher = ElementMatcher(label: "Leaf", scope: .containers)
        XCTAssertNil(tree.firstMatch(matcher))
    }

    func testScopeBothMatchesContainerAndLeaf() {
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Section", children: [
                .element(el(label: "Item"), traversalIndex: 0)
            ])
        ]
        let results = tree.allMatches(
            ElementMatcher(scope: .both)
        )
        // Should find both the container ("Section") and the leaf ("Item")
        XCTAssertEqual(results.count, 2)
    }

    func testScopeBothMatchesLeafByLabel() {
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Section", children: [
                .element(el(label: "Target"), traversalIndex: 0)
            ])
        ]
        let matcher = ElementMatcher(label: "Target", scope: .both)
        let result = tree.firstMatch(matcher)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.label, "Target")
        XCTAssertNotNil(result?.element)
    }

    func testScopeContainersWithTraitsFails() {
        // Containers have no traits — a matcher with scope=containers and traits should never match
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Nav", children: [
                .element(el(label: "Item", traits: .button), traversalIndex: 0)
            ])
        ]
        let matcher = ElementMatcher(label: "Nav", traits: ["button"], scope: .containers)
        XCTAssertNil(tree.firstMatch(matcher))
    }

    func testScopeContainersMatchesByIdentifier() {
        let tree: [AccessibilityHierarchy] = [
            .container(
                AccessibilityContainer(
                    type: .semanticGroup(label: nil, value: nil, identifier: "nav.bar"),
                    frame: .zero
                ),
                children: [
                    .element(el(label: "Item"), traversalIndex: 0)
                ]
            )
        ]
        let matcher = ElementMatcher(identifier: "nav.bar", scope: .containers)
        let result = tree.firstMatch(matcher)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.container)
    }

    func testScopeContainersMatchesByValue() {
        let tree: [AccessibilityHierarchy] = [
            .container(
                AccessibilityContainer(
                    type: .semanticGroup(label: nil, value: "3 items", identifier: nil),
                    frame: .zero
                ),
                children: []
            )
        ]
        let matcher = ElementMatcher(value: "3 items", scope: .containers)
        let result = tree.firstMatch(matcher)
        XCTAssertNotNil(result)
    }

    func testScopeContainersNonSemanticGroupNeverMatches() {
        // .list containers have no label/value/identifier — can only match empty matcher
        let tree: [AccessibilityHierarchy] = [
            .container(
                AccessibilityContainer(type: .list, frame: .zero),
                children: [
                    .element(el(label: "Item"), traversalIndex: 0)
                ]
            )
        ]
        let matcher = ElementMatcher(label: "anything", scope: .containers)
        XCTAssertNil(tree.firstMatch(matcher))
    }

    func testScopeContainersStillRecursesIntoChildren() {
        // Even when scope is .containers, children should still be searched
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Outer", children: [
                labeledGroup(label: "Inner", children: [
                    .element(el(label: "Leaf"), traversalIndex: 0)
                ])
            ])
        ]
        let matcher = ElementMatcher(label: "Inner", scope: .containers)
        let result = tree.firstMatch(matcher)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.label, "Inner")
    }

    func testScopeDefaultMatchesExistingBehavior() {
        // Nil scope should behave exactly like .elements
        let tree: [AccessibilityHierarchy] = [
            labeledGroup(label: "Section", children: [
                .element(el(label: "Target"), traversalIndex: 0)
            ])
        ]
        let withNil = tree.firstMatch(ElementMatcher(label: "Target"))
        let withExplicit = tree.firstMatch(
            ElementMatcher(label: "Target", scope: .elements)
        )
        XCTAssertNotNil(withNil)
        XCTAssertNotNil(withExplicit)
        XCTAssertEqual(withNil?.label, withExplicit?.label)

        // Neither should match the container
        XCTAssertNil(tree.firstMatch(ElementMatcher(label: "Section")))
        XCTAssertNil(tree.firstMatch(
            ElementMatcher(label: "Section", scope: .elements)
        ))
    }

    // MARK: - AccessibilityContainer Matching

    func testContainerMatchesLabel() {
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Settings", value: nil, identifier: nil), frame: .zero
        )
        XCTAssertTrue(container.matches(ElementMatcher(label: "Settings")))
        XCTAssertFalse(container.matches(ElementMatcher(label: "Other")))
    }

    func testContainerMatchesIdentifier() {
        let container = AccessibilityContainer(
            type: .semanticGroup(label: nil, value: nil, identifier: "nav"), frame: .zero
        )
        XCTAssertTrue(container.matches(ElementMatcher(identifier: "nav")))
        XCTAssertFalse(container.matches(ElementMatcher(identifier: "other")))
    }

    func testContainerMatchesValue() {
        let container = AccessibilityContainer(
            type: .semanticGroup(label: nil, value: "5 items", identifier: nil), frame: .zero
        )
        XCTAssertTrue(container.matches(ElementMatcher(value: "5 items")))
        XCTAssertFalse(container.matches(ElementMatcher(value: "3 items")))
    }

    func testContainerWithTraitsAlwaysFails() {
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Nav", value: nil, identifier: nil), frame: .zero
        )
        XCTAssertFalse(container.matches(ElementMatcher(label: "Nav", traits: ["button"])))
    }

    func testContainerEmptyMatcherMatchesAny() {
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Nav", value: nil, identifier: nil), frame: .zero
        )
        XCTAssertTrue(container.matches(ElementMatcher()))
    }

    func testContainerListTypeHasNoProperties() {
        let container = AccessibilityContainer(type: .list, frame: .zero)
        // Empty matcher matches anything
        XCTAssertTrue(container.matches(ElementMatcher()))
        // Any property requirement fails
        XCTAssertFalse(container.matches(ElementMatcher(label: "anything")))
    }
}

#endif

#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheBurglarApplyTests: XCTestCase {

    private var stash: TheStash!

    override func setUp() async throws {
        try await super.setUp()
        stash = TheStash(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        stash = nil
        try await super.tearDown()
    }

    // MARK: - apply() populates registry

    func testApplyPopulatesRegistryElements() {
        let elementA = makeElement(label: "Save", traits: .button)
        let elementB = makeElement(label: "Cancel", traits: .button)
        let hierarchy: [AccessibilityHierarchy] = [
            .element(elementA, traversalIndex: 0),
            .element(elementB, traversalIndex: 1),
        ]
        let result = TheBurglar.ParseResult(
            elements: [elementA, elementB],
            hierarchy: hierarchy,
            objects: [:],
            scrollViews: [:]
        )

        let heistIds = stash.burglar.apply(result, to: stash)

        XCTAssertEqual(heistIds.count, 2)
        XCTAssertEqual(stash.registry.elements.count, 2,
                       "Registry should have one entry per element")
        for heistId in heistIds {
            XCTAssertNotNil(stash.registry.elements[heistId],
                           "Each heistId should map to a registry entry")
        }
    }

    func testApplyRebuildsViewportIds() {
        let element = makeElement(label: "OK", traits: .button)
        let hierarchy: [AccessibilityHierarchy] = [
            .element(element, traversalIndex: 0),
        ]
        let result = TheBurglar.ParseResult(
            elements: [element],
            hierarchy: hierarchy,
            objects: [:],
            scrollViews: [:]
        )

        let heistIds = stash.burglar.apply(result, to: stash)

        XCTAssertEqual(stash.registry.viewportIds, Set(heistIds),
                       "viewportIds should be the set of all heistIds from the apply")
    }

    func testApplyRebuildsReverseIndex() {
        let element = makeElement(label: "Title", traits: .header)
        let hierarchy: [AccessibilityHierarchy] = [
            .element(element, traversalIndex: 0),
        ]
        let result = TheBurglar.ParseResult(
            elements: [element],
            hierarchy: hierarchy,
            objects: [:],
            scrollViews: [:]
        )

        stash.burglar.apply(result, to: stash)

        let heistId = stash.registry.reverseIndex[element]
        XCTAssertNotNil(heistId, "reverseIndex should map element → heistId")
        XCTAssertNotNil(stash.registry.elements[heistId ?? ""],
                       "Reverse-indexed heistId should exist in registry")
    }

    // MARK: - apply() sets currentHierarchy

    func testApplySetsCurrentHierarchy() {
        let element = makeElement(label: "Item")
        let hierarchy: [AccessibilityHierarchy] = [
            .element(element, traversalIndex: 0),
        ]
        let result = TheBurglar.ParseResult(
            elements: [element],
            hierarchy: hierarchy,
            objects: [:],
            scrollViews: [:]
        )

        stash.burglar.apply(result, to: stash)

        XCTAssertEqual(stash.currentHierarchy.count, 1,
                       "apply should set currentHierarchy from the parse result")
    }

    // MARK: - Screen name caching

    func testApplyCachesScreenNameFromFirstHeader() {
        let header = makeElement(label: "Settings", traits: .header)
        let button = makeElement(label: "Save", traits: .button)
        let hierarchy: [AccessibilityHierarchy] = [
            .element(header, traversalIndex: 0),
            .element(button, traversalIndex: 1),
        ]
        let result = TheBurglar.ParseResult(
            elements: [header, button],
            hierarchy: hierarchy,
            objects: [:],
            scrollViews: [:]
        )

        stash.burglar.apply(result, to: stash)

        XCTAssertEqual(stash.lastScreenName, "Settings",
                       "Screen name should be the first header's label")
    }

    func testApplySetsScreenIdAsSlugifiedName() {
        let header = makeElement(label: "My Profile", traits: .header)
        let hierarchy: [AccessibilityHierarchy] = [
            .element(header, traversalIndex: 0),
        ]
        let result = TheBurglar.ParseResult(
            elements: [header],
            hierarchy: hierarchy,
            objects: [:],
            scrollViews: [:]
        )

        stash.burglar.apply(result, to: stash)

        XCTAssertNotNil(stash.lastScreenId)
        XCTAssertEqual(stash.lastScreenId, TheStash.IdAssignment.slugify("My Profile"),
                       "screenId should be the slugified screen name")
    }

    func testApplyScreenNameNilWhenNoHeaders() {
        let button = makeElement(label: "OK", traits: .button)
        let hierarchy: [AccessibilityHierarchy] = [
            .element(button, traversalIndex: 0),
        ]
        let result = TheBurglar.ParseResult(
            elements: [button],
            hierarchy: hierarchy,
            objects: [:],
            scrollViews: [:]
        )

        stash.burglar.apply(result, to: stash)

        XCTAssertNil(stash.lastScreenName,
                     "Screen name should be nil when no header elements exist")
        XCTAssertNil(stash.lastScreenId)
    }

    func testApplyScreenNameIgnoresHeaderWithNilLabel() {
        let headerNoLabel = makeElement(label: nil, traits: .header)
        let button = makeElement(label: "OK", traits: .button)
        let hierarchy: [AccessibilityHierarchy] = [
            .element(headerNoLabel, traversalIndex: 0),
            .element(button, traversalIndex: 1),
        ]
        let result = TheBurglar.ParseResult(
            elements: [headerNoLabel, button],
            hierarchy: hierarchy,
            objects: [:],
            scrollViews: [:]
        )

        stash.burglar.apply(result, to: stash)

        XCTAssertNil(stash.lastScreenName,
                     "Header with nil label should not set screen name")
    }

    // MARK: - First responder detection

    func testApplyDetectsFirstResponder() {
        let textField = UITextField()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.addSubview(textField)
        window.makeKeyAndVisible()
        textField.becomeFirstResponder()

        let element = makeElement(label: "Email", traits: .none)
        let hierarchy: [AccessibilityHierarchy] = [
            .element(element, traversalIndex: 0),
        ]
        let result = TheBurglar.ParseResult(
            elements: [element],
            hierarchy: hierarchy,
            objects: [element: textField],
            scrollViews: [:]
        )

        stash.burglar.apply(result, to: stash)

        XCTAssertNotNil(stash.registry.firstResponderHeistId,
                        "Should detect the text field as first responder")

        textField.resignFirstResponder()
        window.isHidden = true
    }

    func testApplyFirstResponderNilWhenNoneActive() {
        let element = makeElement(label: "Label")
        let label = UILabel()
        let hierarchy: [AccessibilityHierarchy] = [
            .element(element, traversalIndex: 0),
        ]
        let result = TheBurglar.ParseResult(
            elements: [element],
            hierarchy: hierarchy,
            objects: [element: label],
            scrollViews: [:]
        )

        stash.burglar.apply(result, to: stash)

        XCTAssertNil(stash.registry.firstResponderHeistId,
                     "Should be nil when no element is first responder")
    }

    // MARK: - apply() updates existing entries

    func testApplyUpdatesExistingRegistryEntry() {
        // First apply: create the initial entry with a content-space origin
        let elementV1 = makeElement(label: "Count", value: "0")
        let hierarchyV1: [AccessibilityHierarchy] = [
            .element(elementV1, traversalIndex: 0),
        ]
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)
        let resultV1 = TheBurglar.ParseResult(
            elements: [elementV1],
            hierarchy: hierarchyV1,
            objects: [:],
            scrollViews: [:]
        )
        let heistIdsV1 = stash.burglar.apply(resultV1, to: stash)
        let heistId = heistIdsV1.first
        guard let heistId else {
            XCTFail("First apply should produce a heistId")
            return
        }

        // Second apply: same label, different value — entry should be updated
        let elementV2 = makeElement(label: "Count", value: "5")
        let hierarchyV2: [AccessibilityHierarchy] = [
            .element(elementV2, traversalIndex: 0),
        ]
        let resultV2 = TheBurglar.ParseResult(
            elements: [elementV2],
            hierarchy: hierarchyV2,
            objects: [:],
            scrollViews: [:]
        )

        stash.burglar.apply(resultV2, to: stash)

        let entry = stash.registry.elements[heistId]
        XCTAssertNotNil(entry, "Entry should still exist under the same heistId")
        XCTAssertEqual(entry?.element.value, "5",
                       "Element value should be updated to new value")
    }

    // MARK: - HeistId assignment via apply

    func testHeistIdsAreAssignedDeterministically() {
        let button = makeElement(label: "Submit", traits: .button)
        let hierarchy: [AccessibilityHierarchy] = [
            .element(button, traversalIndex: 0),
        ]
        let result = TheBurglar.ParseResult(
            elements: [button],
            hierarchy: hierarchy,
            objects: [:],
            scrollViews: [:]
        )

        let heistIds1 = stash.burglar.apply(result, to: stash)
        stash.registry = TheStash.ElementRegistry()
        let heistIds2 = stash.burglar.apply(result, to: stash)

        XCTAssertEqual(heistIds1, heistIds2,
                       "Same elements should produce same heistIds")
    }

    func testDuplicateLabelsGetDisambiguatedHeistIds() {
        let buttonA = makeElement(label: "Option", traits: .button)
        let buttonB = makeElement(label: "Option", traits: .button)
        let hierarchy: [AccessibilityHierarchy] = [
            .element(buttonA, traversalIndex: 0),
            .element(buttonB, traversalIndex: 1),
        ]
        let result = TheBurglar.ParseResult(
            elements: [buttonA, buttonB],
            hierarchy: hierarchy,
            objects: [:],
            scrollViews: [:]
        )

        let heistIds = stash.burglar.apply(result, to: stash)

        XCTAssertEqual(heistIds.count, 2)
        XCTAssertNotEqual(heistIds[0], heistIds[1],
                          "Duplicate labels should produce disambiguated heistIds")
    }

    // MARK: - isTopologyChanged (via burglar)

    func testTopologyChangedOnBackButtonAppearing() {
        let before = [makeElement(label: "Home", traits: .header)]
        let backButtonTrait = UIAccessibilityTraits(rawValue: 1 << 27)
        let after = [
            makeElement(label: "Home", traits: .header),
            makeElement(label: "Back", traits: backButtonTrait),
        ]
        XCTAssertTrue(stash.burglar.isTopologyChanged(
            before: before, after: after, beforeHierarchy: [], afterHierarchy: []
        ))
    }

    func testTopologyUnchangedWhenSameHeaders() {
        let elements = [makeElement(label: "Settings", traits: .header)]
        XCTAssertFalse(stash.burglar.isTopologyChanged(
            before: elements, after: elements, beforeHierarchy: [], afterHierarchy: []
        ))
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        traits: UIAccessibilityTraits = .none
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
            label: label,
            value: value,
            traits: traits,
            identifier: nil,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(.zero),
            activationPoint: .zero,
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: false
        )
    }
}

#endif

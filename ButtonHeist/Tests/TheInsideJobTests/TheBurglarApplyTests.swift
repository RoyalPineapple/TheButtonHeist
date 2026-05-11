#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Tests for `TheBurglar.buildScreen(from:)` — the lifted body of the old
/// `apply(_:)` pipeline. Validates that a `ParseResult` is converted into a
/// `Screen` value with the same semantics: heistId assignment, content-space
/// origins, first-responder detection, and screen-name derivation.
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

    // MARK: - buildScreen populates elements

    func testBuildScreenPopulatesElements() {
        let elementA = makeElement(label: "Save", traits: .button)
        let elementB = makeElement(label: "Cancel", traits: .button)
        let result = TheBurglar.ParseResult(
            elements: [elementA, elementB],
            hierarchy: [
                .element(elementA, traversalIndex: 0),
                .element(elementB, traversalIndex: 1),
            ],
            objects: [:],
            scrollViews: [:]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.elements.count, 2, "Screen should have one entry per parsed element")
        for heistId in screen.elements.keys {
            XCTAssertNotNil(screen.findElement(heistId: heistId),
                            "Each heistId should map to an entry")
        }
    }

    func testBuildScreenPopulatesHeistIdByElement() {
        let element = makeElement(label: "OK", traits: .button)
        let result = TheBurglar.ParseResult(
            elements: [element],
            hierarchy: [.element(element, traversalIndex: 0)],
            objects: [:],
            scrollViews: [:]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.heistIdByElement[element], "ok_button")
    }

    func testBuildScreenSetsHierarchy() {
        let element = makeElement(label: "Item")
        let hierarchy: [AccessibilityHierarchy] = [.element(element, traversalIndex: 0)]
        let result = TheBurglar.ParseResult(
            elements: [element], hierarchy: hierarchy, objects: [:], scrollViews: [:]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.hierarchy.count, 1)
    }

    // MARK: - Screen name derivation

    func testScreenNameFromFirstHeader() {
        let header = makeElement(label: "Settings", traits: .header)
        let button = makeElement(label: "Save", traits: .button)
        let result = TheBurglar.ParseResult(
            elements: [header, button],
            hierarchy: [
                .element(header, traversalIndex: 0),
                .element(button, traversalIndex: 1),
            ],
            objects: [:], scrollViews: [:]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.name, "Settings")
    }

    func testScreenIdIsSlugifiedName() {
        let header = makeElement(label: "My Profile", traits: .header)
        let result = TheBurglar.ParseResult(
            elements: [header],
            hierarchy: [.element(header, traversalIndex: 0)],
            objects: [:], scrollViews: [:]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.id, TheStash.IdAssignment.slugify("My Profile"))
    }

    func testScreenNameNilWhenNoHeaders() {
        let button = makeElement(label: "OK", traits: .button)
        let result = TheBurglar.ParseResult(
            elements: [button],
            hierarchy: [.element(button, traversalIndex: 0)],
            objects: [:], scrollViews: [:]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertNil(screen.name)
        XCTAssertNil(screen.id)
    }

    func testScreenNameIgnoresHeaderWithNilLabel() {
        let headerNoLabel = makeElement(label: nil, traits: .header)
        let button = makeElement(label: "OK", traits: .button)
        let result = TheBurglar.ParseResult(
            elements: [headerNoLabel, button],
            hierarchy: [
                .element(headerNoLabel, traversalIndex: 0),
                .element(button, traversalIndex: 1),
            ],
            objects: [:], scrollViews: [:]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertNil(screen.name)
    }

    // MARK: - First responder detection

    func testDetectsFirstResponder() async {
        let textField = UITextField()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.addSubview(textField)
        window.makeKeyAndVisible()
        textField.becomeFirstResponder()

        let element = makeElement(label: "Email", traits: .none)
        let result = TheBurglar.ParseResult(
            elements: [element],
            hierarchy: [.element(element, traversalIndex: 0)],
            objects: [element: textField],
            scrollViews: [:]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertNotNil(screen.firstResponderHeistId)

        textField.resignFirstResponder()
        window.isHidden = true
        await KeyboardWindowTestHelpers.waitForKeyboardWindowsToRetire()
    }

    func testFirstResponderNilWhenNoneActive() {
        let element = makeElement(label: "Label")
        let label = UILabel()
        let result = TheBurglar.ParseResult(
            elements: [element],
            hierarchy: [.element(element, traversalIndex: 0)],
            objects: [element: label],
            scrollViews: [:]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertNil(screen.firstResponderHeistId)
    }

    // MARK: - HeistId determinism

    func testHeistIdsAreAssignedDeterministically() {
        let button = makeElement(label: "Submit", traits: .button)
        let result = TheBurglar.ParseResult(
            elements: [button],
            hierarchy: [.element(button, traversalIndex: 0)],
            objects: [:], scrollViews: [:]
        )

        let first = TheBurglar.buildScreen(from: result)
        let second = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(Set(first.elements.keys), Set(second.elements.keys),
                       "Same elements should produce same heistIds")
    }

    func testDuplicateLabelsGetDisambiguatedHeistIds() {
        let buttonA = makeElement(
            label: "Option", traits: .button,
            frame: CGRect(x: 0, y: 0, width: 100, height: 44)
        )
        let buttonB = makeElement(
            label: "Option", traits: .button,
            frame: CGRect(x: 0, y: 60, width: 100, height: 44)
        )
        let result = TheBurglar.ParseResult(
            elements: [buttonA, buttonB],
            hierarchy: [
                .element(buttonA, traversalIndex: 0),
                .element(buttonB, traversalIndex: 1),
            ],
            objects: [:], scrollViews: [:]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.elements.count, 2)
        XCTAssertEqual(screen.elements.count, 2,
                       "Duplicate labels should produce two distinct entries")
    }

    // MARK: - Content space origin

    func testPropagatesContentSpaceOriginForScrollableContainerChild() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 100, width: 320, height: 500))
        scrollView.contentSize = CGSize(width: 320, height: 2000)

        let scrollableContainer = AccessibilityContainer(
            type: .scrollable(contentSize: scrollView.contentSize),
            frame: scrollView.frame
        )
        let childFrame = CGRect(x: 10, y: 150, width: 50, height: 30)
        let child = makeElement(label: "Cell", traits: .button, frame: childFrame)

        let result = TheBurglar.ParseResult(
            elements: [child],
            hierarchy: [.container(scrollableContainer, children: [.element(child, traversalIndex: 0)])],
            objects: [:],
            scrollViews: [scrollableContainer: scrollView]
        )

        let screen = TheBurglar.buildScreen(from: result)
        guard let heistId = screen.elements.keys.first else {
            XCTFail("Expected one heistId")
            return
        }

        XCTAssertNotNil(screen.findElement(heistId: heistId)?.contentSpaceOrigin,
                        "Element inside a scrollable container should receive a contentSpaceOrigin")
    }

    func testLeavesContentSpaceOriginNilOutsideScrollableContainer() {
        let element = makeElement(label: "Plain",
                                  frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let result = TheBurglar.ParseResult(
            elements: [element],
            hierarchy: [.element(element, traversalIndex: 0)],
            objects: [:], scrollViews: [:]
        )

        let screen = TheBurglar.buildScreen(from: result)
        guard let heistId = screen.elements.keys.first else {
            XCTFail("Expected one heistId")
            return
        }

        XCTAssertNil(screen.findElement(heistId: heistId)?.contentSpaceOrigin,
                     "Element with no enclosing scroll view should have nil contentSpaceOrigin")
    }

    // MARK: - isTopologyChanged (via stash)

    func testTopologyChangedOnBackButtonAppearing() {
        let before = [makeElement(label: "Home", traits: .header)]
        let backButtonTrait = UIAccessibilityTraits(rawValue: 1 << 27)
        let after = [
            makeElement(label: "Home", traits: .header),
            makeElement(label: "Back", traits: backButtonTrait),
        ]
        XCTAssertTrue(stash.isTopologyChanged(
            before: before, after: after, beforeHierarchy: [], afterHierarchy: []
        ))
    }

    func testTopologyUnchangedWhenSameHeaders() {
        let elements = [makeElement(label: "Settings", traits: .header)]
        XCTAssertFalse(stash.isTopologyChanged(
            before: elements, after: elements, beforeHierarchy: [], afterHierarchy: []
        ))
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        traits: UIAccessibilityTraits = .none,
        frame: CGRect = .zero
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
            label: label,
            value: value,
            traits: traits,
            identifier: nil,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(frame),
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

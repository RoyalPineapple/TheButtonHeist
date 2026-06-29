#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Tests for `TheBurglar.buildScreen(from:)`. Validates that a `ParseResult`
/// is converted into a `Screen` value with the current semantics: heistId
/// assignment, scroll membership, first-responder detection, and
/// screen-name derivation.
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
            hierarchy: [
                .element(elementA, traversalIndex: 0),
                .element(elementB, traversalIndex: 1),
            ],
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.semantic.elements.count, 2, "Screen should have one entry per parsed element")
        for heistId in screen.semantic.elements.keys {
            XCTAssertNotNil(screen.findElement(heistId: heistId),
                            "Each heistId should map to an entry")
        }
    }

    func testBuildScreenPopulatesHeistIdsByPath() {
        let element = makeElement(label: "OK", traits: .button)
        let result = TheBurglar.ParseResult(
            hierarchy: [.element(element, traversalIndex: 0)],
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.liveCapture.heistId(forPath: TreePath([0])), "ok_button")
    }

    func testBuildScreenKeepsDistinctEntriesForValueEqualElements() {
        let first = makeElement(label: "Item", traits: .button)
        let second = makeElement(label: "Item", traits: .button)
        let result = TheBurglar.ParseResult(
            hierarchy: [
                .element(first, traversalIndex: 0),
                .element(second, traversalIndex: 1),
            ],
        )

        let screen = TheBurglar.buildScreen(from: result)
        let interface = TheStash.WireConversion.toInterface(from: screen)

        // Value-equal elements still get distinct synthesized heistIds because
        // live identity is keyed by tree path, not element value equality.
        XCTAssertEqual(screen.semantic.elements.count, 2)
        XCTAssertEqual(Set(screen.semantic.elements.keys), ["item_button_1", "item_button_2"])
        XCTAssertEqual(interface.annotations.elements.map(\.path), [TreePath([0]), TreePath([1])])
    }

    func testBuildScreenSetsHierarchy() {
        let element = makeElement(label: "Item")
        let hierarchy: [AccessibilityHierarchy] = [.element(element, traversalIndex: 0)]
        let result = TheBurglar.ParseResult(
            hierarchy: hierarchy
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.liveCapture.hierarchy.count, 1)
    }

    // MARK: - Screen name derivation

    func testScreenNameFromFirstHeader() {
        let header = makeElement(label: "Settings", traits: .header)
        let button = makeElement(label: "Save", traits: .button)
        let result = TheBurglar.ParseResult(
            hierarchy: [
                .element(header, traversalIndex: 0),
                .element(button, traversalIndex: 1),
            ]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.name, "Settings")
    }

    func testScreenIdIsSlugifiedName() {
        let header = makeElement(label: "My Profile", traits: .header)
        let result = TheBurglar.ParseResult(
            hierarchy: [.element(header, traversalIndex: 0)]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.id, TheScore.slugify("My Profile"))
    }

    func testScreenNameNilWhenNoHeaders() {
        let button = makeElement(label: "OK", traits: .button)
        let result = TheBurglar.ParseResult(
            hierarchy: [.element(button, traversalIndex: 0)]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertNil(screen.name)
        XCTAssertNil(screen.id)
    }

    func testScreenNameIgnoresHeaderWithNilLabel() {
        let headerNoLabel = makeElement(label: nil, traits: .header)
        let button = makeElement(label: "OK", traits: .button)
        let result = TheBurglar.ParseResult(
            hierarchy: [
                .element(headerNoLabel, traversalIndex: 0),
                .element(button, traversalIndex: 1),
            ]
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
            hierarchy: [.element(element, traversalIndex: 0)],
            objectsByPath: [TreePath([0]): textField],
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertNotNil(screen.liveCapture.firstResponderHeistId)

        textField.resignFirstResponder()
        window.isHidden = true
        await KeyboardWindowTestHelpers.waitForKeyboardWindowsToRetire()
    }

    func testFirstResponderNilWhenNoneActive() {
        let element = makeElement(label: "Label")
        let label = UILabel()
        let result = TheBurglar.ParseResult(
            hierarchy: [.element(element, traversalIndex: 0)],
            objectsByPath: [TreePath([0]): label],
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertNil(screen.liveCapture.firstResponderHeistId)
    }

    // MARK: - HeistId determinism

    func testHeistIdsAreAssignedDeterministically() {
        let button = makeElement(label: "Submit", traits: .button)
        let result = TheBurglar.ParseResult(
            hierarchy: [.element(button, traversalIndex: 0)]
        )

        let first = TheBurglar.buildScreen(from: result)
        let second = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(Set(first.semantic.elements.keys), Set(second.semantic.elements.keys),
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
            hierarchy: [
                .element(buttonA, traversalIndex: 0),
                .element(buttonB, traversalIndex: 1),
            ]
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.semantic.elements.count, 2)
        XCTAssertEqual(screen.semantic.elements.count, 2,
                       "Duplicate labels should produce two distinct entries")
    }

    func testElementOrderDerivesFromHierarchyTraversalIndex() {
        let first = makeElement(label: "Row", traits: .button,
                                frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        let second = makeElement(label: "Row", traits: .button,
                                 frame: CGRect(x: 0, y: 50, width: 100, height: 44))
        let result = TheBurglar.ParseResult(
            hierarchy: [
                .element(second, traversalIndex: 1),
                .element(first, traversalIndex: 0),
            ],
        )

        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.liveCapture.heistId(forPath: TreePath([1])), "row_button_1")
        XCTAssertEqual(screen.liveCapture.heistId(forPath: TreePath([0])), "row_button_2")
    }

    func testBuildScreenRestoresScreenCoordinateGeometryFromParseRootOffset() throws {
        let parseRootOffset = CGPoint(x: 180, y: 24)
        let rootLocalFrame = CGRect(x: 64, y: 372, width: 155, height: 72)
        let screenFrame = rootLocalFrame.offsetBy(dx: parseRootOffset.x, dy: parseRootOffset.y)
        let rootLocalActivationPoint = CGPoint(x: 141.5, y: 408)
        let screenActivationPoint = CGPoint(
            x: rootLocalActivationPoint.x + parseRootOffset.x,
            y: rootLocalActivationPoint.y + parseRootOffset.y
        )
        let parsedElement = makeElement(
            label: "Confirm",
            traits: .button,
            frame: rootLocalFrame,
            activationPoint: rootLocalActivationPoint
        )

        let result = TheBurglar.ParseResult(
            hierarchy: [.element(parsedElement, traversalIndex: 0)],
            screenCoordinateOffsetsByPath: [TreePath([0]): parseRootOffset]
        )

        let screen = TheBurglar.buildScreen(from: result)
        let element = try XCTUnwrap(screen.liveCapture.hierarchy.sortedElements.first)
        let projected = try XCTUnwrap(TheStash.WireConversion.toInterface(from: screen).projectedElements.first)

        XCTAssertEqual(element.shape.frame, screenFrame)
        XCTAssertEqual(element.bhResolvedActivationPoint, screenActivationPoint)
        XCTAssertEqual(projected.frameX, screenFrame.origin.x)
        XCTAssertEqual(projected.frameY, screenFrame.origin.y)
        XCTAssertEqual(projected.frameWidth, screenFrame.size.width)
        XCTAssertEqual(projected.frameHeight, screenFrame.size.height)
        XCTAssertEqual(projected.activationPointX, screenActivationPoint.x)
        XCTAssertEqual(projected.activationPointY, screenActivationPoint.y)
    }

    func testBuildScreenRestoresPathGeometryFromParseRootOffset() throws {
        let parseRootOffset = CGPoint(x: 20, y: 30)
        let pathElement = AccessibilityElement(
            description: "Path Button",
            label: "Path Button",
            value: nil,
            traits: .button,
            identifier: nil,
            hint: nil,
            userInputLabels: nil,
            shape: .path([
                .move(to: AccessibilityPoint(x: 10, y: 10)),
                .line(to: AccessibilityPoint(x: 50, y: 10)),
                .quadCurve(
                    to: AccessibilityPoint(x: 50, y: 50),
                    control: AccessibilityPoint(x: 60, y: 25)
                ),
            ]),
            activationPoint: AccessibilityPoint(x: 30, y: 30),
            usesDefaultActivationPoint: false,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
        )
        let result = TheBurglar.ParseResult(
            hierarchy: [.element(pathElement, traversalIndex: 0)],
            screenCoordinateOffsetsByPath: [TreePath([0]): parseRootOffset]
        )

        let screen = TheBurglar.buildScreen(from: result)
        let translated = try XCTUnwrap(screen.liveCapture.hierarchy.sortedElements.first)

        guard case .path(let elements) = translated.shape else {
            return XCTFail("Expected translated path")
        }
        XCTAssertEqual(elements.first, .move(to: AccessibilityPoint(x: 30, y: 40)))
        XCTAssertEqual(translated.bhResolvedActivationPoint, CGPoint(x: 50, y: 60))
    }

    // MARK: - Scroll membership

    func testPropagatesScrollMembershipForScrollableContainerChild() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 100, width: 320, height: 500))
        scrollView.contentSize = CGSize(width: 320, height: 2000)

        let scrollableContainer = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(scrollView.contentSize)),
            frame: AccessibilityRect(scrollView.frame)
        )
        let childFrame = CGRect(x: 10, y: 150, width: 50, height: 30)
        let child = makeElement(label: "Cell", traits: .button, frame: childFrame)

        let result = TheBurglar.ParseResult(
            hierarchy: [.container(scrollableContainer, children: [.element(child, traversalIndex: 0)])],
            scrollViewsByPath: [TreePath([0]): scrollView]
        )

        let screen = TheBurglar.buildScreen(from: result)
        guard let heistId = screen.semantic.elements.keys.first else {
            XCTFail("Expected one heistId")
            return
        }

        XCTAssertEqual(screen.findElement(heistId: heistId)?.scrollMembership?.containerPath, TreePath([0]))
    }

    func testLeavesScrollMembershipNilOutsideScrollableContainer() {
        let element = makeElement(label: "Plain",
                                  frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let result = TheBurglar.ParseResult(
            hierarchy: [.element(element, traversalIndex: 0)]
        )

        let screen = TheBurglar.buildScreen(from: result)
        guard let heistId = screen.semantic.elements.keys.first else {
            XCTFail("Expected one heistId")
            return
        }

        XCTAssertNil(screen.findElement(heistId: heistId)?.scrollMembership)
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        traits: UIAccessibilityTraits = .none,
        frame: CGRect = .zero,
        activationPoint: CGPoint? = nil
    ) -> AccessibilityElement {
        .make(
            label: label,
            value: value,
            traits: traits,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: activationPoint,
            respondsToUserInteraction: false
        )
    }
}

#endif

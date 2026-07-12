#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Tests for `TheBurglar.buildObservation(from:)`. Validates that a `ParseResult`
/// is converted into a `InterfaceObservation` value with the current semantics: heistId
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

    // MARK: - buildObservation populates elements

    func testBuildObservationPopulatesElements() {
        let elementA = makeElement(label: "Save", traits: .button)
        let elementB = makeElement(label: "Cancel", traits: .button)
        let result = TheBurglar.ParseResult(
            hierarchy: [
                .element(elementA, traversalIndex: 0),
                .element(elementB, traversalIndex: 1),
            ],
        )

        let screen = TheBurglar.buildObservation(from: result)

        XCTAssertEqual(screen.tree.elements.count, 2, "InterfaceObservation should have one entry per parsed element")
        for heistId in screen.tree.elements.keys {
            XCTAssertNotNil(screen.findElement(heistId: heistId),
                            "Each heistId should map to an entry")
        }
    }

    func testBuildObservationPopulatesHeistIdsByPath() {
        let element = makeElement(label: "OK", traits: .button)
        let result = TheBurglar.ParseResult(
            hierarchy: [.element(element, traversalIndex: 0)],
        )

        let screen = TheBurglar.buildObservation(from: result)

        XCTAssertEqual(screen.liveCapture.heistId(forPath: TreePath([0])), "ok_button")
    }

    func testBuildObservationKeepsDistinctEntriesForValueEqualElements() {
        let first = makeElement(label: "Item", traits: .button)
        let second = makeElement(label: "Item", traits: .button)
        let result = TheBurglar.ParseResult(
            hierarchy: [
                .element(first, traversalIndex: 0),
                .element(second, traversalIndex: 1),
            ],
        )

        let screen = TheBurglar.buildObservation(from: result)
        let interface = TheStash.WireConversion.toInterface(from: screen.tree)

        // Value-equal elements still get distinct synthesized heistIds because
        // live identity is keyed by tree path, not element value equality.
        XCTAssertEqual(screen.tree.elements.count, 2)
        XCTAssertEqual(Set(screen.tree.elements.keys), ["item_button_1", "item_button_2"])
        XCTAssertEqual(interface.annotations.elements.map(\.path), [TreePath([0]), TreePath([1])])
    }

    func testBuildObservationSetsHierarchy() {
        let element = makeElement(label: "Item")
        let hierarchy: [AccessibilityHierarchy] = [.element(element, traversalIndex: 0)]
        let result = TheBurglar.ParseResult(
            hierarchy: hierarchy
        )

        let screen = TheBurglar.buildObservation(from: result)

        XCTAssertEqual(screen.liveCapture.hierarchy.count, 1)
    }

    // MARK: - InterfaceObservation name derivation

    func testScreenNameFromFirstHeader() {
        let header = makeElement(label: "Settings", traits: .header)
        let button = makeElement(label: "Save", traits: .button)
        let result = TheBurglar.ParseResult(
            hierarchy: [
                .element(header, traversalIndex: 0),
                .element(button, traversalIndex: 1),
            ]
        )

        let screen = TheBurglar.buildObservation(from: result)

        XCTAssertEqual(screen.name, "Settings")
    }

    func testScreenIdIsSlugifiedName() {
        let header = makeElement(label: "My Profile", traits: .header)
        let result = TheBurglar.ParseResult(
            hierarchy: [.element(header, traversalIndex: 0)]
        )

        let screen = TheBurglar.buildObservation(from: result)

        XCTAssertEqual(screen.id, TheScore.slugify("My Profile"))
    }

    func testScreenNameNilWhenNoHeaders() {
        let button = makeElement(label: "OK", traits: .button)
        let result = TheBurglar.ParseResult(
            hierarchy: [.element(button, traversalIndex: 0)]
        )

        let screen = TheBurglar.buildObservation(from: result)

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

        let screen = TheBurglar.buildObservation(from: result)

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

        let screen = TheBurglar.buildObservation(from: result)

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

        let screen = TheBurglar.buildObservation(from: result)

        XCTAssertNil(screen.liveCapture.firstResponderHeistId)
    }

    func testBuildObservationUsesSyntheticFirstResponderFacts() {
        let first = makeElement(label: "Email")
        let second = makeElement(label: "Password")
        let firstPath = TreePath([0])
        let secondPath = TreePath([1])
        let result = TheBurglar.ParseResult(
            hierarchy: [
                .element(first, traversalIndex: 0),
                .element(second, traversalIndex: 1),
            ],
            objectsByPath: [
                firstPath: NSObject(),
                secondPath: NSObject(),
            ]
        )
        let facts = TheBurglar.InterfaceObservationBuildFacts(
            focus: TheBurglar.InterfaceObservationBuildFocusFacts(firstResponderPaths: [secondPath])
        )

        let screen = TheBurglar.buildObservation(from: result, facts: facts)

        XCTAssertEqual(
            screen.liveCapture.firstResponderHeistId,
            screen.liveCapture.heistId(forPath: secondPath)
        )
    }

    // MARK: - HeistId determinism

    func testHeistIdsAreAssignedDeterministically() {
        let button = makeElement(label: "Submit", traits: .button)
        let result = TheBurglar.ParseResult(
            hierarchy: [.element(button, traversalIndex: 0)]
        )

        let first = TheBurglar.buildObservation(from: result)
        let second = TheBurglar.buildObservation(from: result)

        XCTAssertEqual(Set(first.tree.elements.keys), Set(second.tree.elements.keys),
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

        let screen = TheBurglar.buildObservation(from: result)

        XCTAssertEqual(screen.tree.elements.count, 2)
        XCTAssertEqual(screen.tree.elements.count, 2,
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

        let screen = TheBurglar.buildObservation(from: result)

        XCTAssertEqual(screen.liveCapture.heistId(forPath: TreePath([1])), "row_button_1")
        XCTAssertEqual(screen.liveCapture.heistId(forPath: TreePath([0])), "row_button_2")
    }

    func testBuildObservationRestoresScreenCoordinateGeometryFromParseRootOffset() throws {
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

        let screen = TheBurglar.buildObservation(from: result)
        let element = try XCTUnwrap(screen.liveCapture.hierarchy.sortedElements.first)
        let projected = try XCTUnwrap(TheStash.WireConversion.toInterface(from: screen.tree).projectedElements.first)

        XCTAssertEqual(element.shape.frame, screenFrame)
        XCTAssertEqual(element.bhResolvedActivationPoint, screenActivationPoint)
        XCTAssertEqual(projected.frameX, screenFrame.origin.x)
        XCTAssertEqual(projected.frameY, screenFrame.origin.y)
        XCTAssertEqual(projected.frameWidth, screenFrame.size.width)
        XCTAssertEqual(projected.frameHeight, screenFrame.size.height)
        XCTAssertEqual(projected.activationPointX, screenActivationPoint.x)
        XCTAssertEqual(projected.activationPointY, screenActivationPoint.y)
    }

    func testBuildObservationRestoresPathGeometryFromParseRootOffset() throws {
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

        let screen = TheBurglar.buildObservation(from: result)
        let translated = try XCTUnwrap(screen.liveCapture.hierarchy.sortedElements.first)

        guard case .path(let elements) = translated.shape else {
            return XCTFail("Expected translated path")
        }
        XCTAssertEqual(elements.first, .move(to: AccessibilityPoint(x: 30, y: 40)))
        XCTAssertEqual(translated.bhResolvedActivationPoint, CGPoint(x: 50, y: 60))
    }

    func testBuildObservationTranslationPreservesContainerFacts() throws {
        let parseRootOffset = CGPoint(x: 12, y: 34)
        let containerPath = TreePath([0])
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 80, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1200)
        let containerFrame = CGRect(x: 0, y: 80, width: 320, height: 400)
        let container = AccessibilityContainer(
            type: .none,
            identifier: "checkout-scroll",
            scrollableContentSize: AccessibilitySize(scrollView.contentSize),
            frame: AccessibilityRect(containerFrame),
            isModalBoundary: true,
            customActions: [AccessibilityElement.CustomAction(name: "Archive")]
        )
        let child = makeElement(
            label: "Checkout",
            traits: .button,
            frame: CGRect(x: 24, y: 160, width: 140, height: 44)
        )
        let result = TheBurglar.ParseResult(
            hierarchy: [.container(container, children: [.element(child, traversalIndex: 0)])],
            scrollViewsByPath: [containerPath: scrollView],
            screenCoordinateOffsetsByPath: [containerPath: parseRootOffset]
        )

        let screen = TheBurglar.buildObservation(from: result)
        let translated = try XCTUnwrap(screen.liveCapture.hierarchy.first)
        guard case .container(let translatedContainer, _) = translated else {
            return XCTFail("Expected translated container")
        }

        XCTAssertEqual(translatedContainer.type, .none)
        XCTAssertEqual(translatedContainer.identifier, "checkout-scroll")
        XCTAssertEqual(translatedContainer.scrollableContentSize, AccessibilitySize(scrollView.contentSize))
        XCTAssertEqual(translatedContainer.isModalBoundary, true)
        XCTAssertEqual(translatedContainer.customActions, [AccessibilityElement.CustomAction(name: "Archive")])
        XCTAssertEqual(translatedContainer.frame.cgRect, containerFrame.offsetBy(dx: 12, dy: 34))
        XCTAssertNotNil(screen.liveCapture.scrollView(forContainerPath: containerPath))
    }

    // MARK: - Scroll membership

    func testPropagatesScrollMembershipForScrollableContainerChild() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 100, width: 320, height: 500))
        scrollView.contentSize = CGSize(width: 320, height: 2000)

        let scrollableContainer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(scrollView.contentSize),
            frame: AccessibilityRect(scrollView.frame)
        )
        let childFrame = CGRect(x: 10, y: 150, width: 50, height: 30)
        let child = makeElement(label: "Cell", traits: .button, frame: childFrame)

        let result = TheBurglar.ParseResult(
            hierarchy: [.container(scrollableContainer, children: [.element(child, traversalIndex: 0)])],
            scrollViewsByPath: [TreePath([0]): scrollView]
        )

        let screen = TheBurglar.buildObservation(from: result)
        guard let heistId = screen.tree.elements.keys.first else {
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

        let screen = TheBurglar.buildObservation(from: result)
        guard let heistId = screen.tree.elements.keys.first else {
            XCTFail("Expected one heistId")
            return
        }

        XCTAssertNil(screen.findElement(heistId: heistId)?.scrollMembership)
    }

    func testBuildObservationUsesSyntheticScrollFactsForPureProjection() throws {
        let scrollPath = TreePath([0])
        let nestedContainerPath = TreePath([0, 0])
        let childPath = TreePath([0, 0, 0])
        let scrollableContainer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(width: 320, height: 2000),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 500)
        )
        let nestedContainer = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: 0, y: 150, width: 320, height: 100)
        )
        let child = makeElement(
            label: "Cell",
            traits: .button,
            frame: CGRect(x: 10, y: 160, width: 120, height: 44)
        )
        let observedElementPoint = try XCTUnwrap(
            InterfaceTree.ObservedScrollContentActivationPoint(CGPoint(x: 70, y: 180))
        )
        let observedContainerPoint = try XCTUnwrap(
            InterfaceTree.ObservedScrollContentActivationPoint(CGPoint(x: 160, y: 200))
        )
        let inventory = ScrollInventory(totalElementCount: 20, visibleIndices: [7])
        let result = TheBurglar.ParseResult(
            hierarchy: [
                .container(scrollableContainer, children: [
                    .container(nestedContainer, children: [
                        .element(child, traversalIndex: 0),
                    ]),
                ]),
            ]
        )
        let facts = TheBurglar.InterfaceObservationBuildFacts(
            scroll: TheBurglar.InterfaceObservationBuildScrollFacts(
                contextContainerPaths: [scrollPath],
                elementsByPath: [
                    childPath: TheBurglar.InterfaceObservationBuildElementScrollFacts(
                        containerPath: scrollPath,
                        index: 7,
                        observedScrollContentActivationPoint: observedElementPoint
                    ),
                ],
                containerObservedScrollContentActivationPointsByPath: [
                    nestedContainerPath: observedContainerPoint,
                ],
                inventoriesByPath: [scrollPath: inventory]
            )
        )

        let screen = TheBurglar.buildObservation(from: result, facts: facts)
        let heistId = try XCTUnwrap(screen.liveCapture.heistId(forPath: childPath))
        let element = try XCTUnwrap(screen.findElement(heistId: heistId))

        XCTAssertEqual(
            element.scrollMembership,
            InterfaceTree.ScrollMembership(containerPath: scrollPath, index: 7)
        )
        XCTAssertEqual(element.observedScrollContentActivationPoint, observedElementPoint)
        XCTAssertEqual(screen.liveCapture.scrollInventory(forPath: scrollPath), inventory)
        XCTAssertEqual(
            screen.liveCapture.containerScrollMembership(forPath: nestedContainerPath),
            InterfaceTree.ScrollMembership(containerPath: scrollPath, index: nil)
        )
        XCTAssertEqual(
            screen.liveCapture.containerObservedScrollContentActivationPoint(forPath: nestedContainerPath),
            observedContainerPoint
        )
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

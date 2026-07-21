#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Tests for `TheVault.buildObservation(from:)`. Validates that a `CaptureResult`
/// is converted into a `InterfaceObservation` value with the current semantics: heistId
/// assignment, scroll membership, first-responder detection, and
/// interface-name derivation.
@MainActor
final class TheVaultObservationBuildingTests: XCTestCase {

    private var vault: TheVault!

    override func setUp() async throws {
        try await super.setUp()
        vault = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        vault = nil
        try await super.tearDown()
    }

    // MARK: - buildObservation populates elements

    func testBuildObservationPopulatesElements() {
        let elementA = makeElement(label: "Save", traits: .button)
        let elementB = makeElement(label: "Cancel", traits: .button)
        let result = TheVault.CaptureResult(
            hierarchy: [
                .element(elementA, traversalIndex: 0),
                .element(elementB, traversalIndex: 1),
            ],
        )

        let observation = TheVault.buildObservation(from: result)

        XCTAssertEqual(observation.tree.elements.count, 2, "InterfaceObservation should have one entry per parsed element")
        for heistId in observation.tree.elements.keys {
            XCTAssertNotNil(observation.tree.findElement(heistId: heistId),
                            "Each heistId should map to an entry")
        }
    }

    func testBuildObservationPopulatesHeistIdsByPath() {
        let element = makeElement(label: "OK", traits: .button)
        let result = TheVault.CaptureResult(
            hierarchy: [.element(element, traversalIndex: 0)],
        )

        let observation = TheVault.buildObservation(from: result)

        XCTAssertEqual(observation.liveCapture.heistId(forPath: TreePath([0])), "ok_button")
    }

    func testBuildObservationKeepsDistinctEntriesForValueEqualElements() {
        let first = makeElement(label: "Item", traits: .button)
        let second = makeElement(label: "Item", traits: .button)
        let result = TheVault.CaptureResult(
            hierarchy: [
                .element(first, traversalIndex: 0),
                .element(second, traversalIndex: 1),
            ],
        )

        let observation = TheVault.buildObservation(from: result)
        let interface = TheVault.WireConversion.toSemanticInterface(from: observation.tree)

        // Value-equal elements still get distinct synthesized heistIds because
        // live identity is keyed by tree path, not element value equality.
        XCTAssertEqual(observation.tree.elements.count, 2)
        XCTAssertEqual(Set(observation.tree.elements.keys), ["item_button_1", "item_button_2"])
        XCTAssertEqual(Set(observation.tree.elements.values.map(\.path)), [TreePath([0]), TreePath([1])])
        XCTAssertEqual(interface.annotations.elements.map(\.path), [TreePath([0]), TreePath([1])])
    }

    func testBuildObservationSetsHierarchy() {
        let element = makeElement(label: "Item")
        let hierarchy: [AccessibilityHierarchy] = [.element(element, traversalIndex: 0)]
        let result = TheVault.CaptureResult(
            hierarchy: hierarchy
        )

        let observation = TheVault.buildObservation(from: result)

        XCTAssertEqual(observation.liveCapture.hierarchy.count, 1)
    }

    func testBuildObservationKeepsOffscreenFactsOutOfViewportEvidence() {
        let visible = makeElement(label: "Visible", traits: .button)
        let offscreen = makeElement(
            label: "Offscreen",
            traits: .button,
            visibility: .offscreen
        )
        let result = TheVault.CaptureResult(
            hierarchy: [
                .element(visible, traversalIndex: 0),
                .element(offscreen, traversalIndex: 1),
            ]
        )

        let observation = TheVault.buildObservation(from: result)

        XCTAssertEqual(observation.tree.elementIDs, ["visible_button", "offscreen_button"])
        XCTAssertEqual(observation.tree.viewportElementIDs, ["visible_button"])
        XCTAssertEqual(observation.liveCapture.heistIds, ["visible_button"])
        XCTAssertFalse(observation.liveCapture.contains(heistId: "offscreen_button"))
        XCTAssertEqual(observation.viewportOnly.tree.elementIDs, ["visible_button"])
        XCTAssertNotNil(observation.tree.findElement(heistId: "offscreen_button"))
    }

    func testBuildObservationAdmitsScrollInventoryOffscreenElementsAsKnownOnly() throws {
        let scrollContainerPath = TreePath([0])
        let visiblePath = scrollContainerPath.appending(0)
        let offscreenPath = scrollContainerPath.appending(1_000_004)
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible", traits: .button)
        let offscreen = makeElement(
            label: "Far Target",
            traits: .button,
            frame: CGRect(x: 40, y: 1_120, width: 220, height: 44),
            activationPoint: CGPoint(x: 150, y: 1_142),
            visibility: .offscreen
        )
        let observedPoint = try XCTUnwrap(
            InterfaceTree.ObservedScrollContentActivationPoint(
                CGPoint(x: 150, y: 1_142),
                ownerPath: scrollContainerPath
            )
        )
        let result = TheVault.CaptureResult(
            hierarchy: [
                .container(makeScrollableContainer(), children: [
                    .element(visible, traversalIndex: 0)
                ])
            ],
            objectsByPath: [visiblePath: NSObject()],
            containerObjectsByPath: [scrollContainerPath: scrollView],
            scrollViewsByPath: [scrollContainerPath: scrollView],
            offscreenScrollElements: [
                .init(
                    path: offscreenPath,
                    scrollContainerPath: scrollContainerPath,
                    scrollIndex: 4,
                    element: offscreen,
                    observedScrollContentActivationPoint: observedPoint
                )
            ]
        )

        let observation = TheVault.buildObservation(from: result)
        let target = try XCTUnwrap(observation.tree.orderedElements.first {
            $0.element.label == "Far Target"
        })

        XCTAssertEqual(target.path, offscreenPath)
        XCTAssertEqual(
            target.scrollMembership,
            InterfaceTree.ScrollMembership(containerPath: scrollContainerPath, index: 4)
        )
        XCTAssertEqual(target.observedScrollContentActivationPoint, observedPoint)
        XCTAssertFalse(observation.tree.viewportElementIDs.contains(target.heistId))
        XCTAssertFalse(observation.liveCapture.contains(heistId: target.heistId))
        XCTAssertNil(observation.liveCapture.object(for: target.heistId))
        XCTAssertEqual(observation.viewportOnly.tree.elementIDs, ["visible_button"])

        let interface = TheVault.WireConversion.discoveryProjection(from: observation.tree).interface
        XCTAssertEqual(interface.projectedElements.compactMap(\.label), ["Visible", "Far Target"])
        guard case .container(_, let children) = interface.tree.first,
              case .element(let projectedOffscreen, _) = children.last
        else {
            return XCTFail("Expected offscreen inventory element projected under the scroll container")
        }
        XCTAssertEqual(projectedOffscreen.label, "Far Target")
        XCTAssertEqual(projectedOffscreen.visibility, .offscreen)
    }

    // MARK: - InterfaceObservation name derivation

    func testScreenNameFromFirstHeader() {
        let header = makeElement(label: "Settings", traits: .header)
        let button = makeElement(label: "Save", traits: .button)
        let result = TheVault.CaptureResult(
            hierarchy: [
                .element(header, traversalIndex: 0),
                .element(button, traversalIndex: 1),
            ]
        )

        let observation = TheVault.buildObservation(from: result)

        XCTAssertEqual(observation.tree.name, "Settings")
    }

    func testScreenIdIsSlugifiedName() {
        let header = makeElement(label: "My Profile", traits: .header)
        let result = TheVault.CaptureResult(
            hierarchy: [.element(header, traversalIndex: 0)]
        )

        let observation = TheVault.buildObservation(from: result)

        XCTAssertEqual(observation.tree.id, TheScore.slugify("My Profile"))
    }

    func testScreenNameNilWhenNoHeaders() {
        let button = makeElement(label: "OK", traits: .button)
        let result = TheVault.CaptureResult(
            hierarchy: [.element(button, traversalIndex: 0)]
        )

        let observation = TheVault.buildObservation(from: result)

        XCTAssertNil(observation.tree.name)
        XCTAssertNil(observation.tree.id)
    }

    func testScreenNameIgnoresHeaderWithNilLabel() {
        let headerNoLabel = makeElement(label: nil, traits: .header)
        let button = makeElement(label: "OK", traits: .button)
        let result = TheVault.CaptureResult(
            hierarchy: [
                .element(headerNoLabel, traversalIndex: 0),
                .element(button, traversalIndex: 1),
            ]
        )

        let observation = TheVault.buildObservation(from: result)

        XCTAssertNil(observation.tree.name)
    }

    // MARK: - First responder detection

    func testDetectsFirstResponder() async {
        let textField = UITextField()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.addSubview(textField)
        window.makeKeyAndVisible()
        textField.becomeFirstResponder()

        let element = makeElement(label: "Email", traits: .none)
        let result = TheVault.CaptureResult(
            hierarchy: [.element(element, traversalIndex: 0)],
            objectsByPath: [TreePath([0]): textField],
        )

        let observation = TheVault.buildObservation(from: result)

        XCTAssertNotNil(observation.liveCapture.firstResponderHeistId)

        textField.resignFirstResponder()
        window.isHidden = true
        await KeyboardWindowTestHelpers.waitForKeyboardWindowsToRetire()
    }

    func testFirstResponderNilWhenNoneActive() {
        let element = makeElement(label: "Label")
        let label = UILabel()
        let result = TheVault.CaptureResult(
            hierarchy: [.element(element, traversalIndex: 0)],
            objectsByPath: [TreePath([0]): label],
        )

        let observation = TheVault.buildObservation(from: result)

        XCTAssertNil(observation.liveCapture.firstResponderHeistId)
    }

    func testBuildObservationUsesSyntheticFirstResponderFacts() {
        let first = makeElement(label: "Email")
        let second = makeElement(label: "Password")
        let firstPath = TreePath([0])
        let secondPath = TreePath([1])
        let result = TheVault.CaptureResult(
            hierarchy: [
                .element(first, traversalIndex: 0),
                .element(second, traversalIndex: 1),
            ],
            objectsByPath: [
                firstPath: NSObject(),
                secondPath: NSObject(),
            ]
        )
        let facts = TheVault.BuildFacts(
            focus: TheVault.FocusFacts(firstResponderPaths: [secondPath])
        )

        let observation = TheVault.buildObservation(from: result, facts: facts)

        XCTAssertEqual(
            observation.liveCapture.firstResponderHeistId,
            observation.liveCapture.heistId(forPath: secondPath)
        )
    }

    // MARK: - HeistId determinism

    func testHeistIdsAreAssignedDeterministically() {
        let button = makeElement(label: "Submit", traits: .button)
        let result = TheVault.CaptureResult(
            hierarchy: [.element(button, traversalIndex: 0)]
        )

        let first = TheVault.buildObservation(from: result)
        let second = TheVault.buildObservation(from: result)

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
        let result = TheVault.CaptureResult(
            hierarchy: [
                .element(buttonA, traversalIndex: 0),
                .element(buttonB, traversalIndex: 1),
            ]
        )

        let observation = TheVault.buildObservation(from: result)

        XCTAssertEqual(observation.tree.elements.count, 2)
        XCTAssertEqual(observation.tree.elements.count, 2,
                       "Duplicate labels should produce two distinct entries")
    }

    func testElementOrderDerivesFromHierarchyTraversalIndex() {
        let first = makeElement(label: "Row", traits: .button,
                                frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        let second = makeElement(label: "Row", traits: .button,
                                 frame: CGRect(x: 0, y: 50, width: 100, height: 44))
        let result = TheVault.CaptureResult(
            hierarchy: [
                .element(second, traversalIndex: 1),
                .element(first, traversalIndex: 0),
            ],
        )

        let observation = TheVault.buildObservation(from: result)

        XCTAssertEqual(observation.liveCapture.heistId(forPath: TreePath([1])), "row_button_1")
        XCTAssertEqual(observation.liveCapture.heistId(forPath: TreePath([0])), "row_button_2")
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

        let result = TheVault.CaptureResult(
            hierarchy: [.element(parsedElement, traversalIndex: 0)],
            screenCoordinateOffsetsByPath: [TreePath([0]): parseRootOffset]
        )

        let observation = TheVault.buildObservation(from: result)
        let element = try XCTUnwrap(observation.liveCapture.hierarchy.sortedElements.first)
        let projected = TheVault.WireConversion.convert(element)

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
        let result = TheVault.CaptureResult(
            hierarchy: [.element(pathElement, traversalIndex: 0)],
            screenCoordinateOffsetsByPath: [TreePath([0]): parseRootOffset]
        )

        let observation = TheVault.buildObservation(from: result)
        let translated = try XCTUnwrap(observation.liveCapture.hierarchy.sortedElements.first)

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
        let result = TheVault.CaptureResult(
            hierarchy: [.container(container, children: [.element(child, traversalIndex: 0)])],
            scrollViewsByPath: [containerPath: scrollView],
            screenCoordinateOffsetsByPath: [containerPath: parseRootOffset]
        )

        let observation = TheVault.buildObservation(from: result)
        let translated = try XCTUnwrap(observation.liveCapture.hierarchy.first)
        guard case .container(let translatedContainer, _) = translated else {
            return XCTFail("Expected translated container")
        }

        XCTAssertEqual(translatedContainer.type, .none)
        XCTAssertEqual(translatedContainer.identifier, "checkout-scroll")
        XCTAssertEqual(translatedContainer.scrollableContentSize, AccessibilitySize(scrollView.contentSize))
        XCTAssertEqual(translatedContainer.isModalBoundary, true)
        XCTAssertEqual(translatedContainer.customActions, [AccessibilityElement.CustomAction(name: "Archive")])
        XCTAssertEqual(translatedContainer.frame.cgRect, containerFrame.offsetBy(dx: 12, dy: 34))
        XCTAssertNotNil(observation.liveCapture.scrollView(forContainerPath: containerPath))
    }

    // MARK: - Scroll membership

    func testObservedScrollContentActivationPointAdmitsOnlyMatchingOwner() throws {
        let ownerPath = TreePath([0, 1])
        let point = try XCTUnwrap(
            InterfaceTree.ObservedScrollContentActivationPoint(
                CGPoint(x: 120, y: 640),
                ownerPath: ownerPath
            )
        )

        XCTAssertEqual(point.admit(ownerPath: ownerPath), point.point)
        XCTAssertNil(point.admit(ownerPath: TreePath([0])))
        XCTAssertNil(point.admit(ownerPath: TreePath([0, 2])))
    }

    func testObservedContentPointsCarryProducingContainerPath() throws {
        let outerPath = TreePath([0])
        let viewportElementPath = TreePath([0, 0])
        let nestedPath = TreePath([0, 1])
        let outerScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        outerScrollView.contentSize = CGSize(width: 320, height: 2_000)
        let offscreenElement = UIAccessibilityElement(accessibilityContainer: NSObject())
        offscreenElement.accessibilityLabel = "Offscreen"
        offscreenElement.accessibilityTraits = .button
        offscreenElement.accessibilityFrame = CGRect(x: 20, y: 900, width: 160, height: 44)
        offscreenElement.accessibilityActivationPoint = CGPoint(x: 100, y: 922)
        let nestedScrollView = ObservationInventoryScrollView(element: offscreenElement)
        nestedScrollView.frame = CGRect(x: 0, y: 500, width: 320, height: 300)
        nestedScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let viewportElement = makeElement(
            label: "Viewport",
            traits: .button,
            frame: CGRect(x: 20, y: 120, width: 160, height: 44),
            activationPoint: CGPoint(x: 100, y: 142)
        )
        let inventory = vault.enumerateOffscreenScrollInventory(
            objectsByPath: [:],
            scrollViewsByPath: [nestedPath: nestedScrollView],
            budget: 1
        )
        XCTAssertEqual(inventory.offscreenElements.count, 1)
        let offscreenPoint = try XCTUnwrap(
            inventory.offscreenElements.first?.observedScrollContentActivationPoint
        )
        let result = TheVault.CaptureResult(
            hierarchy: [
                .container(makeScrollableContainer(), children: [
                    .element(viewportElement, traversalIndex: 0),
                    .container(
                        makeScrollableContainer(
                            frame: CGRect(x: 0, y: 500, width: 320, height: 300)
                        ),
                        children: []
                    ),
                ]),
            ],
            scrollViewsByPath: [
                outerPath: outerScrollView,
                nestedPath: nestedScrollView,
            ]
        )

        let observation = TheVault.buildObservation(from: result)
        let viewportHeistId = try XCTUnwrap(observation.liveCapture.heistId(forPath: viewportElementPath))
        let viewportPoint = try XCTUnwrap(
            observation.tree.elements[viewportHeistId]?.observedScrollContentActivationPoint
        )
        let nestedPoint = try XCTUnwrap(
            observation.tree.containers[nestedPath]?.observedScrollContentActivationPoint
        )
        XCTAssertEqual(viewportPoint.ownerPath, outerPath)
        XCTAssertEqual(nestedPoint.ownerPath, outerPath)
        XCTAssertEqual(offscreenPoint.ownerPath, nestedPath)
    }

    func testPropagatesScrollMembershipForScrollableContainerChild() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 100, width: 320, height: 500))
        scrollView.contentSize = CGSize(width: 320, height: 2000)

        let scrollableContainer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(scrollView.contentSize),
            frame: AccessibilityRect(scrollView.frame)
        )
        let childFrame = CGRect(x: 10, y: 150, width: 50, height: 30)
        let child = makeElement(label: "Cell", traits: .button, frame: childFrame)

        let result = TheVault.CaptureResult(
            hierarchy: [.container(scrollableContainer, children: [.element(child, traversalIndex: 0)])],
            scrollViewsByPath: [TreePath([0]): scrollView]
        )

        let observation = TheVault.buildObservation(from: result)
        guard let heistId = observation.tree.elements.keys.first else {
            XCTFail("Expected one heistId")
            return
        }

        XCTAssertEqual(observation.tree.findElement(heistId: heistId)?.scrollMembership?.containerPath, TreePath([0]))
    }

    func testLeavesScrollMembershipNilOutsideScrollableContainer() {
        let element = makeElement(label: "Plain",
                                  frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let result = TheVault.CaptureResult(
            hierarchy: [.element(element, traversalIndex: 0)]
        )

        let observation = TheVault.buildObservation(from: result)
        guard let heistId = observation.tree.elements.keys.first else {
            XCTFail("Expected one heistId")
            return
        }

        XCTAssertNil(observation.tree.findElement(heistId: heistId)?.scrollMembership)
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
            InterfaceTree.ObservedScrollContentActivationPoint(
                CGPoint(x: 70, y: 180),
                ownerPath: scrollPath
            )
        )
        let observedContainerPoint = try XCTUnwrap(
            InterfaceTree.ObservedScrollContentActivationPoint(
                CGPoint(x: 160, y: 200),
                ownerPath: scrollPath
            )
        )
        let inventory = try XCTUnwrap(
            ScrollInventory(totalElementCount: 20, visibleIndices: [7])
        )
        let result = TheVault.CaptureResult(
            hierarchy: [
                .container(scrollableContainer, children: [
                    .container(nestedContainer, children: [
                        .element(child, traversalIndex: 0),
                    ]),
                ]),
            ]
        )
        let facts = TheVault.BuildFacts(
            scroll: TheVault.ScrollFacts(
                contextContainerPaths: [scrollPath],
                elementsByPath: [
                    childPath: TheVault.ElementScrollFacts(
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

        let observation = TheVault.buildObservation(from: result, facts: facts)
        let heistId = try XCTUnwrap(observation.liveCapture.heistId(forPath: childPath))
        let element = try XCTUnwrap(observation.tree.findElement(heistId: heistId))

        XCTAssertEqual(
            element.scrollMembership,
            InterfaceTree.ScrollMembership(containerPath: scrollPath, index: 7)
        )
        XCTAssertEqual(element.observedScrollContentActivationPoint, observedElementPoint)
        XCTAssertEqual(observation.tree.containers[scrollPath]?.scrollInventory, inventory)
        XCTAssertEqual(
            observation.tree.containers[nestedContainerPath]?.scrollMembership,
            InterfaceTree.ScrollMembership(containerPath: scrollPath, index: nil)
        )
        XCTAssertEqual(
            observation.tree.containers[nestedContainerPath]?.observedScrollContentActivationPoint,
            observedContainerPoint
        )
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        traits: UIAccessibilityTraits = .none,
        frame: CGRect = .zero,
        activationPoint: CGPoint? = nil,
        visibility: AccessibilityVisibility = .onscreen
    ) -> AccessibilityElement {
        .make(
            label: label,
            value: value,
            traits: traits,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: activationPoint,
            respondsToUserInteraction: false,
            visibility: visibility
        )
    }

    private func makeScrollableContainer(
        contentSize: CGSize = CGSize(width: 320, height: 1_600),
        frame: CGRect = CGRect(x: 0, y: 0, width: 320, height: 400)
    ) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .none,
            scrollableContentSize: AccessibilitySize(contentSize),
            frame: AccessibilityRect(frame)
        )
    }
}

@MainActor
private final class ObservationInventoryScrollView: UIScrollView {
    private let element: NSObject

    init(element: NSObject) {
        self.element = element
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func accessibilityElementCount() -> Int {
        1
    }

    override func accessibilityElement(at index: Int) -> Any? {
        index == 0 ? element : nil
    }
}

#endif

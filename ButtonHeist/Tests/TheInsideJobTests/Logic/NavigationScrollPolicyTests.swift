#if canImport(UIKit)
import UIKit
import XCTest

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import ThePlans

@MainActor
final class NavigationScrollPolicyTests: XCTestCase {
    private var brains: TheBrains!
    private var retainedLiveObjects: [NSObject] = []

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        brains.vault.semanticObservationStream.stop()
        brains = nil
        retainedLiveObjects = []
        try await super.tearDown()
    }

    func testRequiredAxisForScrollDirection() async {
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.up), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.down), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.left), .horizontal)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.right), .horizontal)
    }

    func testRequiredAxisForScrollEdge() async {
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollEdge.top), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollEdge.bottom), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollEdge.left), .horizontal)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollEdge.right), .horizontal)
    }

    func testUIScrollDirectionFromScrollDirection() async {
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.up), .up)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.down), .down)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.left), .left)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.right), .right)
    }

    func testScrollTargetDescriptionUsesNamedPriority() async {
        let labeledElement = AccessibilityElement.make(label: "Labeled", identifier: "labeled_id")
        let labeled = InterfaceTree.Element(
            heistId: "labeled_item", scrollMembership: nil,
            geometry: testGeometry(for: labeledElement, ownerPath: .root, screen: TheVault.onscreenSpace(for: labeledElement)),
            element: labeledElement
        )
        let identifiedElement = AccessibilityElement.make(identifier: "identified_id")
        let identified = InterfaceTree.Element(
            heistId: "identified_item", scrollMembership: nil,
            geometry: testGeometry(for: identifiedElement, ownerPath: .root, screen: TheVault.onscreenSpace(for: identifiedElement)),
            element: identifiedElement
        )
        let anonymousElement = AccessibilityElement.make()
        let anonymous = InterfaceTree.Element(
            heistId: "anonymous_item", scrollMembership: nil,
            geometry: testGeometry(for: anonymousElement, ownerPath: .root, screen: TheVault.onscreenSpace(for: anonymousElement)),
            element: anonymousElement
        )

        XCTAssertEqual(Navigation.ScrollTargetDescription(labeled), .label("Labeled"))
        XCTAssertEqual(Navigation.ScrollTargetDescription(identified), .identifier("identified_id"))
        XCTAssertEqual(Navigation.ScrollTargetDescription(anonymous), .element)
    }

    func testScrollCandidatesFilterToRequiredAxis() async {
        let vertical = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 2_000),
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        let horizontal = makeScrollableContainer(
            contentSize: CGSize(width: 1_200, height: 200),
            frame: CGRect(x: 0, y: 420, width: 320, height: 200)
        )
        await installScrollableContainers([vertical, horizontal])

        XCTAssertEqual(brains.navigation.scrollCandidates(requiredAxis: .horizontal).map(\.container), [horizontal])
    }

    func testScrollCandidatesPreserveTreeOrderWithinRequiredAxis() async {
        let horizontal = makeScrollableContainer(
            contentSize: CGSize(width: 1_200, height: 200),
            frame: CGRect(x: 0, y: 0, width: 320, height: 200)
        )
        let verticalOne = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 1_600),
            frame: CGRect(x: 0, y: 220, width: 320, height: 400)
        )
        let verticalTwo = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 1_800),
            frame: CGRect(x: 0, y: 640, width: 320, height: 400)
        )
        await installScrollableContainers([horizontal, verticalOne, verticalTwo])

        XCTAssertEqual(
            brains.navigation.scrollCandidates(requiredAxis: .vertical).map(\.container),
            [verticalOne, verticalTwo]
        )
    }

    private func makeScrollableContainer(contentSize: CGSize, frame: CGRect) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .none,
            scrollableContentSize: AccessibilitySize(contentSize),
            frame: AccessibilityRect(frame)
        )
    }

    private func installScrollableContainers(_ containers: [AccessibilityContainer]) async {
        let containerRefs = Dictionary(uniqueKeysWithValues: containers.indices.map { index in
            let object = NSObject()
            retainedLiveObjects.append(object)
            return (TreePath([index]), LiveCapture.ContainerRef(object: object))
        })
        let observation = InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: containers.map { .container($0, children: []) },
            containerRefsByPath: containerRefs,
            firstResponderHeistId: nil
        )
        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(observation)
    }
}

#endif

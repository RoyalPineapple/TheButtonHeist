#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class ScreenClassifierTests: XCTestCase {

    func testPrimaryHeaderChangeInfersScreenChange() {
        let before = screen(elements: [element(label: "Home", traits: .header)])
        let after = screen(elements: [element(label: "Settings", traits: .header)])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .inferredScreenChange(reason: .primaryHeaderChanged))
    }

    func testExplicitSummaryElementKeepsSameGeneration() {
        let before = screen(elements: [
            element(label: "Home Header", traits: .header),
            element(label: "Messages", traits: .summaryElement),
        ])
        let after = screen(elements: [
            element(label: "Settings Header", traits: .header),
            element(label: "Messages", traits: .summaryElement),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .sameGeneration)
    }

    func testBackButtonChangeInfersScreenChange() {
        let before = screen(elements: [element(label: "Detail", traits: .header)])
        let after = screen(elements: [
            element(label: "Orders", traits: UIAccessibilityTraits.fromNames(["backButton"])),
            element(label: "Detail", traits: .header),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .inferredScreenChange(reason: .navigationMarkerChanged))
    }

    func testSelectedTabChangeInfersScreenChange() {
        let tabBar = AccessibilityContainer(type: .tabBar, frame: .zero)
        let before = screen(hierarchy: [
            .container(tabBar, children: [
                .element(element(label: "Home", traits: [.button, .selected]), traversalIndex: 0),
                .element(element(label: "Settings", traits: .button), traversalIndex: 1),
            ]),
        ])
        let after = screen(hierarchy: [
            .container(tabBar, children: [
                .element(element(label: "Home", traits: .button), traversalIndex: 0),
                .element(element(label: "Settings", traits: [.button, .selected]), traversalIndex: 1),
            ]),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .inferredScreenChange(reason: .selectedTabChanged))
    }

    func testSelectedTabComparisonIncludesEveryTabBar() {
        let firstTabBar = AccessibilityContainer(type: .tabBar, identifier: "primary_tabs", frame: .zero)
        let secondTabBar = AccessibilityContainer(type: .tabBar, identifier: "secondary_tabs", frame: .zero)
        let before = screen(hierarchy: [
            .container(firstTabBar, children: [
                .element(element(label: "Home", traits: [.button, .selected]), traversalIndex: 0),
                .element(element(label: "Settings", traits: .button), traversalIndex: 1),
            ]),
            .container(secondTabBar, children: [
                .element(element(label: "Overview", traits: [.button, .selected]), traversalIndex: 2),
                .element(element(label: "Details", traits: .button), traversalIndex: 3),
            ]),
        ])
        let after = screen(hierarchy: [
            .container(firstTabBar, children: [
                .element(element(label: "Home", traits: [.button, .selected]), traversalIndex: 0),
                .element(element(label: "Settings", traits: .button), traversalIndex: 1),
            ]),
            .container(secondTabBar, children: [
                .element(element(label: "Overview", traits: .button), traversalIndex: 2),
                .element(element(label: "Details", traits: [.button, .selected]), traversalIndex: 3),
            ]),
        ])

        XCTAssertEqual(
            classify(before: before, after: after),
            .inferredScreenChange(reason: .selectedTabChanged)
        )
    }

    func testModalBoundaryChangeInfersScreenChange() {
        let modal = AccessibilityContainer(
            type: .semanticGroup(label: "Alert", value: nil), identifier: nil,
            frame: .zero,
            isModalBoundary: true
        )
        let before = screen(elements: [element(label: "Home", traits: .header)])
        let after = screen(hierarchy: [
            .container(modal, children: [
                .element(element(label: "Confirm", traits: .header), traversalIndex: 0),
            ]),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .inferredScreenChange(reason: .modalBoundaryChanged))
    }

    func testRootShapeReplacementWithoutNavigationMarkersInfersScreenChange() {
        let before = screen(elements: [element(label: "Search", traits: .searchField)])
        let after = screen(elements: [
            element(label: "Inbox", traits: .button),
            element(label: "Compose", traits: .button),
            element(label: "Settings", traits: .button),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .inferredScreenChange(reason: .rootShapeChanged))
    }

    func testRootShapeAdditionWithoutReplacementKeepsSameGeneration() {
        let before = screen(elements: [
            element(label: "Search", traits: .searchField),
            element(label: "Save", traits: .button),
        ])
        let after = screen(elements: [
            element(label: "Search", traits: .searchField),
            element(label: "Save", traits: .button),
            element(label: "Filtered result", traits: .button),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .sameGeneration)
    }

    func testStableFirstResponderAloneKeepsRootShapeChurnInSameGeneration() {
        let before = focusedScreen(
            elements: [element(label: "Search", traits: .searchField)],
            firstResponderHeistId: "search"
        )
        let after = focusedScreen(
            elements: [
                element(label: "Search", traits: .searchField),
                element(label: "First result", traits: .button),
                element(label: "Second result", traits: .button),
                element(label: "Third result", traits: .button),
            ],
            firstResponderHeistId: "search"
        )
        let afterWithoutFocus = screen(elements: [
            element(label: "Search", traits: .searchField),
            element(label: "First result", traits: .button),
            element(label: "Second result", traits: .button),
            element(label: "Third result", traits: .button),
        ])

        XCTAssertEqual(classify(before: before, after: after), .sameGeneration)
        XCTAssertEqual(
            classify(before: before, after: afterWithoutFocus),
            .inferredScreenChange(reason: .rootShapeChanged)
        )
    }

    func testLeafValueChangeKeepsSameGeneration() {
        let before = screen(elements: [element(label: "Total", value: "$1.00", traits: .staticText)])
        let after = screen(elements: [element(label: "Total", value: "$2.00", traits: .staticText)])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .sameGeneration)
    }

    func testDelimiterLikeIdentifierDoesNotCollideWithSelectedState() {
        let before = screen(elements: [
            element(label: "Action", identifier: "toolbar:selected", traits: .button),
        ])
        let after = screen(elements: [
            element(label: "Action", identifier: "toolbar", traits: [.button, .selected]),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .inferredScreenChange(reason: .rootShapeChanged))
    }

    func testDelimiterLikeContainerIdentifierDoesNotCollideWithModalState() {
        let nonModal = AccessibilityContainer(
            type: .semanticGroup(label: "Panel", value: nil), identifier: "dialog:modal",
            frame: .zero
        )
        let modal = AccessibilityContainer(
            type: .semanticGroup(label: "Panel", value: nil), identifier: "dialog",
            frame: .zero,
            isModalBoundary: true
        )

        let before = ScreenClassifier.snapshot(of: screen(hierarchy: [
            .container(nonModal, children: []),
        ]).tree)
        let after = ScreenClassifier.snapshot(of: screen(hierarchy: [
            .container(modal, children: []),
        ]).tree)

        XCTAssertNotEqual(before.signature.rootShape, after.signature.rootShape)
    }

    func testTopLevelMultiRootWrapperAroundSameContentKeepsSameGeneration() {
        let before = screen(elements: [
            element(label: "Checkout", traits: .header),
            element(label: "Total", value: "$1.00", traits: .staticText),
        ])
        let overlayWindow = AccessibilityContainer(
            type: .semanticGroup(label: "OverlayWindow", value: "debug wrapper"), identifier: nil,
            frame: .zero
        )
        let appWindow = AccessibilityContainer(
            type: .semanticGroup(label: "UIWindow", value: "debug wrapper"), identifier: nil,
            frame: .zero
        )
        let after = screen(hierarchy: [
            .container(overlayWindow, children: []),
            .container(appWindow, children: [
                .element(element(label: "Checkout", traits: .header), traversalIndex: 0),
                .element(element(label: "Total", value: "$1.00", traits: .staticText), traversalIndex: 1),
            ]),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .sameGeneration)
    }

    func testSingleTopLevelSemanticGroupAroundSameContentContributesToRootShape() {
        let before = screen(elements: [
            element(label: "Checkout", traits: .header),
        ])
        let group = AccessibilityContainer(
            type: .semanticGroup(label: "Content", value: nil), identifier: nil,
            frame: .zero
        )
        let after = screen(hierarchy: [
            .container(group, children: [
                .element(element(label: "Checkout", traits: .header), traversalIndex: 0),
            ]),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .inferredScreenChange(reason: .rootShapeChanged))
    }

    func testRootShapeComparisonIncludesTokensBeyondFormerCap() {
        let shared = (0..<80).map { index in
            element(label: "Shared \(index)", identifier: "shared_\(index)", traits: .button)
        }
        let beforeElements = shared + (0..<121).map { index in
            element(label: "Before \(index)", identifier: "before_\(index)", traits: .button)
        }
        let afterElements = shared + (0..<121).map { index in
            element(label: "After \(index)", identifier: "after_\(index)", traits: .button)
        }
        let before = screen(elements: beforeElements)
        let after = screen(elements: afterElements)

        XCTAssertEqual(ScreenClassifier.snapshot(of: before.tree).signature.rootShape.count, 201)
        XCTAssertEqual(ScreenClassifier.snapshot(of: after.tree).signature.rootShape.count, 201)
        XCTAssertEqual(
            classify(before: before, after: after),
            .inferredScreenChange(reason: .rootShapeChanged)
        )
    }

    private func classify(before: InterfaceObservation, after: InterfaceObservation) -> ScreenClassifier.Classification {
        ScreenClassifier.classify(
            before: ScreenClassifier.snapshot(of: before.tree),
            after: ScreenClassifier.snapshot(of: after.tree)
        )
    }

    private func focusedScreen(
        elements: [AccessibilityElement],
        firstResponderHeistId: HeistId
    ) -> InterfaceObservation {
        precondition(!elements.isEmpty)
        return InterfaceObservation.makeForTests(
            elements: elements.enumerated().map { index, element in
                let heistId = index == 0
                    ? firstResponderHeistId
                    : HeistId(rawValue: "element_\(index)")
                return (element: element, heistId: heistId)
            },
            firstResponderHeistId: firstResponderHeistId
        )
    }

    private func screen(elements: [AccessibilityElement]) -> InterfaceObservation {
        InterfaceObservation.makeForTests(
            elements: elements.enumerated().map { index, element in
                (element: element, heistId: HeistId(rawValue: "element_\(index)"))
            }
        )
    }

    private func screen(hierarchy: [AccessibilityHierarchy]) -> InterfaceObservation {
        let elements = hierarchy.sortedElements
        return InterfaceObservation.makeForTests(
            elements: Dictionary(uniqueKeysWithValues: elements.enumerated().map { index, element in
                let heistId = HeistId(rawValue: "element_\(index)")
                return (
                    heistId,
                    InterfaceTree.Element(
                        heistId: heistId,
                        scrollMembership: nil,
                        element: element
                    )
                )
            }),
            hierarchy: hierarchy,
            heistIdsByPath: Dictionary(uniqueKeysWithValues: hierarchy.pathIndexedElements.enumerated().map { index, item in
                (item.path, HeistId(rawValue: "element_\(index)"))
            }),
            firstResponderHeistId: nil,
        )
    }

    private func element(
        label: String,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits
    ) -> AccessibilityElement {
        .make(
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            respondsToUserInteraction: false
        )
    }
}

#endif

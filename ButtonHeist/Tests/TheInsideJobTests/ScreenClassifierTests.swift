#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

@MainActor
final class ScreenClassifierTests: XCTestCase {

    func testPrimaryHeaderChangeIsScreenChange() {
        let before = screen(elements: [element(label: "Home", traits: .header)])
        let after = screen(elements: [element(label: "Settings", traits: .header)])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .screenChanged(.primaryHeaderChanged))
    }

    func testBackButtonChangeIsScreenChange() {
        let before = screen(elements: [element(label: "Detail", traits: .header)])
        let after = screen(elements: [
            element(label: "Orders", traits: UIAccessibilityTraits.fromNames(["backButton"])),
            element(label: "Detail", traits: .header),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .screenChanged(.navigationMarkerChanged))
    }

    func testSelectedTabChangeIsScreenChange() {
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

        XCTAssertEqual(result, .screenChanged(.selectedTabChanged))
    }

    func testModalBoundaryChangeIsScreenChange() {
        let modal = AccessibilityContainer(
            type: .semanticGroup(label: "Alert", value: nil, identifier: nil),
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

        XCTAssertEqual(result, .screenChanged(.modalBoundaryChanged))
    }

    func testRootShapeReplacementWithoutNavigationMarkersIsScreenChange() {
        let before = screen(elements: [element(label: "Search", traits: .searchField)])
        let after = screen(elements: [
            element(label: "Inbox", traits: .button),
            element(label: "Compose", traits: .button),
            element(label: "Settings", traits: .button),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .screenChanged(.rootShapeChanged))
    }

    func testRootShapeAdditionWithoutReplacementIsSameScreen() {
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

        XCTAssertEqual(result, .sameScreen)
    }

    func testStableFirstResponderKeepsRootShapeChurnOnSameScreen() {
        let before = screen(
            elements: [element(label: "Search", traits: .searchField)],
            firstResponderHeistId: "search"
        )
        let after = screen(
            elements: [
                element(label: "Search", traits: .searchField),
                element(label: "Filtered result", traits: .button),
            ],
            firstResponderHeistId: "search"
        )

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .sameScreen)
    }

    func testLeafValueChangeIsSameScreen() {
        let before = screen(elements: [element(label: "Total", value: "$1.00", traits: .staticText)])
        let after = screen(elements: [element(label: "Total", value: "$2.00", traits: .staticText)])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .sameScreen)
    }

    func testDelimiterLikeIdentifierDoesNotCollideWithSelectedState() {
        let before = screen(elements: [
            element(label: "Action", identifier: "toolbar:selected", traits: .button),
        ])
        let after = screen(elements: [
            element(label: "Action", identifier: "toolbar", traits: [.button, .selected]),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .screenChanged(.rootShapeChanged))
    }

    func testDelimiterLikeContainerIdentifierDoesNotCollideWithModalState() {
        let nonModal = AccessibilityContainer(
            type: .semanticGroup(label: "Panel", value: nil, identifier: "dialog:modal"),
            frame: .zero
        )
        let modal = AccessibilityContainer(
            type: .semanticGroup(label: "Panel", value: nil, identifier: "dialog"),
            frame: .zero,
            isModalBoundary: true
        )

        let before = ScreenClassifier.snapshot(of: screen(hierarchy: [
            .container(nonModal, children: []),
        ]))
        let after = ScreenClassifier.snapshot(of: screen(hierarchy: [
            .container(modal, children: []),
        ]))

        XCTAssertNotEqual(before.signature.rootShape, after.signature.rootShape)
    }

    func testTopLevelMultiRootWrapperAroundSameContentIsSameScreen() {
        let before = screen(elements: [
            element(label: "Checkout", traits: .header),
            element(label: "Total", value: "$1.00", traits: .staticText),
        ])
        let overlayWindow = AccessibilityContainer(
            type: .semanticGroup(label: "OverlayWindow", value: "debug wrapper", identifier: nil),
            frame: .zero
        )
        let appWindow = AccessibilityContainer(
            type: .semanticGroup(label: "UIWindow", value: "debug wrapper", identifier: nil),
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

        XCTAssertEqual(result, .sameScreen)
    }

    func testSingleTopLevelSemanticGroupAroundSameContentContributesToRootShape() {
        let before = screen(elements: [
            element(label: "Checkout", traits: .header),
        ])
        let group = AccessibilityContainer(
            type: .semanticGroup(label: "Content", value: nil, identifier: nil),
            frame: .zero
        )
        let after = screen(hierarchy: [
            .container(group, children: [
                .element(element(label: "Checkout", traits: .header), traversalIndex: 0),
            ]),
        ])

        let result = classify(before: before, after: after)

        XCTAssertEqual(result, .screenChanged(.rootShapeChanged))
    }

    private func classify(before: Screen, after: Screen) -> ScreenClassifier.Classification {
        ScreenClassifier.classify(
            before: ScreenClassifier.snapshot(of: before),
            after: ScreenClassifier.snapshot(of: after)
        )
    }

    private func screen(
        elements: [AccessibilityElement],
        firstResponderHeistId: String? = nil
    ) -> Screen {
        Screen.makeForTests(
            elements: elements.enumerated().map { index, element in
                (element: element, heistId: "element_\(index)")
            },
            firstResponderHeistId: firstResponderHeistId
        )
    }

    private func screen(hierarchy: [AccessibilityHierarchy]) -> Screen {
        let elements = hierarchy.sortedElements
        return Screen(
            elements: Dictionary(uniqueKeysWithValues: elements.enumerated().map { index, element in
                (
                    "element_\(index)",
                    Screen.ScreenElement(
                        heistId: "element_\(index)",
                        contentSpaceOrigin: nil,
                        element: element,
                        object: nil,
                        scrollView: nil
                    )
                )
            }),
            hierarchy: hierarchy,
            containerStableIds: [:],
            heistIdByElement: Dictionary(uniqueKeysWithValues: elements.enumerated().map { index, element in
                (element, "element_\(index)")
            }),
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
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

#if canImport(UIKit)
#if DEBUG
import XCTest
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

/// Deterministic tests for `Navigation.hasContentBeyondFrame` — the AX-tree gate
/// that prevents `exploreScreen` from swiping containers whose accessibility
/// descendants all fit inside the container frame (e.g. SwiftUI hosting scroll
/// views around a non-scrolling canvas).
@MainActor
final class ExploreOffFoldGateTests: XCTestCase {

    private let containerFrame = CGRect(x: 0, y: 0, width: 320, height: 500)

    func testNoDescendantsReturnsFalse() {
        let container = makeScrollable(contentSize: CGSize(width: 320, height: 2000))
        let hierarchy: [AccessibilityHierarchy] = [.container(container, children: [])]

        XCTAssertFalse(
            Navigation.hasContentBeyondFrame(of: container, in: hierarchy),
            "An empty container has no content beyond the fold"
        )
    }

    func testAllDescendantsFullyInsideReturnsFalse() {
        let container = makeScrollable(contentSize: CGSize(width: 320, height: 2000))
        let hierarchy: [AccessibilityHierarchy] = [
            .container(container, children: [
                element(label: "Top", frame: CGRect(x: 0, y: 0, width: 320, height: 100)),
                element(label: "Middle", frame: CGRect(x: 0, y: 200, width: 320, height: 100)),
                element(label: "Bottom", frame: CGRect(x: 0, y: 399, width: 320, height: 100)),
            ])
        ]

        XCTAssertFalse(
            Navigation.hasContentBeyondFrame(of: container, in: hierarchy),
            "Every descendant fits within the container frame — nothing to discover by swiping"
        )
    }

    func testDescendantSlightlyPastFoldReturnsTrue() {
        let container = makeScrollable(contentSize: CGSize(width: 320, height: 2000))
        let hierarchy: [AccessibilityHierarchy] = [
            .container(container, children: [
                element(label: "Visible", frame: CGRect(x: 0, y: 0, width: 320, height: 100)),
                // Bottom edge sits 3pt past container.maxY — past the 1pt tolerance.
                element(label: "Clipped", frame: CGRect(x: 0, y: 410, width: 320, height: 93)),
            ])
        ]

        XCTAssertTrue(
            Navigation.hasContentBeyondFrame(of: container, in: hierarchy),
            "A descendant clipped just past the fold counts as off-screen content"
        )
    }

    func testDescendantWithinTolerancePassesAsInside() {
        let container = makeScrollable(contentSize: CGSize(width: 320, height: 2000))
        let hierarchy: [AccessibilityHierarchy] = [
            .container(container, children: [
                // Bottom edge at 500.5 — within the 1pt tolerance.
                element(label: "On edge", frame: CGRect(x: 0, y: 0, width: 320, height: 500.5)),
            ])
        ]

        XCTAssertFalse(
            Navigation.hasContentBeyondFrame(of: container, in: hierarchy),
            "Sub-pixel slack within the tolerance must not count as off-fold"
        )
    }

    func testHorizontallyOffscreenDescendantReturnsTrue() {
        let container = makeScrollable(contentSize: CGSize(width: 1000, height: 500))
        let hierarchy: [AccessibilityHierarchy] = [
            .container(container, children: [
                element(label: "Right of fold", frame: CGRect(x: 400, y: 0, width: 100, height: 50)),
            ])
        ]

        XCTAssertTrue(
            Navigation.hasContentBeyondFrame(of: container, in: hierarchy),
            "Content past the right edge counts as off-fold"
        )
    }

    func testNestedContainerDescendantsAreConsidered() {
        let container = makeScrollable(contentSize: CGSize(width: 320, height: 2000))
        let nestedGroup = AccessibilityContainer(
            type: .semanticGroup(label: "Nested", value: nil, identifier: nil),
            frame: CGRect(x: 0, y: 0, width: 320, height: 200)
        )
        let hierarchy: [AccessibilityHierarchy] = [
            .container(container, children: [
                .container(nestedGroup, children: [
                    element(label: "Way Below", frame: CGRect(x: 0, y: 800, width: 320, height: 50)),
                ])
            ])
        ]

        XCTAssertTrue(
            Navigation.hasContentBeyondFrame(of: container, in: hierarchy),
            "Descendants of nested containers must be inspected too"
        )
    }

    func testDescendantsOutsideTargetContainerAreIgnored() {
        let target = makeScrollable(contentSize: CGSize(width: 320, height: 2000))
        let unrelated = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 5000)),
            frame: CGRect(x: 0, y: 600, width: 320, height: 200)
        )
        let hierarchy: [AccessibilityHierarchy] = [
            .container(target, children: [
                element(label: "Inside target", frame: CGRect(x: 0, y: 0, width: 320, height: 100)),
            ]),
            .container(unrelated, children: [
                // Off-fold relative to `unrelated`, but irrelevant when querying `target`.
                element(label: "Sibling overflow", frame: CGRect(x: 0, y: 4000, width: 320, height: 100)),
            ])
        ]

        XCTAssertFalse(
            Navigation.hasContentBeyondFrame(of: target, in: hierarchy),
            "Off-fold content inside a sibling container must not bleed into the target's verdict"
        )
    }

    // MARK: - Helpers

    private func makeScrollable(contentSize: CGSize) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .scrollable(contentSize: contentSize),
            frame: containerFrame
        )
    }

    private func element(label: String, frame: CGRect, index: Int = 0) -> AccessibilityHierarchy {
        .element(.make(label: label, frame: frame), traversalIndex: index)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

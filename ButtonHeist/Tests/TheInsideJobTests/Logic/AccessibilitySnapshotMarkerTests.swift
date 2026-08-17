#if canImport(UIKit)
import AccessibilitySnapshotModel
import Foundation
import XCTest

@testable import TheInsideJob
import TheScore

final class AccessibilitySnapshotMarkerTests: XCTestCase {
    func testMarkersContainOnlyOnscreenElementsInTraversalOrder() throws {
        let interface = try XCTUnwrap(Interface(
            admitting: Date(),
            tree: [
                element(label: "First visible", visibility: .onscreen, traversalIndex: 0),
                element(label: "Offscreen", visibility: .offscreen, traversalIndex: 1),
                element(label: "Second visible", visibility: .onscreen, traversalIndex: 2),
            ]
        ))

        let markers = TheBrains.accessibilitySnapshotMarkers(in: interface)
        let numberedLabels = markers.enumerated().map { index, marker in
            "\(index + 1): \(marker.label ?? "")"
        }

        XCTAssertEqual(numberedLabels, ["1: First visible", "2: Second visible"])
    }

    private func element(
        label: String,
        visibility: AccessibilityVisibility,
        traversalIndex: Int
    ) -> AccessibilityHierarchy {
        .element(
            .make(label: label, visibility: visibility),
            traversalIndex: traversalIndex
        )
    }
}
#endif

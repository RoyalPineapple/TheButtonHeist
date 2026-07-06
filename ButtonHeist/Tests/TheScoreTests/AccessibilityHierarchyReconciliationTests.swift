import AccessibilitySnapshotModel
import XCTest

@testable import TheScore

final class AccessibilityHierarchyReconciliationTests: XCTestCase {
    func testContentFingerprintIgnoresTraversalIndex() {
        let first = AccessibilityHierarchy.element(makeElement(label: "Row", identifier: "row"), traversalIndex: 0)
        let second = AccessibilityHierarchy.element(makeElement(label: "Row", identifier: "row"), traversalIndex: 12)

        XCTAssertEqual(first.contentFingerprint, second.contentFingerprint)
    }

    func testContentFingerprintIncludesSemanticFieldsAndGeometry() {
        XCTAssertNotEqual(
            makeElement(label: "Save").contentFingerprint,
            makeElement(label: "Cancel").contentFingerprint
        )
        XCTAssertNotEqual(
            makeElement(label: "Cell", y: 0).contentFingerprint,
            makeElement(label: "Cell", y: 44).contentFingerprint
        )
    }

    func testOverlapFindsForwardScrollIntersection() {
        let result = findOverlap(accumulated: [1, 2, 3, 4, 5], page: [4, 5, 6, 7])

        XCTAssertEqual(result.accumulatedStart, 3)
        XCTAssertEqual(result.pageStart, 0)
        XCTAssertEqual(result.length, 2)
    }

    func testReconcilePageMergesOverlappingPageEvidence() {
        let row1 = makeElement(label: "Row 1", identifier: "r1", y: 0)
        let row2 = makeElement(label: "Row 2", identifier: "r2", y: 44)
        let row3 = makeElement(label: "Row 3", identifier: "r3", y: 88)
        let row4 = makeElement(label: "Row 4", identifier: "r4", y: 132)

        let result = reconcilePage(
            accumulated: [row1, row2],
            page: [row2, row3, row4]
        )

        XCTAssertEqual(result.overlap.length, 1)
        XCTAssertEqual(result.inserted.map(\.label), ["Row 3", "Row 4"])
        XCTAssertEqual(result.elements.map(\.label), ["Row 1", "Row 2", "Row 3", "Row 4"])
    }

    func testSafeIntClampsNonFiniteAndHugeValues() {
        XCTAssertEqual(safeInt(Double.nan), 0)
        XCTAssertEqual(safeInt(Double.infinity), 0)
        XCTAssertEqual(safeInt(Double.greatestFiniteMagnitude), Int.max)
        XCTAssertEqual(safeInt(-Double.greatestFiniteMagnitude), Int.min)
    }

    func testPathFingerprintHandlesNonFinitePoints() {
        let element = makeElement(
            label: "Path",
            shape: .path([
                .move(to: AccessibilityPoint(x: .nan, y: .infinity)),
                .line(to: AccessibilityPoint(x: 10, y: 20)),
            ])
        )

        _ = element.contentFingerprint
    }

    private func makeElement(
        label: String,
        identifier: String? = nil,
        y: Double = 0,
        shape: AccessibilityShape? = nil
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label,
            label: label,
            value: nil,
            traits: AccessibilityTraits(),
            identifier: identifier,
            hint: nil,
            userInputLabels: nil,
            shape: shape ?? .frame(AccessibilityRect(x: 0, y: y, width: 320, height: 44)),
            activationPoint: .zero,
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
        )
    }
}

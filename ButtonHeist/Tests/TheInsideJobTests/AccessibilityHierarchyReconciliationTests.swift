#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

@MainActor
final class AccessibilityHierarchyReconciliationTests: XCTestCase {

    // MARK: - Fixtures

    private func makeElement(
        label: String,
        value: String? = nil,
        traits: UIAccessibilityTraits = .none,
        identifier: String? = nil,
        frame: CGRect = .zero,
        index: Int = 0
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label,
            label: label,
            value: value,
            traits: traits,
            identifier: identifier,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(frame),
            activationPoint: CGPoint(x: frame.midX, y: frame.midY),
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
        )
    }

    private func hierarchyElement(
        label: String,
        value: String? = nil,
        traits: UIAccessibilityTraits = .none,
        identifier: String? = nil,
        frame: CGRect = .zero,
        index: Int = 0
    ) -> AccessibilityHierarchy {
        .element(makeElement(label: label, value: value, traits: traits, identifier: identifier, frame: frame), traversalIndex: index)
    }

    // MARK: - Content Fingerprint: Basics

    func testSameContentSameFingerprint() {
        let element1 = makeElement(label: "Save", identifier: "save-btn")
        let element2 = makeElement(label: "Save", identifier: "save-btn")
        XCTAssertEqual(element1.contentFingerprint, element2.contentFingerprint)
    }

    func testDifferentLabelDifferentFingerprint() {
        let element1 = makeElement(label: "Save")
        let element2 = makeElement(label: "Cancel")
        XCTAssertNotEqual(element1.contentFingerprint, element2.contentFingerprint)
    }

    func testFingerprintIgnoresTraversalIndex() {
        // Same content at different traversal positions — must have same fingerprint.
        // This is the whole point: traversal index shifts on insert/remove.
        let node1 = hierarchyElement(label: "Row 5", identifier: "row-5", index: 5)
        let node2 = hierarchyElement(label: "Row 5", identifier: "row-5", index: 12)
        XCTAssertEqual(node1.contentFingerprint, node2.contentFingerprint)
    }

    func testFingerprintIncludesFrame() {
        let element1 = makeElement(label: "Cell", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let element2 = makeElement(label: "Cell", frame: CGRect(x: 0, y: 44, width: 320, height: 44))
        XCTAssertNotEqual(element1.contentFingerprint, element2.contentFingerprint)
    }

    func testFingerprintIncludesTraits() {
        let element1 = makeElement(label: "Title", traits: .header)
        let element2 = makeElement(label: "Title", traits: .button)
        XCTAssertNotEqual(element1.contentFingerprint, element2.contentFingerprint)
    }

    func testFingerprintIncludesValue() {
        let element1 = makeElement(label: "Slider", value: "50%")
        let element2 = makeElement(label: "Slider", value: "75%")
        XCTAssertNotEqual(element1.contentFingerprint, element2.contentFingerprint)
    }

    // MARK: - Hierarchy Content Fingerprint

    func testHierarchyFingerprintIgnoresTraversalIndex() {
        let node1 = hierarchyElement(label: "Item", index: 0)
        let node2 = hierarchyElement(label: "Item", index: 99)
        XCTAssertEqual(node1.contentFingerprint, node2.contentFingerprint)
    }

    func testContainerFingerprintIncludesChildren() {
        let container1: AccessibilityHierarchy = .container(
            AccessibilityContainer(type: .list, frame: .zero),
            children: [hierarchyElement(label: "A"), hierarchyElement(label: "B")]
        )
        let container2: AccessibilityHierarchy = .container(
            AccessibilityContainer(type: .list, frame: .zero),
            children: [hierarchyElement(label: "A"), hierarchyElement(label: "C")]
        )
        XCTAssertNotEqual(container1.contentFingerprint, container2.contentFingerprint)
    }

    // MARK: - Overlap Detection: Basics

    func testOverlapIdenticalSequences() {
        let fingerprints = [1, 2, 3, 4, 5]
        let result = findOverlap(accumulated: fingerprints, page: fingerprints)
        XCTAssertEqual(result.accumulatedStart, 0)
        XCTAssertEqual(result.pageStart, 0)
        XCTAssertEqual(result.length, 5)
    }

    func testOverlapNoMatch() {
        let result = findOverlap(accumulated: [1, 2, 3], page: [4, 5, 6])
        XCTAssertEqual(result.length, 0)
    }

    func testOverlapEmptyAccumulated() {
        let result = findOverlap(accumulated: [], page: [1, 2, 3])
        XCTAssertTrue(result.isEmpty)
    }

    func testOverlapEmptyPage() {
        let result = findOverlap(accumulated: [1, 2, 3], page: [])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Overlap Detection: Scroll Forward

    func testOverlapScrollForward() {
        // Accumulated: [A B C D E]
        // Page (scrolled forward): [D E F G]
        // Overlap: D E at accumulated[3..4], page[0..1]
        let accumulated = [1, 2, 3, 4, 5]
        let page = [4, 5, 6, 7]
        let result = findOverlap(accumulated: accumulated, page: page)
        XCTAssertEqual(result.accumulatedStart, 3)
        XCTAssertEqual(result.pageStart, 0)
        XCTAssertEqual(result.length, 2)
    }

    func testOverlapScrollBackward() {
        // Accumulated: [D E F G]
        // Page (scrolled backward): [A B C D E]
        // Overlap: D E at accumulated[0..1], page[3..4]
        let accumulated = [4, 5, 6, 7]
        let page = [1, 2, 3, 4, 5]
        let result = findOverlap(accumulated: accumulated, page: page)
        XCTAssertEqual(result.accumulatedStart, 0)
        XCTAssertEqual(result.pageStart, 3)
        XCTAssertEqual(result.length, 2)
    }

    func testOverlapLargeOverlapRegion() {
        // Accumulated: [A B C D E F G H]
        // Page: [C D E F G H I J]
        // Overlap: C D E F G H (6 elements)
        let accumulated = [1, 2, 3, 4, 5, 6, 7, 8]
        let page = [3, 4, 5, 6, 7, 8, 9, 10]
        let result = findOverlap(accumulated: accumulated, page: page)
        XCTAssertEqual(result.length, 6)
        XCTAssertEqual(result.accumulatedStart, 2)
        XCTAssertEqual(result.pageStart, 0)
    }

    func testOverlapMiddleInsertion() {
        // Accumulated: [A B C D E]
        // Page: [B C X D E] — X was inserted between C and D
        // The best contiguous overlap is either [B C] or [D E] (length 2)
        let accumulated = [1, 2, 3, 4, 5]
        let page = [2, 3, 99, 4, 5]
        let result = findOverlap(accumulated: accumulated, page: page)
        XCTAssertEqual(result.length, 2, "Best contiguous run is 2 elements")
    }

    // MARK: - Stitching: Empty Cases

    func testStitchEmptyAccumulated() {
        let page = [makeElement(label: "A"), makeElement(label: "B")]
        let result = stitchPage(accumulated: [], page: page)
        XCTAssertEqual(result.elements.count, 2)
        XCTAssertEqual(result.inserted.count, 2)
        XCTAssertEqual(result.previousCount, 0)
    }

    func testStitchEmptyPage() {
        let accumulated = [makeElement(label: "A"), makeElement(label: "B")]
        let result = stitchPage(accumulated: accumulated, page: [])
        XCTAssertEqual(result.elements.count, 2)
        XCTAssertTrue(result.inserted.isEmpty)
    }

    // MARK: - Stitching: Scroll Forward

    func testStitchScrollForward() {
        // Accumulated: [Row1 Row2 Row3]
        // Page (scrolled down): [Row2 Row3 Row4 Row5]
        // Result: [Row1 Row2 Row3 Row4 Row5]
        let row1 = makeElement(label: "Row 1", identifier: "r1", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let row2 = makeElement(label: "Row 2", identifier: "r2", frame: CGRect(x: 0, y: 44, width: 320, height: 44))
        let row3 = makeElement(label: "Row 3", identifier: "r3", frame: CGRect(x: 0, y: 88, width: 320, height: 44))
        let row4 = makeElement(label: "Row 4", identifier: "r4", frame: CGRect(x: 0, y: 132, width: 320, height: 44))
        let row5 = makeElement(label: "Row 5", identifier: "r5", frame: CGRect(x: 0, y: 176, width: 320, height: 44))

        let accumulated = [row1, row2, row3]
        let page = [row2, row3, row4, row5]

        let result = stitchPage(accumulated: accumulated, page: page)

        XCTAssertEqual(result.elements.count, 5, "All 5 unique rows present")
        XCTAssertEqual(result.overlap.length, 2, "Row2 and Row3 overlap")
        XCTAssertEqual(result.inserted.count, 2, "Row4 and Row5 are new")
        XCTAssertEqual(result.elements.map(\.label), ["Row 1", "Row 2", "Row 3", "Row 4", "Row 5"])
    }

    func testStitchScrollBackward() {
        // Accumulated: [Row3 Row4 Row5]
        // Page (scrolled up): [Row1 Row2 Row3 Row4]
        // Result: [Row1 Row2 Row3 Row4 Row5]
        let row1 = makeElement(label: "Row 1", identifier: "r1", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let row2 = makeElement(label: "Row 2", identifier: "r2", frame: CGRect(x: 0, y: 44, width: 320, height: 44))
        let row3 = makeElement(label: "Row 3", identifier: "r3", frame: CGRect(x: 0, y: 88, width: 320, height: 44))
        let row4 = makeElement(label: "Row 4", identifier: "r4", frame: CGRect(x: 0, y: 132, width: 320, height: 44))
        let row5 = makeElement(label: "Row 5", identifier: "r5", frame: CGRect(x: 0, y: 176, width: 320, height: 44))

        let accumulated = [row3, row4, row5]
        let page = [row1, row2, row3, row4]

        let result = stitchPage(accumulated: accumulated, page: page)

        XCTAssertEqual(result.elements.count, 5, "All 5 unique rows present")
        XCTAssertEqual(result.overlap.length, 2, "Row3 and Row4 overlap")
        XCTAssertEqual(result.inserted.count, 2, "Row1 and Row2 are new")
        XCTAssertEqual(result.elements.map(\.label), ["Row 1", "Row 2", "Row 3", "Row 4", "Row 5"])
    }

    // MARK: - Stitching: Multi-Page Assembly

    func testStitchThreePages() {
        // Simulate scrolling through 3 pages of a long list
        let rows = (0..<15).map { index in
            makeElement(
                label: "Row \(index)",
                identifier: "r\(index)",
                frame: CGRect(x: 0, y: Double(index) * 44, width: 320, height: 44)
            )
        }

        // Page 1: rows 0–4
        let page1 = Array(rows[0..<5])
        // Page 2: rows 3–8 (overlaps with page 1 at rows 3–4)
        let page2 = Array(rows[3..<9])
        // Page 3: rows 7–12 (overlaps with page 2 at rows 7–8)
        let page3 = Array(rows[7..<13])

        // Stitch page 1 into empty
        let after1 = stitchPage(accumulated: [], page: page1)
        XCTAssertEqual(after1.elements.count, 5)

        // Stitch page 2 into accumulated
        let after2 = stitchPage(accumulated: after1.elements, page: page2)
        XCTAssertEqual(after2.elements.count, 9, "Rows 0-8")
        XCTAssertEqual(after2.overlap.length, 2, "Rows 3-4 overlap")

        // Stitch page 3 into accumulated
        let after3 = stitchPage(accumulated: after2.elements, page: page3)
        XCTAssertEqual(after3.elements.count, 13, "Rows 0-12")
        XCTAssertEqual(after3.overlap.length, 2, "Rows 7-8 overlap")

        // Verify final ordering
        for index in 0..<13 {
            XCTAssertEqual(after3.elements[index].label, "Row \(index)")
        }
    }

    // MARK: - Stitching: No Overlap (Disjoint Pages)

    func testStitchDisjointPages() {
        let row1 = makeElement(label: "Row 1", identifier: "r1", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let row2 = makeElement(label: "Row 2", identifier: "r2", frame: CGRect(x: 0, y: 44, width: 320, height: 44))
        let row5 = makeElement(label: "Row 5", identifier: "r5", frame: CGRect(x: 0, y: 176, width: 320, height: 44))
        let row6 = makeElement(label: "Row 6", identifier: "r6", frame: CGRect(x: 0, y: 220, width: 320, height: 44))

        let accumulated = [row1, row2]
        let page = [row5, row6]

        let result = stitchPage(accumulated: accumulated, page: page)
        XCTAssertEqual(result.elements.count, 4, "Both sets appended")
        XCTAssertTrue(result.overlap.isEmpty, "No overlap found")
        XCTAssertEqual(result.inserted.count, 2)
    }

    // MARK: - Stitching: Complete Overlap

    func testStitchIdenticalPage() {
        let rows = (0..<5).map { index in
            makeElement(
                label: "Row \(index)",
                identifier: "r\(index)",
                frame: CGRect(x: 0, y: Double(index) * 44, width: 320, height: 44)
            )
        }

        let result = stitchPage(accumulated: rows, page: rows)
        XCTAssertEqual(result.elements.count, 5, "Same elements, no duplication")
        XCTAssertEqual(result.overlap.length, 5, "Full overlap")
        XCTAssertTrue(result.inserted.isEmpty, "Nothing new")
    }

    // MARK: - Stitching: Value Updates in Overlap

    func testStitchUpdatesValuesInOverlapRegion() {
        let row1 = makeElement(label: "Score", value: "100", identifier: "score", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let row2 = makeElement(label: "Lives", value: "3", identifier: "lives", frame: CGRect(x: 0, y: 44, width: 320, height: 44))

        let accumulated = [row1, row2]

        // Same elements but Lives value changed — but value is part of fingerprint,
        // so this is actually a different element. The overlap will not include it.
        let updatedRow2 = makeElement(label: "Lives", value: "2", identifier: "lives", frame: CGRect(x: 0, y: 44, width: 320, height: 44))
        let page = [row1, updatedRow2]

        let result = stitchPage(accumulated: accumulated, page: page)
        // row1 overlaps, updatedRow2 doesn't match row2's fingerprint
        // So overlap is length 1 (row1), then updatedRow2 is inserted after,
        // and original row2 is appended from accumulated
        XCTAssertGreaterThanOrEqual(result.overlap.length, 1)
    }

    // MARK: - Stitching: Insertion Detection

    func testStitchDetectsInsertedElement() {
        // Accumulated: [A B C]
        // Page: [B NEW C D]
        // Overlap on [B] or [C] — NEW is inserted, D is appended
        let elementA = makeElement(label: "A", identifier: "a", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let elementB = makeElement(label: "B", identifier: "b", frame: CGRect(x: 0, y: 44, width: 320, height: 44))
        let elementC = makeElement(label: "C", identifier: "c", frame: CGRect(x: 0, y: 88, width: 320, height: 44))
        let elementNew = makeElement(label: "NEW", identifier: "new", frame: CGRect(x: 0, y: 66, width: 320, height: 44))
        let elementD = makeElement(label: "D", identifier: "d", frame: CGRect(x: 0, y: 132, width: 320, height: 44))

        let accumulated = [elementA, elementB, elementC]
        let page = [elementB, elementNew, elementC, elementD]

        let result = stitchPage(accumulated: accumulated, page: page)
        XCTAssertGreaterThan(result.elements.count, 3, "At least one new element added")
        // The inserted list should contain at least NEW and D
        let insertedLabels = Set(result.inserted.map { $0.label ?? "" })
        XCTAssertTrue(insertedLabels.contains("NEW") || insertedLabels.contains("D"),
                       "Should detect new elements")
    }

    // MARK: - Hierarchy Convenience

    func testHierarchyStitchPage() {
        let accumulated: [AccessibilityHierarchy] = [
            hierarchyElement(label: "Row 0", identifier: "r0", frame: CGRect(x: 0, y: 0, width: 320, height: 44), index: 0),
            hierarchyElement(label: "Row 1", identifier: "r1", frame: CGRect(x: 0, y: 44, width: 320, height: 44), index: 1),
            hierarchyElement(label: "Row 2", identifier: "r2", frame: CGRect(x: 0, y: 88, width: 320, height: 44), index: 2),
        ]
        let page: [AccessibilityHierarchy] = [
            hierarchyElement(label: "Row 1", identifier: "r1", frame: CGRect(x: 0, y: 44, width: 320, height: 44), index: 1),
            hierarchyElement(label: "Row 2", identifier: "r2", frame: CGRect(x: 0, y: 88, width: 320, height: 44), index: 2),
            hierarchyElement(label: "Row 3", identifier: "r3", frame: CGRect(x: 0, y: 132, width: 320, height: 44), index: 3),
        ]

        let result = accumulated.stitchPage(from: page)
        XCTAssertEqual(result.elements.count, 4)
        XCTAssertEqual(result.elements.map(\.label), ["Row 0", "Row 1", "Row 2", "Row 3"])
    }

    // MARK: - Content-Space Stitching (Scroll-Invariant)

    func testContentSpaceFingerprintStableAcrossScrollPositions() {
        // Same element, different screen-space frames (scroll moved it), same content-space origin.
        // Window-space fingerprints would differ. Content-space fingerprints must match.
        let elementPage1 = makeElement(
            label: "Row 5", identifier: "r5",
            frame: CGRect(x: 0, y: 220, width: 320, height: 44)  // screen position on page 1
        )
        let elementPage2 = makeElement(
            label: "Row 5", identifier: "r5",
            frame: CGRect(x: 0, y: 132, width: 320, height: 44)  // screen position on page 2 (scrolled)
        )

        // Window-space: different (frames differ)
        XCTAssertNotEqual(elementPage1.contentFingerprint, elementPage2.contentFingerprint,
                          "Window-space fingerprints differ because frames differ")

        // Content-space: same (both at y=220 in content coordinates)
        let contentOrigin = CGPoint(x: 0, y: 220)
        XCTAssertEqual(
            elementPage1.fingerprint(contentSpaceOrigin: contentOrigin),
            elementPage2.fingerprint(contentSpaceOrigin: contentOrigin),
            "Content-space fingerprints match — same row regardless of scroll position"
        )
    }

    func testStitchWithContentSpaceOrigins() {
        // Simulate scrolling a table view forward by one row.
        // Screen-space frames shift, but content-space origins are stable.
        //
        // Content layout (fixed):
        //   Row 0: content y=0
        //   Row 1: content y=44
        //   Row 2: content y=88
        //   Row 3: content y=132
        //
        // Page 1 viewport (scroll offset 0): rows 0,1,2 visible
        //   Row 0 screen y=0, Row 1 screen y=44, Row 2 screen y=88
        //
        // Page 2 viewport (scroll offset 44): rows 1,2,3 visible
        //   Row 1 screen y=0, Row 2 screen y=44, Row 3 screen y=88
        //   (screen frames shifted because viewport moved)

        let page1 = [
            makeElement(label: "Row 0", identifier: "r0", frame: CGRect(x: 0, y: 0, width: 320, height: 44)),
            makeElement(label: "Row 1", identifier: "r1", frame: CGRect(x: 0, y: 44, width: 320, height: 44)),
            makeElement(label: "Row 2", identifier: "r2", frame: CGRect(x: 0, y: 88, width: 320, height: 44)),
        ]
        let page1Origins: [CGPoint?] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 44),
            CGPoint(x: 0, y: 88),
        ]

        let page2 = [
            makeElement(label: "Row 1", identifier: "r1", frame: CGRect(x: 0, y: 0, width: 320, height: 44)),   // screen y shifted!
            makeElement(label: "Row 2", identifier: "r2", frame: CGRect(x: 0, y: 44, width: 320, height: 44)),  // screen y shifted!
            makeElement(label: "Row 3", identifier: "r3", frame: CGRect(x: 0, y: 88, width: 320, height: 44)),
        ]
        let page2Origins: [CGPoint?] = [
            CGPoint(x: 0, y: 44),   // same content-space y as Row 1 in page 1
            CGPoint(x: 0, y: 88),   // same content-space y as Row 2 in page 1
            CGPoint(x: 0, y: 132),
        ]

        let result = stitchPage(
            accumulated: page1,
            accumulatedOrigins: page1Origins,
            page: page2,
            pageOrigins: page2Origins
        )

        XCTAssertEqual(result.elements.count, 4, "All 4 unique rows")
        XCTAssertEqual(result.elements.map(\.label), ["Row 0", "Row 1", "Row 2", "Row 3"])
        XCTAssertEqual(result.overlap.length, 2, "Row 1 and Row 2 overlap via content-space match")
        XCTAssertEqual(result.inserted.count, 1, "Only Row 3 is new")
    }

    func testWindowSpaceStitchFailsWithScrolledFrames() {
        // Same scenario as above but using window-space fingerprints (no content origins).
        // The overlap should fail because Row 1 at screen y=44 ≠ Row 1 at screen y=0.

        let page1 = [
            makeElement(label: "Row 0", identifier: "r0", frame: CGRect(x: 0, y: 0, width: 320, height: 44)),
            makeElement(label: "Row 1", identifier: "r1", frame: CGRect(x: 0, y: 44, width: 320, height: 44)),
            makeElement(label: "Row 2", identifier: "r2", frame: CGRect(x: 0, y: 88, width: 320, height: 44)),
        ]

        let page2 = [
            makeElement(label: "Row 1", identifier: "r1", frame: CGRect(x: 0, y: 0, width: 320, height: 44)),   // different screen y!
            makeElement(label: "Row 2", identifier: "r2", frame: CGRect(x: 0, y: 44, width: 320, height: 44)),  // different screen y!
            makeElement(label: "Row 3", identifier: "r3", frame: CGRect(x: 0, y: 88, width: 320, height: 44)),
        ]

        // Window-space stitch — no content origins, so frames are compared directly
        let result = stitchPage(accumulated: page1, page: page2)

        // The overlap should be 0 or very small because the screen-space frames don't match
        XCTAssertEqual(result.overlap.length, 0,
                       "Window-space frames shift with scroll — overlap detection fails")
    }
}
#endif

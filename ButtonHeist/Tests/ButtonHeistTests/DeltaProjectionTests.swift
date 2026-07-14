import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import Foundation
import ThePlans
import TheScore
import XCTest
@_spi(ButtonHeistInternals) @testable import ButtonHeist

final class DeltaProjectionTests: XCTestCase {

    func testManyLifecycleFactsPreserveFoldOrderAndPublicShape() throws {
        let elementCount = 16
        let removalOrder = [7, 2, 13, 0, 15, 5, 9, 1, 12, 4, 11, 6]
        let allElements = (0..<elementCount).map { index in
            makeTestHeistElement(
                label: "Row \(index)",
                identifier: "row_\(index)",
                traits: [.staticText]
            )
        }
        var remaining = Array(allElements.indices)
        var interfaces = [makeTestInterface(elements: allElements)]
        for removedIndex in removalOrder {
            remaining.removeAll { $0 == removedIndex }
            interfaces.append(makeTestInterface(elements: remaining.map { allElements[$0] }))
        }
        let trace = AccessibilityTrace(captures: interfaces.enumerated().map { index, interface in
            AccessibilityTrace.Capture(
                sequence: index + 1,
                interface: interface,
                context: AccessibilityTrace.Context(screenId: "rows")
            )
        })

        let projection = try XCTUnwrap(DeltaProjection(
            trace: trace,
            isComplete: false,
            profile: .full
        ))
        guard case .elementsChanged(let delta) = projection else {
            return XCTFail("Expected elementsChanged, got \(projection.kind)")
        }

        XCTAssertEqual(delta.edits.added.elements, [])
        XCTAssertEqual(delta.edits.updated.updates, [])
        XCTAssertEqual(
            delta.edits.removed.elements.compactMap(\.identifier),
            removalOrder.map { "row_\($0)" }
        )
        XCTAssertEqual(delta.metadata.captureEdge?.before.sequence, 1)
        XCTAssertEqual(delta.metadata.captureEdge?.after.sequence, interfaces.count)

        let compact = FenceResponse.compactDelta(projection, method: "activate")
        let expectedLines = ["activate: elements changed (4 elements)"] + removalOrder.map {
            "  - \"Row \($0)\" staticText id=\"row_\($0)\""
        }
        XCTAssertEqual(compact, expectedLines.joined(separator: "\n"))

        let json = try publicDeltaJSON(projection)
        let edits = try json.object("edits")
        XCTAssertEqual(try json.string("kind"), "elementsChanged")
        XCTAssertEqual(try json.int("elementCount"), 4)
        XCTAssertEqual(
            try edits.array("removed").map { try $0.string("identifier") },
            removalOrder.map { "row_\($0)" }
        )
        try edits.assertMissing("added")
        try edits.assertMissing("updated")
        try json.assertMissing("transient")
        try json.assertMissing("newInterface")
        try json.assertMissing("screen")
        try json.assertMissing("omitted")
    }

    func testDuplicateSemanticNodesProjectTheRecordAtTheFactPath() throws {
        let duplicate = makeTestAccessibilityElement(makeTestHeistElement(
            label: "Duplicate",
            identifier: "duplicate",
            traits: [.button]
        ))
        let firstPath = TreePath([0, 0, 0])
        let secondPath = TreePath([0, 1, 0])
        let before = duplicateInterface(
            duplicate: duplicate,
            firstPath: firstPath,
            secondPath: secondPath,
            includesSecond: true
        )
        let after = duplicateInterface(
            duplicate: duplicate,
            firstPath: firstPath,
            secondPath: secondPath,
            includesSecond: false
        )
        let projection = try XCTUnwrap(DeltaProjection(
            trace: makeTestTrace(before: before, after: after),
            isComplete: false,
            profile: .full
        ))
        guard case .elementsChanged(let delta) = projection else {
            return XCTFail("Expected elementsChanged, got \(projection.kind)")
        }

        let removed = try XCTUnwrap(delta.edits.removed.elements.first)
        XCTAssertEqual(delta.edits.removed.elements.count, 1)
        XCTAssertEqual(removed.identifier, "duplicate")
        XCTAssertEqual(removed.actions, [.custom("Archive")])
        XCTAssertTrue(delta.edits.added.elements.isEmpty)
        XCTAssertTrue(delta.edits.updated.updates.isEmpty)
    }

    func testScreenBoundaryDominatesEarlierElementFacts() throws {
        let cart = makeTestInterface(elements: [
            makeTestHeistElement(label: "Cart", identifier: "cart", traits: [.header]),
        ])
        let toast = makeTestHeistElement(label: "Saved", identifier: "saved", traits: [.staticText])
        let cartWithToast = makeTestInterface(elements: cart.projectedElements + [toast])
        let checkout = makeTestInterface(elements: [
            makeTestHeistElement(label: "Checkout", identifier: "checkout", traits: [.header]),
            makeTestHeistElement(label: "Pay", identifier: "pay", traits: [.button]),
        ])
        let trace = AccessibilityTrace(captures: [
            AccessibilityTrace.Capture(
                sequence: 1,
                interface: cart,
                context: AccessibilityTrace.Context(screenId: "cart")
            ),
            AccessibilityTrace.Capture(
                sequence: 2,
                interface: cartWithToast,
                context: AccessibilityTrace.Context(screenId: "cart")
            ),
            AccessibilityTrace.Capture(
                sequence: 3,
                interface: checkout,
                context: AccessibilityTrace.Context(screenId: "checkout"),
                transition: makeTestScreenChangedTransition()
            ),
        ])

        let projection = try XCTUnwrap(DeltaProjection(
            trace: trace,
            isComplete: false,
            profile: .full
        ))
        guard case .screenChanged(let delta) = projection else {
            return XCTFail("Expected screenChanged, got \(projection.kind)")
        }

        XCTAssertEqual(delta.screen.elements.compactMap(\.identifier), ["checkout", "pay"])
        XCTAssertEqual(delta.metadata.transient.elements.compactMap(\.identifier), ["saved"])

        let json = try publicDeltaJSON(projection)
        XCTAssertEqual(try json.string("kind"), "screenChanged")
        XCTAssertEqual(try json.int("elementCount"), 2)
        XCTAssertEqual(try json.object("screen").int("elementCount"), 2)
        try json.assertMissing("edits")
        try json.assertMissing("newInterface")
    }

    private func duplicateInterface(
        duplicate: AccessibilityElement,
        firstPath: TreePath,
        secondPath: TreePath,
        includesSecond: Bool
    ) -> Interface {
        let secondChildren: [AccessibilityHierarchy] = includesSecond
            ? [.element(duplicate, traversalIndex: 1)]
            : []
        let root = makeTestAccessibilityContainer(type: .list)
        let group = makeTestAccessibilityContainer(type: .semanticGroup(label: "Group", value: nil))
        let tree: [AccessibilityHierarchy] = [
            .container(root, children: [
                .container(group, children: [
                    .element(duplicate, traversalIndex: 0),
                ]),
                .container(group, children: secondChildren),
            ]),
        ]
        var annotations = [
            InterfaceElementAnnotation(path: firstPath, actions: [.activate]),
        ]
        if includesSecond {
            annotations.append(InterfaceElementAnnotation(path: secondPath, actions: [.custom("Archive")]))
        }
        let annotationByPath = InterfaceAnnotations(elements: annotations).elementByPath
        return Interface(
            timestamp: Date(timeIntervalSince1970: includesSecond ? 1 : 2),
            projecting: tree,
            elementMetadata: { path, _, _ in
                annotationByPath[path].map { InterfaceElementProjectionMetadata(actions: $0.actions) }
            },
            containerMetadata: { _, _ in nil }
        )
    }

    private func publicDeltaJSON(_ projection: DeltaProjection) throws -> JSONProbe {
        try JSONProbe(data: JSONEncoder().encode(PublicDelta(
            projection: projection,
            screenPolicy: .screenSummary
        )))
    }
}

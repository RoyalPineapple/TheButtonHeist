import ButtonHeistTestSupport
import XCTest
import ThePlans
import AccessibilitySnapshotModel
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

extension TheFenceCompactFormattingContractTests {

    func testElementsChangedActionOutputIncludesConcreteElementDelta() throws {
        let added = makeTestHeistElement(
            label: "Barbaresco",
            value: "$55.00",
            identifier: "wine_barbaresco",
            traits: [.staticText]
        )
        let unchanged = (0..<11).map { index in
            makeTestHeistElement(label: "Row \(index)", identifier: "row_\(index)")
        }
        let trace = makeTestTrace(
            before: makeTestInterface(elements: unchanged),
            after: makeTestInterface(elements: unchanged + [added])
        )
        let response = FenceResponse.action(
            command: .activate,
            result: HeistResultFixture.actionResult(
                traceEvidence: makeTestTraceEvidence(trace, completeness: .incomplete)
            )
        )

        let delta = try publicJSONProbe(response).object("delta")
        let addedJSON = try delta.object("edits").array("added")
        let digest = try delta.object("interactionDigest")
        let compact = response.compactFormatted()
        let human = response.humanFormatted()

        XCTAssertEqual(try delta.string("kind"), "elementsChanged")
        XCTAssertEqual(try digest.int("nodeCountBefore"), 11)
        XCTAssertEqual(try digest.int("nodeCountAfter"), 12)
        XCTAssertEqual(try digest.bool("nodeCountChanged"), true)
        XCTAssertEqual(try digest.bool("elementSetChanged"), true)
        XCTAssertEqual(try addedJSON.first?.string("label"), "Barbaresco")
        XCTAssertEqual(try addedJSON.first?.string("identifier"), "wine_barbaresco")
        XCTAssertTrue(compact.contains(#"+ "Barbaresco":"$55.00" staticText id="wine_barbaresco""#), compact)
        XCTAssertTrue(human.contains(#"+ "Barbaresco":"$55.00" staticText id="wine_barbaresco""#), human)
    }

    func testDeltaFoldsFastElementLifecycleWithoutEndpointDiffing() throws {
        let toast = makeTestHeistElement(label: "Saved", identifier: "saved_toast", traits: [.staticText])
        let empty = makeTestInterface(elements: [])
        let visible = makeTestInterface(elements: [toast])
        let trace = AccessibilityTrace(first: empty)
            .appending(visible)
            .appending(empty)
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(
                payload: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
            )
        )

        let delta = try publicJSONProbe(response).object("delta")
        let compact = response.compactFormatted()

        XCTAssertEqual(try delta.string("kind"), "elementsChanged")
        XCTAssertEqual(try delta.array("transient").first?.string("identifier"), "saved_toast")
        try delta.assertMissing("edits")
        XCTAssertTrue(compact.contains("activate: elements changed"), compact)
        XCTAssertTrue(compact.contains(#"+- "Saved" staticText id="saved_toast""#), compact)
    }

    func testNotificationOnlyDeltaPreservesDeduplicatedTemporalEvidence() throws {
        let interface = makeTestInterface(elementCount: 1)
        let first = AccessibilityNotificationEvidence(
            sequence: 7,
            kind: .elementChanged(.value),
            timestamp: Date(timeIntervalSince1970: 7),
            notificationData: .none,
            associatedElement: .none
        )
        let second = AccessibilityNotificationEvidence(
            sequence: 8,
            kind: .elementChanged(.layout),
            timestamp: Date(timeIntervalSince1970: 8),
            notificationData: .none,
            associatedElement: .none
        )
        let trace = AccessibilityTrace(first: interface)
            .appending(
                interface,
                transition: AccessibilityTrace.Transition(accessibilityNotifications: [first])
            )
            .appending(
                interface,
                transition: AccessibilityTrace.Transition(accessibilityNotifications: [first, second])
            )
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(
                payload: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
            )
        )

        let delta = try publicJSONProbe(response).object("delta")
        let notifications = try delta.array("accessibilityNotifications")
        let compact = response.compactFormatted()

        XCTAssertEqual(try delta.string("kind"), "elementsChanged")
        try delta.assertMissing("edits")
        XCTAssertEqual(try notifications.map { try $0.int("sequence") }, [7, 8])
        let kinds = try notifications.map { try $0.object("kind") }
        XCTAssertEqual(try kinds.map { try $0.string("type") }, ["elementChanged", "elementChanged"])
        XCTAssertEqual(try kinds.map { try $0.string("notification") }, ["value", "layout"])
        XCTAssertTrue(compact.contains("accessibility notification elementChanged(value) #7"), compact)
        XCTAssertTrue(compact.contains("accessibility notification elementChanged(layout) #8"), compact)
    }
}

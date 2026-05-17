import XCTest
@testable import TheScore

final class AccessibilityTraceTests: XCTestCase {

    func testCaptureCarriesFullInterfaceAndStableHash() throws {
        let interface = makeInterface(timestamp: Date(timeIntervalSince1970: 1))
        let sameContent = makeInterface(timestamp: Date(timeIntervalSince1970: 2))

        let capture = AccessibilityTrace.Capture(sequence: 3, interface: interface, parentHash: "sha256:parent")
        let sameHash = AccessibilityTrace.Capture.hash(sameContent)

        XCTAssertEqual(capture.hash, sameHash)
        XCTAssertEqual(capture.parentHash, "sha256:parent")
        XCTAssertEqual(capture.interface.tree, interface.tree)
        XCTAssertEqual(capture.summary, "Settings — 1 button (2 elements)")
    }

    func testCaptureHashIncludesSemanticContext() throws {
        let interface = makeInterface()
        let unfocused = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(focusedElementId: nil, keyboardVisible: false)
        )
        let focused = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(focusedElementId: "save", keyboardVisible: true)
        )

        XCTAssertNotEqual(unfocused.hash, focused.hash)
    }

    func testTraceCanLookupCaptureByHash() throws {
        let first = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Home"))
        let second = AccessibilityTrace.Capture(sequence: 2, interface: makeInterface(label: "Settings"), parentHash: first.hash)
        let trace = AccessibilityTrace(captures: [first, second])

        XCTAssertEqual(trace.capture(hash: second.hash)?.hash, second.hash)
        XCTAssertEqual(trace.receipts.map(\.hash), [first.hash, second.hash])
        XCTAssertEqual(trace.receipts[1].parentHash, first.hash)
        XCTAssertTrue(trace.isLinearChain)
    }

    func testAppendingCreatesSingleLinkedList() throws {
        let first = makeInterface(label: "Home")
        let second = makeInterface(label: "Settings")

        let trace = AccessibilityTrace(first: first).appending(second)

        XCTAssertEqual(trace.captures.map(\.sequence), [1, 2])
        XCTAssertNil(trace.captures[0].parentHash)
        XCTAssertEqual(trace.captures[1].parentHash, trace.captures[0].hash)
        XCTAssertTrue(trace.isLinearChain)
    }

    func testTraceConstructionNormalizesToSingleLinkedList() throws {
        let first = AccessibilityTrace.Capture(
            sequence: 99,
            interface: makeInterface(label: "Home"),
            parentHash: "sha256:bad",
            context: AccessibilityTrace.Context(focusedElementId: "title")
        )
        let second = AccessibilityTrace.Capture(sequence: 42, interface: makeInterface(label: "Settings"), parentHash: "sha256:fork")

        let trace = AccessibilityTrace(captures: [first, second])

        XCTAssertEqual(trace.captures.map(\.sequence), [1, 2])
        XCTAssertNil(trace.captures[0].parentHash)
        XCTAssertEqual(trace.captures[1].parentHash, trace.captures[0].hash)
        XCTAssertEqual(trace.captures[0].context.focusedElementId, "title")
        XCTAssertTrue(trace.isLinearChain)
    }

    private func makeInterface(label: String = "Settings", timestamp: Date = Date(timeIntervalSince1970: 0)) -> Interface {
        Interface(timestamp: timestamp, tree: [
            .element(makeElement(heistId: "title", label: label, traits: [.header])),
            .element(makeElement(heistId: "save", label: "Save")),
        ])
    }

    private func makeElement(
        heistId: String,
        label: String,
        traits: [HeistTrait] = [.button]
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label,
            label: label,
            value: nil,
            identifier: nil,
            traits: traits,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: [.activate]
        )
    }
}

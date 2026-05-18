import XCTest
@testable import TheScore

final class AccessibilityTraceHistoryTests: XCTestCase {

    func testAppendNormalizesCaptureSequenceAndParentLinks() {
        var history = AccessibilityTrace.History()
        let first = AccessibilityTrace.Capture(
            sequence: 99,
            interface: makeInterface(label: "Home"),
            parentHash: "sha256:fork",
            context: AccessibilityTrace.Context(focusedElementId: "title")
        )
        let second = AccessibilityTrace.Capture(
            sequence: 42,
            interface: makeInterface(label: "Settings"),
            parentHash: "sha256:other-fork",
            transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
        )

        let firstRef = history.append(first)
        let secondRef = history.append(second)

        XCTAssertEqual(firstRef.sequence, 1)
        XCTAssertEqual(secondRef.sequence, 2)
        XCTAssertEqual(history.captures.map(\.sequence), [1, 2])
        XCTAssertNil(history.captures[0].parentHash)
        XCTAssertEqual(history.captures[1].parentHash, history.captures[0].hash)
        XCTAssertEqual(history.captures[0].context.focusedElementId, "title")
        XCTAssertEqual(history.captures[1].transition.screenChangeReason, "primaryHeaderChanged")
        XCTAssertEqual(history.latestRef, secondRef)
    }

    func testAppendInterfaceCreatesLatestCaptureAndSingleCaptureTrace() throws {
        var history = AccessibilityTrace.History()

        let ref = history.append(
            interface: makeInterface(label: "Home"),
            context: AccessibilityTrace.Context(screenId: "home")
        )
        let trace = try XCTUnwrap(history.trace(from: nil, to: ref))

        XCTAssertEqual(history.latestRef, ref)
        XCTAssertEqual(history.latestCapture?.context.screenId, "home")
        XCTAssertEqual(trace.captures.count, 1)
        XCTAssertEqual(trace.captures[0].hash, ref.hash)
        XCTAssertNil(history.delta(from: nil, to: ref))
    }

    func testEndpointTraceAndDeltaDeriveFromTraceEndpointProjection() throws {
        var history = AccessibilityTrace.History()
        let startRef = history.append(interface: makeInterface(label: "Menu"))
        let endRef = history.append(interface: makeInterface(label: "Checkout"))

        let trace = try XCTUnwrap(history.trace(from: startRef, to: endRef))
        let delta = try XCTUnwrap(history.delta(from: startRef, to: endRef))

        XCTAssertEqual(trace.captures.count, 2)
        XCTAssertEqual(delta, trace.captureEndpointDelta)
        XCTAssertEqual(delta.captureEdge?.before.hash, trace.captures[0].hash)
        XCTAssertEqual(delta.captureEdge?.after.hash, trace.captures[1].hash)
    }

    func testDropAfterDeliveryRetainsLatestCaptureAsNextDeltaBaseline() throws {
        var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
        _ = history.append(interface: makeInterface(label: "Home"))
        _ = history.append(interface: makeInterface(label: "Menu"))
        let deliveredRef = history.append(interface: makeInterface(label: "Review"))

        history.markDelivered(through: deliveredRef)

        XCTAssertEqual(history.captures.count, 1)
        XCTAssertEqual(history.captures[0].hash, deliveredRef.hash)
        XCTAssertEqual(history.captures[0].sequence, deliveredRef.sequence)
        XCTAssertNil(history.captures[0].parentHash)
        XCTAssertEqual(history.capture(ref: deliveredRef), history.captures[0])

        let baselineRef = try XCTUnwrap(history.latestRef)
        let latestRef = history.append(interface: makeInterface(label: "Checkout"))
        let delta = try XCTUnwrap(history.delta(from: baselineRef, to: latestRef))

        XCTAssertEqual(history.captures.map(\.sequence), [deliveredRef.sequence, latestRef.sequence])
        XCTAssertEqual(delta, history.trace(from: baselineRef, to: latestRef)?.captureEndpointDelta)
        XCTAssertEqual(delta.captureEdge?.before.hash, baselineRef.hash)
        XCTAssertEqual(delta.captureEdge?.after.hash, latestRef.hash)
    }

    func testDropAfterDeliveryRetainsDeliveredBoundaryAsOnlyDeliveredBaseline() {
        var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
        _ = history.append(interface: makeInterface(label: "Home"))
        let deliveredRef = history.append(interface: makeInterface(label: "Menu"))
        let pendingRef = history.append(interface: makeInterface(label: "Checkout"))

        history.markDelivered(through: deliveredRef)

        XCTAssertEqual(history.captures.count, 2)
        XCTAssertEqual(history.captures.map(\.hash), [deliveredRef.hash, pendingRef.hash])
        XCTAssertEqual(history.captures.map(\.sequence), [deliveredRef.sequence, pendingRef.sequence])
        XCTAssertNil(history.captures[0].parentHash)
        XCTAssertEqual(history.captures[1].parentHash, history.captures[0].hash)
        XCTAssertEqual(history.capture(ref: deliveredRef), history.captures[0])
        XCTAssertEqual(history.capture(ref: pendingRef), history.captures[1])
        XCTAssertEqual(history.latestRef, AccessibilityTrace.CaptureRef(capture: history.captures[1]))
    }

    func testDropAfterDeliveryWithNilRefKeepsOnlyLatestCapture() {
        var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
        _ = history.append(interface: makeInterface(label: "Home"))
        let latestRef = history.append(interface: makeInterface(label: "Menu"))

        history.markDelivered(through: nil)

        XCTAssertEqual(history.captures.count, 1)
        XCTAssertEqual(history.captures[0].hash, latestRef.hash)
        XCTAssertEqual(history.captures[0].sequence, latestRef.sequence)
        XCTAssertNil(history.captures[0].parentHash)
        XCTAssertEqual(history.capture(ref: latestRef), history.captures[0])
    }

    func testPersistForSessionRetainsFullChainAfterDeliveryMarkers() {
        var history = AccessibilityTrace.History(retention: .persistForSession)
        _ = history.append(interface: makeInterface(label: "Home"))
        let middleRef = history.append(interface: makeInterface(label: "Menu"))
        let latestRef = history.append(interface: makeInterface(label: "Checkout"))

        history.markDelivered(through: middleRef)
        history.markDelivered(through: nil)

        XCTAssertEqual(history.captures.count, 3)
        XCTAssertEqual(history.captures.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(history.latestRef, latestRef)
        XCTAssertEqual(history.captures[1].parentHash, history.captures[0].hash)
        XCTAssertEqual(history.captures[2].parentHash, history.captures[1].hash)
    }

    func testPruneRetainingRefsRelinksRetainedCapturesWithoutInvalidatingRefs() {
        var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
        _ = history.append(interface: makeInterface(label: "Home"))
        let retainedRef = history.append(interface: makeInterface(label: "Menu"))
        let droppedRef = history.append(interface: makeInterface(label: "Review"))
        let latestRef = history.append(interface: makeInterface(label: "Checkout"))

        history.prune(retaining: [retainedRef])

        XCTAssertEqual(history.captures.map(\.hash), [retainedRef.hash, latestRef.hash])
        XCTAssertEqual(history.captures.map(\.sequence), [retainedRef.sequence, latestRef.sequence])
        XCTAssertNil(history.captures[0].parentHash)
        XCTAssertEqual(history.captures[1].parentHash, history.captures[0].hash)
        XCTAssertEqual(history.capture(ref: retainedRef), history.captures[0])
        XCTAssertNil(history.capture(ref: droppedRef))
        XCTAssertEqual(history.capture(ref: latestRef), history.captures[1])
    }

    func testResetClearsEverything() {
        var history = AccessibilityTrace.History()
        let ref = history.append(interface: makeInterface(label: "Home"))

        history.reset()

        XCTAssertTrue(history.captures.isEmpty)
        XCTAssertNil(history.latestCapture)
        XCTAssertNil(history.latestRef)
        XCTAssertNil(history.capture(ref: ref))
        XCTAssertNil(history.trace(from: nil, to: nil))
        XCTAssertNil(history.delta(from: nil, to: nil))
    }

    func testUnknownRefsReturnNil() {
        var history = AccessibilityTrace.History()
        let firstRef = history.append(interface: makeInterface(label: "Home"))
        let secondRef = history.append(interface: makeInterface(label: "Menu"))
        let unknownHash = AccessibilityTrace.CaptureRef(sequence: 1, hash: "sha256:missing")
        let unknownSequence = AccessibilityTrace.CaptureRef(sequence: 99, hash: firstRef.hash)

        XCTAssertNil(history.capture(ref: unknownHash))
        XCTAssertNil(history.capture(ref: unknownSequence))
        XCTAssertNil(history.trace(from: unknownHash, to: secondRef))
        XCTAssertNil(history.trace(from: firstRef, to: unknownHash))
        XCTAssertNil(history.delta(from: unknownHash, to: secondRef))
        XCTAssertNil(history.trace(from: secondRef, to: firstRef))
    }

    private func makeInterface(label: String) -> Interface {
        Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [
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

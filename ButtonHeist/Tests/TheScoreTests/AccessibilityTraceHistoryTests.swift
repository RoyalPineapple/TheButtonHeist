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

    func testPendingTraceViewsAreDerivedFromRetainedCaptures() throws {
        var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
        let sourceTrace = makeTrace(before: "Menu", after: "Checkout")

        let pending = try XCTUnwrap(history.enqueuePendingTrace(sourceTrace, limit: 20))

        XCTAssertEqual(history.pendingTraceCount, 1)
        XCTAssertEqual(pending.index, 0)
        XCTAssertEqual(pending.cursor, history.pendingCursor(at: 0))
        XCTAssertEqual(pending.trace, history.pendingTrace(at: 0)?.trace)
        XCTAssertEqual(pending.delta, pending.trace.backgroundDelta)
        XCTAssertEqual(pending.trace.captures.map(\.hash), sourceTrace.captures.map(\.hash))
        XCTAssertEqual(history.elementLookup(captureRef: pending.firstRef)["title"]?.label, "Menu")
    }

    func testPendingTraceLimitDropsOldestButRetainsLatestPendingTrace() throws {
        var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
        let first = try XCTUnwrap(history.enqueuePendingTrace(makeTrace(before: "Home", after: "Menu"), limit: 1))
        let second = try XCTUnwrap(history.enqueuePendingTrace(makeTrace(before: "Review", after: "Checkout"), limit: 1))

        XCTAssertEqual(history.pendingTraceCount, 1)
        XCTAssertNil(first.firstRef.flatMap { history.capture(ref: $0) })
        XCTAssertNil(first.lastRef.flatMap { history.capture(ref: $0) })
        XCTAssertEqual(history.pendingTrace(at: 0)?.trace.captures.map(\.hash), second.trace.captures.map(\.hash))
        XCTAssertEqual(history.latestRef, second.lastRef)
        XCTAssertEqual(history.captures.map(\.hash), second.trace.captures.map(\.hash))
    }

    func testPendingTraceIsDrainedAsProjectionAndMarksDelivered() throws {
        var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
        let sourceTrace = AccessibilityTrace(captures: [
            AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Loading")),
            AccessibilityTrace.Capture(
                sequence: 2,
                interface: makeInterface(label: "Done"),
                transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
            ),
        ])

        let pendingTrace = try XCTUnwrap(history.enqueuePendingTrace(sourceTrace))
        let drained = try XCTUnwrap(history.drainPendingTrace())

        XCTAssertEqual(drained.captures.map(\.hash), pendingTrace.cursor.captureRefs.map(\.hash))
        XCTAssertEqual(history.pendingTraceCount, 0)
        XCTAssertEqual(history.captures.map(\.hash), [try XCTUnwrap(pendingTrace.lastRef).hash])
    }

    func testMarkDeliveredDoesNotRegressDeliveredBoundary() throws {
        var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
        let pendingTrace = try XCTUnwrap(history.enqueuePendingTrace(makeTrace(before: "Menu", after: "Checkout")))
        let latestRef = history.append(interface: makeInterface(label: "Receipt"))

        history.markDelivered(through: latestRef)
        _ = history.removePendingTrace(at: 0)
        history.markDelivered(through: pendingTrace.firstRef)

        XCTAssertNil(pendingTrace.firstRef.flatMap { history.capture(ref: $0) })
        XCTAssertNil(pendingTrace.lastRef.flatMap { history.capture(ref: $0) })
        XCTAssertEqual(history.capture(ref: latestRef), history.latestCapture)
        XCTAssertEqual(history.captures.map(\.hash), [latestRef.hash])
    }

    func testRetentionRetainsPendingTraceRefsWithoutExternalRetainedSet() throws {
        var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
        let sourceTrace = AccessibilityTrace(captures: [
            AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu")),
            AccessibilityTrace.Capture(
                sequence: 2,
                interface: makeInterface(label: "Checkout"),
                transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
            ),
        ])

        let pendingTrace = try XCTUnwrap(history.enqueuePendingTrace(sourceTrace))
        let projectedTrace = try XCTUnwrap(history.trace(cursor: pendingTrace.cursor))

        XCTAssertEqual(projectedTrace.captures.map(\.hash), pendingTrace.cursor.captureRefs.map(\.hash))
        XCTAssertEqual(history.pendingTraceCount, 1)
        XCTAssertEqual(history.pendingTraces(startingAt: 0).map(\.index), [0])
    }

    func testPendingTraceLimitDropsOldestBoundary() throws {
        var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
        let firstPendingTrace = try XCTUnwrap(history.enqueuePendingTrace(
            AccessibilityTrace(first: makeInterface(label: "First")),
            limit: 1
        ))
        let secondPendingTrace = try XCTUnwrap(history.enqueuePendingTrace(
            AccessibilityTrace(first: makeInterface(label: "Second")),
            limit: 1
        ))

        XCTAssertEqual(history.pendingTraceCount, 1)
        XCTAssertNil(history.trace(cursor: firstPendingTrace.cursor))
        XCTAssertNotNil(history.trace(cursor: secondPendingTrace.cursor))
    }

    func testResetClearsEverything() {
        var history = AccessibilityTrace.History()
        let ref = history.append(interface: makeInterface(label: "Home"))
        _ = history.enqueuePendingTrace(AccessibilityTrace(first: makeInterface(label: "Pending")))
        history.markDelivered(through: ref)

        history.reset()

        XCTAssertTrue(history.captures.isEmpty)
        XCTAssertEqual(history.pendingTraceCount, 0)
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

    private func makeTrace(before: String, after: String) -> AccessibilityTrace {
        AccessibilityTrace(captures: [
            AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: before)),
            AccessibilityTrace.Capture(sequence: 2, interface: makeInterface(label: after)),
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

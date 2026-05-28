import XCTest

@testable import ButtonHeist
import TheScore

final class FenceBackgroundAccessibilityLifecycleTests: XCTestCase {
    @ButtonHeistActor
    func testSnapshotTracksBeginEndAndReset() async {
        let lifecycle = FenceBackgroundAccessibilityLifecycle()

        XCTAssertEqual(
            lifecycle.snapshot,
            FenceBackgroundAccessibilitySnapshot(
                pendingTraceCount: 0,
                latestRef: nil,
                retention: .dropAfterDelivery
            )
        )

        lifecycle.beginRecordingRetention()
        XCTAssertEqual(lifecycle.snapshot.retention, .persistForSession)

        lifecycle.enqueue(makeBackgroundScreenChangedTrace(elementCount: 2))
        XCTAssertEqual(lifecycle.snapshot.pendingTraceCount, 1)
        XCTAssertNotNil(lifecycle.snapshot.latestRef)

        lifecycle.endRecordingRetention()
        XCTAssertEqual(lifecycle.snapshot.retention, .dropAfterDelivery)

        lifecycle.reset()
        XCTAssertEqual(
            lifecycle.snapshot,
            FenceBackgroundAccessibilitySnapshot(
                pendingTraceCount: 0,
                latestRef: nil,
                retention: .dropAfterDelivery
            )
        )
        XCTAssertNil(lifecycle.drainTrace())
    }

    @ButtonHeistActor
    func testEndRecordingRetentionDropsDeliveredStaleCaptures() async {
        let lifecycle = FenceBackgroundAccessibilityLifecycle()
        lifecycle.beginRecordingRetention()

        let oldRef = lifecycle.append(interface: makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "old", label: "Old"),
        ]))
        let latestRef = lifecycle.append(interface: makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "latest", label: "Latest"),
        ]))

        lifecycle.markDelivered(through: latestRef)
        XCTAssertEqual(lifecycle.elementLookup(captureRef: oldRef)["old"]?.label, "Old")

        lifecycle.endRecordingRetention()

        XCTAssertNil(lifecycle.elementLookup(captureRef: oldRef)["old"])
        XCTAssertEqual(lifecycle.elementLookup(captureRef: latestRef)["latest"]?.label, "Latest")
    }

    @ButtonHeistActor
    func testQueuedExpectationConsumesOnlyMatchingTraceAndResetClearsRemainder() async throws {
        let lifecycle = FenceBackgroundAccessibilityLifecycle()
        lifecycle.enqueue(makeBackgroundElementsChangedTrace(elementCount: 2))
        lifecycle.enqueue(makeBackgroundScreenChangedTrace(elementCount: 7))

        let match = try XCTUnwrap(lifecycle.consumeFirstTraceMatchingExpectation(.screenChanged))

        XCTAssertEqual(match.result.accessibilityDelta?.isScreenChanged, true)
        XCTAssertEqual(match.validation.met, true)
        XCTAssertEqual(lifecycle.snapshot.pendingTraceCount, 1)
        XCTAssertEqual(lifecycle.drainTrace()?.backgroundDeltaProjection?.kindRawValue, "elementsChanged")

        lifecycle.enqueue(makeBackgroundScreenChangedTrace(elementCount: 3))
        lifecycle.reset()

        XCTAssertEqual(lifecycle.snapshot.pendingTraceCount, 0)
        XCTAssertNil(lifecycle.drainTrace())
    }
}

#if canImport(UIKit)
import UIKit
import XCTest

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import ThePlans
@testable import TheScore

private final class RawEvidenceAdjustableView: UIView {
    private(set) var incrementCount = 0

    override func accessibilityIncrement() {
        incrementCount += 1
    }
}

@MainActor
final class RawParserEvidenceAdmissionTests: XCTestCase {

    private var brains: TheBrains!

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
    }

    override func tearDown() async throws {
        brains = nil
        try await super.tearDown()
    }

    func testRawRefreshCannotAdmitNewTargetForAction() async throws {
        let settledA = observation(label: "Screen A", heistId: "screen_a")
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(settledA)

        let rawObject = RawEvidenceAdjustableView()
        let rawB = observation(label: "Screen B", heistId: "screen_b", object: rawObject)
        brains.stash.nextVisibleRefreshScreenForTesting = rawB
        let screenBTarget = try resolvedTarget(label: "Screen B")

        let beforeRefresh = await brains.actions.executeIncrement(screenBTarget)

        XCTAssertFalse(beforeRefresh.success)
        XCTAssertEqual(brains.stash.latestObservation.orderedElements.first?.element.label, "Screen A")
        XCTAssertEqual(rawObject.incrementCount, 0)

        XCTAssertNotNil(brains.stash.refreshLiveCapture())
        XCTAssertEqual(brains.stash.latestObservation.orderedElements.first?.element.label, "Screen B")
        XCTAssertEqual(brains.stash.interfaceTree.orderedElements.first?.element.label, "Screen A")
        XCTAssertNil(brains.stash.resolveVisibleTarget(screenBTarget).resolved)

        let afterRefresh = await brains.actions.executeIncrement(screenBTarget)

        XCTAssertFalse(afterRefresh.success)
        XCTAssertEqual(rawObject.incrementCount, 0)
    }

    func testSettledIdentityUsesOnlyRefAndGeometryFromRawRefresh() async throws {
        let heistId: HeistId = "shared_control"
        let sharedControlTarget = try resolvedTarget(label: "Shared Control")
        let settledFrame = CGRect(x: 10, y: 20, width: 100, height: 44)
        let settled = observation(
            label: "Shared Control",
            value: "settled",
            heistId: heistId,
            frame: settledFrame
        )
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(settled)

        let refreshedObject = RawEvidenceAdjustableView()
        let refreshedFrame = CGRect(x: 80, y: 160, width: 180, height: 52)
        brains.stash.nextVisibleRefreshScreenForTesting = observation(
            label: "Shared Control",
            value: "raw",
            heistId: heistId,
            object: refreshedObject,
            frame: refreshedFrame
        )
        XCTAssertNotNil(brains.stash.refreshLiveCapture())

        let semanticTarget = try XCTUnwrap(
            brains.stash.resolveVisibleTarget(sharedControlTarget).resolved
        )
        XCTAssertEqual(semanticTarget.element.value, "settled")
        XCTAssertEqual(semanticTarget.element.bhFrame, settledFrame)

        guard case .resolved(let liveTarget) = brains.stash.resolveLiveActionTarget(for: semanticTarget) else {
            return XCTFail("Expected refreshed live evidence for the settled identity")
        }
        XCTAssertTrue(liveTarget.object === refreshedObject)
        XCTAssertEqual(liveTarget.treeElement.heistId, heistId)
        XCTAssertEqual(liveTarget.element.value, "settled")
        XCTAssertEqual(liveTarget.frame, refreshedFrame)

        let result = await brains.actions.executeIncrement(sharedControlTarget)

        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(refreshedObject.incrementCount, 1)
        XCTAssertEqual(
            brains.stash.resolveVisibleTarget(sharedControlTarget).resolved?.element.value,
            "settled"
        )
    }

    func testMatchingRawIdentityCannotStealResolvedAction() throws {
        let committedId: HeistId = "committed_control"
        let rawId: HeistId = "raw_control"
        let sharedControlTarget = try resolvedTarget(label: "Shared Control")
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Shared Control", heistId: committedId)
        )
        let resolvedActionTarget = try XCTUnwrap(
            brains.stash.resolveVisibleTarget(sharedControlTarget).resolved
        )

        let rawObject = RawEvidenceAdjustableView()
        brains.stash.nextVisibleRefreshScreenForTesting = observation(
            label: "Shared Control",
            heistId: rawId,
            object: rawObject,
            frame: CGRect(x: 80, y: 160, width: 180, height: 52)
        )
        XCTAssertNotNil(brains.stash.refreshLiveCapture())

        XCTAssertEqual(brains.stash.latestObservation.orderedElements.first?.heistId, rawId)
        XCTAssertNil(brains.stash.interfaceElement(heistId: rawId))
        XCTAssertEqual(
            brains.stash.resolveVisibleTarget(sharedControlTarget).resolved?.heistId,
            committedId
        )
        guard case .objectUnavailable = brains.stash.resolveLiveActionTarget(for: resolvedActionTarget) else {
            return XCTFail("Expected raw evidence with a different HeistId to remain non-dispatchable")
        }
        XCTAssertEqual(rawObject.incrementCount, 0)
    }

    func testReusedCommittedHeistIdCannotDispatchDifferentRawElement() throws {
        let sharedId: HeistId = "shared_control"
        let quantityTarget = try resolvedTarget(label: "Quantity")
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Quantity", heistId: sharedId)
        )
        let committedTarget = try XCTUnwrap(
            brains.stash.resolveVisibleTarget(quantityTarget).resolved
        )

        let replacementObject = RawEvidenceAdjustableView()
        brains.stash.nextVisibleRefreshScreenForTesting = observation(
            label: "Tip",
            heistId: sharedId,
            object: replacementObject
        )
        XCTAssertNotNil(brains.stash.refreshLiveCapture())

        guard case .objectUnavailable = brains.stash.resolveLiveActionTarget(for: committedTarget) else {
            return XCTFail("Expected recycled raw evidence to fail semantic alias proof")
        }
        XCTAssertEqual(replacementObject.incrementCount, 0)
    }

    func testSettledCommitAdmitsPreviouslyRawTarget() async throws {
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Screen A", heistId: "screen_a")
        )

        let object = RawEvidenceAdjustableView()
        let screenB = observation(label: "Screen B", heistId: "screen_b", object: object)
        let screenBTarget = try resolvedTarget(label: "Screen B")
        brains.stash.nextVisibleRefreshScreenForTesting = screenB
        XCTAssertNotNil(brains.stash.refreshLiveCapture())
        XCTAssertNil(brains.stash.resolveVisibleTarget(screenBTarget).resolved)

        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(screenB)

        XCTAssertEqual(
            brains.stash.resolveVisibleTarget(screenBTarget).resolved?.heistId,
            "screen_b"
        )
        let result = await brains.actions.executeIncrement(screenBTarget)
        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(object.incrementCount, 1)
    }

    private func resolvedTarget(label: String) throws -> ResolvedAccessibilityTarget {
        let authoredTarget = AccessibilityTarget.element(.label(label), traits: [.adjustable])
        return try authoredTarget.resolve(in: .empty)
    }

    private func observation(
        label: String,
        value: String? = nil,
        heistId: HeistId,
        object: NSObject? = nil,
        frame: CGRect = CGRect(x: 20, y: 40, width: 120, height: 44)
    ) -> InterfaceObservation {
        .makeForTests([
            .init(
                .make(
                    label: label,
                    value: value,
                    traits: .adjustable,
                    frame: frame
                ),
                heistId: heistId,
                object: object
            ),
        ])
    }
}

#endif

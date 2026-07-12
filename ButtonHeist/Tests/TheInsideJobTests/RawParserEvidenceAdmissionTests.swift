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

    func testRawRefreshCannotAdmitNewTargetForAction() async {
        let settledA = observation(label: "Screen A", heistId: "screen_a")
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(settledA)

        let rawObject = RawEvidenceAdjustableView()
        let rawB = observation(label: "Screen B", heistId: "screen_b", object: rawObject)
        brains.stash.nextVisibleRefreshScreenForTesting = rawB

        let beforeRefresh = await brains.actions.executeIncrement(target(label: "Screen B"))

        XCTAssertFalse(beforeRefresh.success)
        XCTAssertEqual(brains.stash.latestObservation.orderedElements.first?.element.label, "Screen A")
        XCTAssertEqual(rawObject.incrementCount, 0)

        XCTAssertNotNil(brains.stash.refreshLiveCapture())
        XCTAssertEqual(brains.stash.latestObservation.orderedElements.first?.element.label, "Screen B")
        XCTAssertEqual(brains.stash.interfaceTree.orderedElements.first?.element.label, "Screen A")
        XCTAssertNil(brains.stash.resolveVisibleTarget(target(label: "Screen B")).resolved)

        let afterRefresh = await brains.actions.executeIncrement(target(label: "Screen B"))

        XCTAssertFalse(afterRefresh.success)
        XCTAssertEqual(rawObject.incrementCount, 0)
    }

    func testSettledIdentityUsesRefreshedLiveEvidenceWithoutChangingSemanticSelection() async throws {
        let heistId: HeistId = "shared_control"
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
            brains.stash.resolveVisibleTarget(target(label: "Shared Control")).resolved
        )
        XCTAssertEqual(semanticTarget.element.value, "settled")
        XCTAssertEqual(semanticTarget.element.bhFrame, settledFrame)

        guard case .resolved(let liveTarget) = brains.stash.resolveLiveActionTarget(for: semanticTarget) else {
            return XCTFail("Expected refreshed live evidence for the settled identity")
        }
        XCTAssertTrue(liveTarget.object === refreshedObject)
        XCTAssertEqual(liveTarget.treeElement.heistId, heistId)
        XCTAssertEqual(liveTarget.element.value, "raw")
        XCTAssertEqual(liveTarget.frame, refreshedFrame)

        let result = await brains.actions.executeIncrement(target(label: "Shared Control"))

        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(refreshedObject.incrementCount, 1)
        XCTAssertEqual(
            brains.stash.resolveVisibleTarget(target(label: "Shared Control")).resolved?.element.value,
            "settled"
        )
    }

    func testSettledCommitAdmitsPreviouslyRawTarget() async {
        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Screen A", heistId: "screen_a")
        )

        let object = RawEvidenceAdjustableView()
        let screenB = observation(label: "Screen B", heistId: "screen_b", object: object)
        brains.stash.nextVisibleRefreshScreenForTesting = screenB
        XCTAssertNotNil(brains.stash.refreshLiveCapture())
        XCTAssertNil(brains.stash.resolveVisibleTarget(target(label: "Screen B")).resolved)

        brains.stash.semanticObservationStream.commitVisibleObservationForTesting(screenB)

        XCTAssertEqual(
            brains.stash.resolveVisibleTarget(target(label: "Screen B")).resolved?.heistId,
            "screen_b"
        )
        let result = await brains.actions.executeIncrement(target(label: "Screen B"))
        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(object.incrementCount, 1)
    }

    private func target(label: String) -> AccessibilityTarget {
        literalTarget(ElementPredicate(label: .exact(label), traits: [.adjustable]))
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

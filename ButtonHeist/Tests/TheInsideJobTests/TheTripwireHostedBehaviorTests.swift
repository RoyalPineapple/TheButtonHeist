#if canImport(UIKit)
import XCTest

import ButtonHeistHostedTestSupport
import ButtonHeistTesting
import TheScore
@testable import TheInsideJob

@MainActor
final class TheTripwireHostedBehaviorTests: XCTestCase {

    private var tripwire: TheTripwire!

    override func setUp() async throws {
        tripwire = TheTripwire()
    }

    override func tearDown() async throws {
        tripwire.stopPulse()
        tripwire = nil
    }

    func testPulseLifecycleIsIdempotentAndReturnsToIdle() {
        tripwire.startPulse()
        tripwire.startPulse()
        XCTAssertTrue(tripwire.isPulseRunning)

        tripwire.stopPulse()
        XCTAssertFalse(tripwire.isPulseRunning)
        XCTAssertNil(tripwire.latestReading)
    }

    func testTickWaitIsUnavailableWithoutCallerOwnedPulse() async {
        let outcome = await tripwire.waitForNextTick(
            timeout: .milliseconds(10),
            demand: .ambient
        )

        XCTAssertEqual(outcome, .unavailable)
        XCTAssertFalse(tripwire.isPulseRunning)
    }

    func testTraversableWindowsAreVisibleSizedAndFrontToBack() {
        let windows = tripwire.captureTraversableWindows().map(\.window)

        XCTAssertFalse(windows.isEmpty, "Test host should have a traversable window")
        XCTAssertTrue(windows.allSatisfy { !$0.isHidden && $0.bounds.size != .zero })
        for pair in zip(windows, windows.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.0.windowLevel, pair.1.windowLevel)
        }
    }

    func testFingerprintWindowParticipationIsExplicit() throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        )
        let fingerprintWindow = TheFingerprints.FingerprintWindow(windowScene: scene)
        fingerprintWindow.windowLevel = .statusBar + 100
        fingerprintWindow.frame = UIScreen.main.bounds
        fingerprintWindow.isHidden = false
        defer { fingerprintWindow.isHidden = true }

        XCTAssertFalse(TheTripwire.orderedVisibleWindows().contains(fingerprintWindow))
        XCTAssertFalse(tripwire.captureTraversableWindows().contains { $0.window === fingerprintWindow })
        XCTAssertTrue(TheTripwire.orderedVisibleWindows(includeFingerprints: true).contains(fingerprintWindow))
    }

    func testFingerprintsTrackEveryActivePoint() {
        let fingerprints = TheFingerprints(isEnabled: true)
        let phases = [
            [CGPoint(x: 20, y: 40), CGPoint(x: 80, y: 120)],
            [CGPoint(x: 25, y: 45), CGPoint(x: 85, y: 125), CGPoint(x: 145, y: 185)],
            [CGPoint(x: 40, y: 60)],
        ]

        fingerprints.beginTracking(at: phases[0])
        XCTAssertEqual(fingerprints.activeFingerprintCenters, phases[0])
        for points in phases.dropFirst() {
            fingerprints.updateTracking(to: points)
            XCTAssertEqual(fingerprints.activeFingerprintCenters, points)
        }

        fingerprints.endTracking()
        XCTAssertTrue(fingerprints.activeFingerprintCenters.isEmpty)
    }

    func testHostedControllerIsResolvableWhenIdle() {
        XCTAssertNotNil(tripwire.topmostViewController())
    }

    func testTransientExpectationLatchesUntilReadyHandoff() async throws {
        let heist = try await runHeist("HostedTransientExpectationReadyHandoff") {
            try DemoNavigation.backToRoot()
            try DogfoodHome.openScreen("Transient Flow")
            Activate(.label("Submit"))
                .expect(TransientFlowScreen.lifecycle, timeout: 8)
        }
        let evidence = try actionEvidence(
            matching: TransientFlowScreen.lifecycle,
            in: heist.result
        )
        let result = try XCTUnwrap(evidence.result)
        let observation = try XCTUnwrap(result.observationEvidence)

        XCTAssertEqual(evidence.expectation?.met, true)
        XCTAssertTrue(
            observation.hostedElementEdits.added.contains {
                $0.semantics.assertable.label == "Processing"
            }
        )
        XCTAssertTrue(
            observation.hostedElementEdits.removed.contains {
                $0.semantics.assertable.label == "Submit"
            }
        )
        XCTAssertEqual(observation.completeness, .complete)
    }

    func testAnnouncementExpectationLatchesUntilReadyHandoff() async throws {
        let heist = try await runHeist("HostedAnnouncementExpectationReadyHandoff") {
            try DemoNavigation.backToRoot()
            try DogfoodHome.openScreen("Transient Flow")
            Activate(.label("Submit"))
                .expect(TransientFlowScreen.announcement, timeout: 8)
        }
        let evidence = try actionEvidence(
            matching: TransientFlowScreen.announcement,
            in: heist.result
        )
        let result = try XCTUnwrap(evidence.result)
        let observation = try XCTUnwrap(result.observationEvidence)

        XCTAssertEqual(evidence.expectation?.met, true)
        XCTAssertEqual(evidence.announcement, "Ticket saved.")
        XCTAssertEqual(observation.completeness, .complete)
    }

    private func actionEvidence(
        matching predicate: AccessibilityPredicate,
        in result: HeistResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HeistActionEvidence {
        try XCTUnwrap(
            result.outputNodes.lazy.compactMap(\.actionEvidence)
                .first { $0.expectation?.predicate == predicate },
            "Missing action evidence for \(predicate)",
            file: file,
            line: line
        )
    }
}

private extension Observation.Evidence {
    var hostedElementEdits: ElementEdits {
        let snapshots = (baseline.map { [$0] } ?? []) + events.compactMap(\.snapshot)
        return zip(snapshots, snapshots.dropFirst())
            .reduce(into: ElementEdits()) { combined, pair in
                let edits = ElementEdits.between(pair.0.interface, pair.1.interface)
                combined = ElementEdits(
                    added: combined.added + edits.added,
                    removed: combined.removed + edits.removed,
                    updated: combined.updated + edits.updated
                )
            }
    }
}

#endif // canImport(UIKit)

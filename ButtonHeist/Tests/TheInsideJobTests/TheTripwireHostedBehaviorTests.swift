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

    func testWaitForSettleRequiresCallerOwnedPulse() async {
        let settled = await tripwire.waitForSettle(timeout: 0.01)

        XCTAssertFalse(settled)
        XCTAssertFalse(tripwire.isPulseRunning)
    }

    func testLayerScanCoversEveryTraversableWindow() {
        let windows = tripwire.captureTraversableWindows()
        let scan = tripwire.scanLayers()

        XCTAssertFalse(windows.isEmpty, "Test host should have a traversable window")
        XCTAssertEqual(scan.windowCount, windows.count)
        XCTAssertGreaterThan(scan.layerCount, 0)
        XCTAssertGreaterThan(scan.fingerprint.layerCount, 0)
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

    func testLayerScanReportsPendingLayout() throws {
        let window = try XCTUnwrap(tripwire.captureTraversableWindows().first?.window)
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        window.addSubview(view)
        defer { view.removeFromSuperview() }

        view.setNeedsLayout()
        XCTAssertTrue(tripwire.scanLayers().hasPendingLayout)
    }

    func testLayerScanIgnoresNeedsDisplay() throws {
        let window = try XCTUnwrap(tripwire.captureTraversableWindows().first?.window)
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        window.layer.addSublayer(layer)
        defer { layer.removeFromSuperlayer() }

        for _ in 0..<3 {
            window.layoutIfNeeded()
            CATransaction.flush()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        XCTAssertFalse(tripwire.scanLayers().hasPendingLayout, "Test baseline must be settled")

        layer.setNeedsDisplay()
        XCTAssertFalse(tripwire.scanLayers().hasPendingLayout)
    }

    func testHostedControllerAndFingerprintRemainStableWhenIdle() {
        XCTAssertNotNil(tripwire.topmostViewController())

        let first = tripwire.scanLayers().fingerprint
        let second = tripwire.scanLayers().fingerprint
        XCTAssertTrue(first.matches(second))
    }

    func testAllClearRequiresFirstPulseReading() {
        tripwire.startPulse()

        XCTAssertFalse(tripwire.allClear())
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
        let result = try XCTUnwrap(evidence.expectationResult)
        let trace = try XCTUnwrap(result.accessibilityTrace)
        let settlement = try XCTUnwrap(result.evidence.settlement)

        XCTAssertEqual(evidence.checkedExpectation?.met, true)
        XCTAssertTrue(trace.hostedAppearedLabels.contains("Processing"))
        XCTAssertTrue(trace.hostedDisappearedLabels.contains("Submit"))
        XCTAssertTrue(settlement.readinessEstablished)
        XCTAssertTrue(settlement.observationHandoffCompleted)
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
        let result = try XCTUnwrap(evidence.expectationResult)
        let settlement = try XCTUnwrap(result.evidence.settlement)

        XCTAssertEqual(evidence.checkedExpectation?.met, true)
        XCTAssertEqual(evidence.announcement, "Ticket saved.")
        XCTAssertTrue(settlement.readinessEstablished)
        XCTAssertTrue(settlement.observationHandoffCompleted)
    }

    private func actionEvidence(
        matching predicate: AccessibilityPredicate,
        in result: HeistResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HeistActionEvidence {
        try XCTUnwrap(
            result.outputNodes.lazy.compactMap(\.actionEvidence)
                .first { $0.checkedExpectation?.predicate == predicate },
            "Missing action evidence for \(predicate)",
            file: file,
            line: line
        )
    }
}

private extension AccessibilityTrace {
    var hostedAppearedLabels: [String] {
        changeFacts.flatMap { fact -> [String] in
            guard case .elementsChanged(let elements) = fact else { return [] }
            return elements.appeared.compactMap(\.hostedElementLabel)
        }
    }

    var hostedDisappearedLabels: [String] {
        changeFacts.flatMap { fact -> [String] in
            guard case .elementsChanged(let elements) = fact else { return [] }
            return elements.disappeared.compactMap(\.hostedElementLabel)
        }
    }
}

private extension AccessibilityTrace.InterfaceChangeNode {
    var hostedElementLabel: String? {
        guard case .element(let element, _) = node else { return nil }
        return element.label
    }
}

#endif // canImport(UIKit)

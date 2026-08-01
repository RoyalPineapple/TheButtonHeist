#if canImport(UIKit)
#if DEBUG
import UIKit
import XCTest

@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob

@MainActor
final class HeistExecutionHostTests: ButtonHeistTestCase {
    /// Physical canary: semantic Host coverage belongs to the deterministic
    /// runtime driver; this remains because it verifies UIKit viewport repair.
    func testCancellationRestoresPhysicalViewportAndAdmitsOneTerminalObservationCycle() async throws {
        let root = UIViewController()
        root.view.backgroundColor = .white
        root.view.accessibilityViewIsModal = true
        let scrollView = TrackingScrollView(
            frame: CGRect(x: 0, y: 40, width: 320, height: 240)
        )
        scrollView.contentSize = CGSize(width: 320, height: 960)
        let row = UILabel(frame: CGRect(x: 20, y: 20, width: 200, height: 44))
        row.text = "Visible Row"
        row.accessibilityLabel = "Visible Row"
        row.isAccessibilityElement = true
        scrollView.addSubview(row)
        root.view.addSubview(scrollView)
        present(root, above: true)

        let tripwire = TheTripwire()
        let brains = TheBrains(tripwire: tripwire, failureEvidencePolicy: .hierarchy)
        let forwardScroll = HostCaptureGate()
        scrollView.onForwardScroll = forwardScroll.arrive
        await brains.startTestObservation()
        defer {
            brains.stopTestObservation()
        }
        let initialContentOffset = scrollView.contentOffset

        let execution = Task { @MainActor in
            try await HeistExecution.Host(brains: brains).execute(
                try HeistPlan(body: [
                    .wait(WaitStep(
                        predicate: .exists(.label("Never Appears")),
                        timeout: 30
                    )),
                ]),
                timeout: try .seconds(60)
            )
        }
        await forwardScroll.waitUntilEntered()
        XCTAssertGreaterThan(scrollView.forwardScrollCount, 0)
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)
        execution.cancel()

        do {
            _ = try await execution.value
            XCTFail("Expected cancelled execution")
        } catch is CancellationError {
            // Expected after terminal restoration finishes.
        }

        XCTAssertEqual(scrollView.contentOffset, initialContentOffset)
    }

}

@MainActor
private final class HostCaptureGate {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []

    func arrive() {
        guard !entered else { return }
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }
}

@MainActor
private final class TrackingScrollView: UIScrollView {
    private(set) var forwardScrollCount = 0
    var onForwardScroll: (@MainActor () -> Void)?

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        if contentOffset.y > self.contentOffset.y {
            forwardScrollCount += 1
            onForwardScroll?()
        }
        super.setContentOffset(contentOffset, animated: animated)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

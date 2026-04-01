#if canImport(UIKit)
// Integration tests for performWaitFor — the settle-event polling loop that waits
// for an element to appear or disappear. Requires the BH Demo test host
// since wait_for polls the live accessibility tree via TheBagman.
import XCTest
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class WaitForIntegrationTests: XCTestCase {

    private var insideJob: TheInsideJob!
    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        insideJob = TheInsideJob(token: "wait-for-test-token")
        let windows = insideJob.tripwire.getTraversableWindows()
        window = windows.first?.window
        XCTAssertNotNil(window, "Test host must provide a window")
    }

    override func tearDown() {
        insideJob.tripwire.stopPulse()
        insideJob = nil
        window = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func collectResponse() -> (respond: @Sendable (Data) -> Void, result: () -> ActionResult?) {
        final class Box: @unchecked Sendable {
            var data: Data?
        }
        let box = Box()
        let respond: @Sendable (Data) -> Void = { data in
            box.data = data
        }
        return (respond, {
            guard let data = box.data,
                  let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data),
                  case .actionResult(let result) = envelope.message else { return nil }
            return result
        })
    }

    @discardableResult
    private func addLabel(_ text: String, identifier: String? = nil) -> UILabel {
        let label = UILabel()
        label.text = text
        label.accessibilityLabel = text
        label.isAccessibilityElement = true
        label.frame = CGRect(x: 10, y: 100, width: 200, height: 44)
        if let identifier {
            label.accessibilityIdentifier = identifier
        }
        window.addSubview(label)
        return label
    }

    private func waitFor(
        target: ElementTarget,
        absent: Bool? = nil,
        timeout: Double? = nil
    ) async -> ActionResult? {
        let waitTarget = WaitForTarget(elementTarget: target, absent: absent, timeout: timeout)
        let (respond, result) = collectResponse()
        await insideJob.performWaitFor(
            target: waitTarget,
            command: .waitFor(waitTarget),
            requestId: "test",
            respond: respond
        )
        return result()
    }

    // MARK: - 1. Element already present — returns immediately

    func testWaitForAlreadyPresentReturnsImmediately() async {
        let label = addLabel("WaitFor-AlreadyPresent")
        defer { label.removeFromSuperview() }

        let result = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-AlreadyPresent")),
            timeout: 5.0
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.success == true)
        XCTAssertEqual(result?.method, .waitFor)
        XCTAssertEqual(result?.message, "matched immediately")
        XCTAssertNil(result?.errorKind)
    }

    // MARK: - 2. Element appears after a delay

    func testWaitForElementAppearsAfterDelay() async {
        let result: ActionResult? = await withCheckedContinuation { continuation in
            Task { @MainActor in
                // Schedule the label to appear after a short delay
                let addTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    self.addLabel("WaitFor-Delayed")
                }

                let r = await self.waitFor(
                    target: .matcher(ElementMatcher(label: "WaitFor-Delayed")),
                    timeout: 10.0
                )
                addTask.cancel()
                continuation.resume(returning: r)
            }
        }

        // Clean up
        for subview in window.subviews where subview.accessibilityLabel == "WaitFor-Delayed" {
            subview.removeFromSuperview()
        }

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.success == true)
        XCTAssertEqual(result?.method, .waitFor)
        XCTAssertNotNil(result?.message)
        XCTAssertTrue(result?.message?.contains("matched after") == true)
        XCTAssertNil(result?.errorKind)
    }

    // MARK: - 3. wait_for absent: true on a present element — should timeout

    func testWaitForAbsentOnPresentElementTimesOut() async {
        let label = addLabel("WaitFor-StillHere")
        defer { label.removeFromSuperview() }

        let result = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-StillHere")),
            absent: true,
            timeout: 2.0
        )

        XCTAssertNotNil(result)
        XCTAssertFalse(result?.success == true)
        XCTAssertEqual(result?.method, .waitFor)
        XCTAssertEqual(result?.errorKind, .timeout)
        XCTAssertTrue(result?.message?.contains("element still present") == true)
    }

    // MARK: - 4. wait_for absent: true on an element that disappears

    func testWaitForAbsentElementDisappears() async {
        let label = addLabel("WaitFor-GoingAway")

        let result: ActionResult? = await withCheckedContinuation { continuation in
            Task { @MainActor in
                let removeTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    label.removeFromSuperview()
                }

                let r = await self.waitFor(
                    target: .matcher(ElementMatcher(label: "WaitFor-GoingAway")),
                    absent: true,
                    timeout: 10.0
                )
                removeTask.cancel()
                continuation.resume(returning: r)
            }
        }

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.success == true)
        XCTAssertEqual(result?.method, .waitFor)
        XCTAssertTrue(result?.message?.contains("absent confirmed") == true)
        XCTAssertNil(result?.errorKind)
    }

    // MARK: - 5. wait_for respects timeout value

    func testWaitForRespectsTimeout() async {
        let start = CFAbsoluteTimeGetCurrent()

        let result = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-NonExistent-Element")),
            timeout: 2.0
        )

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertNotNil(result)
        XCTAssertFalse(result?.success == true)
        XCTAssertEqual(result?.errorKind, .timeout)
        XCTAssertTrue(result?.message?.contains("element not found") == true)
        // Should complete around 2s — allow generous margin for settle loop overhead
        XCTAssertGreaterThanOrEqual(elapsed, 1.5, "Should wait at least close to the timeout")
        XCTAssertLessThan(elapsed, 5.0, "Should not wait much longer than the timeout")
    }

    // MARK: - 6. wait_for with heistId vs matcher — both paths resolve

    func testWaitForWithMatcherByIdentifier() async {
        let label = addLabel("WaitFor-ById", identifier: "waitfor-test-id")
        defer { label.removeFromSuperview() }

        let result = await waitFor(
            target: .matcher(ElementMatcher(identifier: "waitfor-test-id")),
            timeout: 5.0
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.success == true)
        XCTAssertEqual(result?.message, "matched immediately")
    }

    func testWaitForWithHeistId() async {
        let label = addLabel("WaitFor-HeistId")
        defer { label.removeFromSuperview() }

        // Refresh the tree so heistIds are assigned
        insideJob.bagman.refresh()
        let elements = insideJob.bagman.snapshot(.visible)

        // Find the heistId for our element
        let heistId = elements.first(where: {
            $0.element.label == "WaitFor-HeistId"
        })?.heistId

        guard let heistId else {
            XCTFail("Could not find heistId for test label")
            return
        }

        let result = await waitFor(
            target: .heistId(heistId),
            timeout: 5.0
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.success == true)
        XCTAssertEqual(result?.message, "matched immediately")
    }

    // MARK: - Absent already absent returns immediately

    func testWaitForAbsentAlreadyAbsentReturnsImmediately() async {
        let result = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-NeverExisted")),
            absent: true,
            timeout: 5.0
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.success == true)
        XCTAssertEqual(result?.method, .waitFor)
        XCTAssertEqual(result?.message, "absent confirmed after 0.0s")
        XCTAssertNil(result?.errorKind)
    }
}
#endif

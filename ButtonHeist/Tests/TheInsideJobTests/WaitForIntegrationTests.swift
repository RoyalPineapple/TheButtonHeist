#if canImport(UIKit)
// Integration tests for performWaitFor — the settle-event polling loop that waits
// for an element to appear or disappear. Requires the BH Demo test host
// since wait_for polls the live accessibility tree via TheStash.
import XCTest
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class WaitForIntegrationTests: XCTestCase {

    private var insideJob: TheInsideJob!
    private var window: UIWindow!

    override func setUp() async throws {
        insideJob = TheInsideJob(token: "wait-for-test-token")
        // Pick the frontmost non-passthrough window so a keyboard window left
        // over from a prior test in the suite (which is hidden from the
        // accessibility tree) doesn't receive our test labels.
        let windows = insideJob.tripwire.getTraversableWindows()
            .filter { !TheTripwire.isSystemPassthroughWindow($0.window) }
        window = windows.first?.window
        XCTAssertNotNil(window, "Test host must provide a non-passthrough window")
    }

    override func tearDown() async throws {
        insideJob.tripwire.stopPulse()
        insideJob = nil
        window = nil
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
            guard let data = box.data else { return nil }
            let envelope: ResponseEnvelope
            do {
                envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
            } catch {
                XCTFail("Failed to decode ResponseEnvelope: \(error)")
                return nil
            }
            guard case .actionResult(let result) = envelope.message else { return nil }
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
        return await insideJob.brains.performWaitFor(target: waitTarget)
    }

    // MARK: - 1. Element already present — returns immediately

    func testWaitForAlreadyPresentReturnsImmediately() async throws {
        let label = addLabel("WaitFor-AlreadyPresent")
        defer { label.removeFromSuperview() }

        let response = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-AlreadyPresent")),
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .waitFor)
        XCTAssertEqual(result.message, "matched immediately")
        XCTAssertNil(result.errorKind)
    }

    // MARK: - 2. Element appears after a delay

    func testWaitForElementAppearsAfterDelay() async throws {
        // Queue the label-add Task on @MainActor before calling waitFor.
        // waitFor runs its synchronous prefix (initial hasTarget check returns
        // false because the label isn't in the tree yet), then suspends on
        // `tripwire.waitForAllClear`. While suspended the queued addLabel Task
        // runs; the next pulse tick observes the new label and wait_for resolves
        // with "matched after …". No wall-clock sleep needed.
        let addTask = Task { @MainActor in
            _ = self.addLabel("WaitFor-Delayed")
        }

        let response = await self.waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-Delayed")),
            timeout: 10.0
        )
        await addTask.value

        // Clean up
        for subview in window.subviews where subview.accessibilityLabel == "WaitFor-Delayed" {
            subview.removeFromSuperview()
        }

        let unwrapped = try XCTUnwrap(response)
        XCTAssertTrue(unwrapped.success)
        XCTAssertEqual(unwrapped.method, .waitFor)
        let message = try XCTUnwrap(unwrapped.message)
        XCTAssertTrue(message.contains("matched after"))
        XCTAssertNil(unwrapped.errorKind)
    }

    // MARK: - 3. wait_for absent: true on a present element — should timeout

    func testWaitForAbsentOnPresentElementTimesOut() async throws {
        let label = addLabel("WaitFor-StillHere")
        defer { label.removeFromSuperview() }

        let response = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-StillHere")),
            absent: true,
            timeout: 2.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitFor)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("element still present") == true)
    }

    // MARK: - 4. wait_for absent: true on an element that disappears

    func testWaitForAbsentElementDisappears() async throws {
        let label = addLabel("WaitFor-GoingAway")

        // Queue the removal on @MainActor; it runs once waitFor suspends on
        // its first tripwire await. The pulse then observes the absence and
        // resolves the wait deterministically.
        let removeTask = Task { @MainActor in
            label.removeFromSuperview()
        }

        let response = await self.waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-GoingAway")),
            absent: true,
            timeout: 10.0
        )
        await removeTask.value

        let unwrapped = try XCTUnwrap(response)
        XCTAssertTrue(unwrapped.success)
        XCTAssertEqual(unwrapped.method, .waitFor)
        XCTAssertTrue(unwrapped.message?.contains("absent confirmed") == true)
        XCTAssertNil(unwrapped.errorKind)
    }

    // MARK: - 5. wait_for respects timeout value

    func testWaitForRespectsTimeout() async throws {
        let start = CFAbsoluteTimeGetCurrent()

        let response = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-NonExistent-Element")),
            timeout: 2.0
        )
        let result = try XCTUnwrap(response)

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("element not found") == true)
        // Should complete around 2s — allow generous margin for settle loop overhead
        XCTAssertGreaterThanOrEqual(elapsed, 1.5, "Should wait at least close to the timeout")
        XCTAssertLessThan(elapsed, 5.0, "Should not wait much longer than the timeout")
    }

    // MARK: - 6. wait_for with heistId vs matcher — both paths resolve

    func testWaitForWithMatcherByIdentifier() async throws {
        let label = addLabel("WaitFor-ById", identifier: "waitfor-test-id")
        defer { label.removeFromSuperview() }

        let response = await waitFor(
            target: .matcher(ElementMatcher(identifier: "waitfor-test-id")),
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.message, "matched immediately")
    }

    func testWaitForWithHeistId() async throws {
        let label = addLabel("WaitFor-HeistId")
        defer { label.removeFromSuperview() }

        // Refresh the tree so heistIds are assigned
        guard insideJob.brains.refresh() != nil else {
            XCTFail("Could not refresh accessibility tree")
            return
        }
        let elements = insideJob.brains.stash.selectElements()

        // Find the heistId for our element
        let heistId = try XCTUnwrap(elements.first(where: {
            $0.element.label == "WaitFor-HeistId"
        })?.heistId, "Could not find heistId for test label")

        let response = await waitFor(
            target: .heistId(heistId),
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.message, "matched immediately")
    }

    func testWaitForAbsentWithHeistIdSucceedsAfterElementLeavesLiveTree() async throws {
        let label = addLabel("WaitFor-HeistId-GoingAway")

        guard insideJob.brains.refresh() != nil else {
            XCTFail("Could not refresh accessibility tree")
            return
        }
        let elements = insideJob.brains.stash.selectElements()
        let heistId = try XCTUnwrap(elements.first(where: {
            $0.element.label == "WaitFor-HeistId-GoingAway"
        })?.heistId, "Could not find heistId for test label")

        let removeTask = Task { @MainActor in
            label.removeFromSuperview()
        }

        let response = await self.waitFor(
            target: .heistId(heistId),
            absent: true,
            timeout: 10.0
        )
        await removeTask.value

        let unwrapped = try XCTUnwrap(response)
        XCTAssertTrue(unwrapped.success)
        XCTAssertEqual(unwrapped.method, .waitFor)
        XCTAssertTrue(unwrapped.message?.contains("absent confirmed") == true)
        XCTAssertNil(unwrapped.errorKind)
    }

    // MARK: - Absent already absent returns immediately

    func testWaitForAbsentAlreadyAbsentReturnsImmediately() async throws {
        let response = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-NeverExisted")),
            absent: true,
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .waitFor)
        XCTAssertEqual(result.message, "absent confirmed after 0.0s")
        XCTAssertNil(result.errorKind)
    }
}
#endif

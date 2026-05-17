#if canImport(UIKit)
// Integration tests for performWaitFor — the settle-event polling loop that waits
// for an element to appear or disappear. Requires the BH Demo test host
// since wait_for polls the semantic accessibility tree via TheStash.
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
        // Test-only inspection box. Mutated only from within the @Sendable
        // closure that captures it; not shared across threads in practice.
        final class Box: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
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
    private func addLabel(_ text: String, identifier: String? = nil, y: CGFloat = 100) -> UILabel {
        let label = UILabel()
        label.text = text
        label.accessibilityLabel = text
        label.isAccessibilityElement = true
        label.frame = CGRect(x: 10, y: y, width: 200, height: 44)
        if let identifier {
            label.accessibilityIdentifier = identifier
        }
        window.addSubview(label)
        return label
    }

    @discardableResult
    private func addScrollViewWithOffscreenLabel(_ text: String) -> UIScrollView {
        let scrollView = UIScrollView(frame: CGRect(x: 10, y: 100, width: 220, height: 120))
        scrollView.contentSize = CGSize(width: 220, height: 640)
        scrollView.isAccessibilityElement = false

        let label = UILabel(frame: CGRect(x: 10, y: 480, width: 180, height: 44))
        label.text = text
        label.accessibilityLabel = text
        label.isAccessibilityElement = true
        scrollView.addSubview(label)

        window.addSubview(scrollView)
        return scrollView
    }

    private func waitFor(
        target: ElementTarget,
        absent: Bool? = nil,
        timeout: Double? = nil
    ) async -> ActionResult? {
        let waitTarget = WaitForTarget(elementTarget: target, absent: absent, timeout: timeout)
        return await insideJob.brains.performWaitFor(target: waitTarget)
    }

    private func waitForChange(
        expectation: ActionExpectation,
        timeout: Double? = nil
    ) async -> ActionResult {
        await insideJob.brains.executeWaitForChange(
            timeout: timeout ?? 5.0,
            expectation: expectation
        )
    }

    @discardableResult
    private func refreshAndRecordSentState() -> Bool {
        guard insideJob.brains.refresh() != nil else { return false }
        insideJob.brains.recordSentState()
        return true
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

    func testWaitForAmbiguousMatcherDoesNotSatisfyPresence() async throws {
        let first = addLabel("WaitFor-Ambiguous", y: 100)
        let second = addLabel("WaitFor-Ambiguous", y: 150)
        defer {
            first.removeFromSuperview()
            second.removeFromSuperview()
        }

        let response = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-Ambiguous")),
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitFor)
        XCTAssertEqual(result.errorKind, .elementNotFound)
        XCTAssertTrue(result.message?.contains("2 elements match") == true)
        XCTAssertTrue(result.message?.contains("ordinal") == true)
    }

    func testWaitForExplicitOrdinalHitSatisfiesPresence() async throws {
        let first = addLabel("WaitFor-OrdinalHit", y: 100)
        let second = addLabel("WaitFor-OrdinalHit", y: 150)
        defer {
            first.removeFromSuperview()
            second.removeFromSuperview()
        }

        let response = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-OrdinalHit"), ordinal: 1),
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .waitFor)
        XCTAssertEqual(result.message, "matched immediately")
        XCTAssertNil(result.errorKind)
    }

    func testWaitForExplicitOrdinalOutOfRangeDoesNotFallBackToFirstMatch() async throws {
        let first = addLabel("WaitFor-OrdinalOutOfRange", y: 100)
        let second = addLabel("WaitFor-OrdinalOutOfRange", y: 150)
        defer {
            first.removeFromSuperview()
            second.removeFromSuperview()
        }

        let response = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-OrdinalOutOfRange"), ordinal: 2),
            timeout: 0.2
        )
        let result = try XCTUnwrap(response)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitFor)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("element not found") == true)
        XCTAssertTrue(result.message?.contains("ordinal 2 requested") == true)
        XCTAssertTrue(result.message?.contains("2 matches") == true)
    }

    func testWaitForAppearTimeoutNamesExpectedMatcherAndKnownCount() async throws {
        let label = addLabel("WaitFor-Known-Anchor")
        defer { label.removeFromSuperview() }

        let response = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-Missing-Target")),
            timeout: 0.2
        )
        let result = try XCTUnwrap(response)
        let message = try XCTUnwrap(result.message)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitFor)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(message.contains("waiting for element to appear"), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("expected: label=\"WaitFor-Missing-Target\""), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("known:"), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("Next: get_interface(scope: \"full\")"), "Unexpected message: \(message)")
    }

    // MARK: - 2. Element appears after a delay

    func testWaitForElementAppearsAfterDelay() async throws {
        // Delay the UI mutation by a couple of display frames so the first
        // semantic snapshot still observes absence and the poll path observes
        // the later arrival.
        let addTask = Task { @MainActor in
            await self.insideJob.tripwire.yieldRealFrames(2)
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
        XCTAssertTrue(message.contains("matched after"), "Unexpected message: \(message)")
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

    func testWaitForAbsentAmbiguousMatcherDoesNotSatisfyAbsence() async throws {
        let first = addLabel("WaitFor-Absent-Ambiguous", y: 100)
        let second = addLabel("WaitFor-Absent-Ambiguous", y: 150)
        defer {
            first.removeFromSuperview()
            second.removeFromSuperview()
        }

        let response = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-Absent-Ambiguous")),
            absent: true,
            timeout: 5.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitFor)
        XCTAssertEqual(result.errorKind, .elementNotFound)
        XCTAssertTrue(result.message?.contains("2 elements match") == true)
        XCTAssertTrue(result.message?.contains("ordinal") == true)
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

    func testWaitForAbsentTreatsOffscreenScrollableElementAsPresent() async throws {
        let scrollView = addScrollViewWithOffscreenLabel("WaitFor-Offscreen-StillHere")
        defer { scrollView.removeFromSuperview() }

        let response = await waitFor(
            target: .matcher(ElementMatcher(label: "WaitFor-Offscreen-StillHere")),
            absent: true,
            timeout: 2.0
        )
        let result = try XCTUnwrap(response)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitFor)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("element still present") == true)
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

    // MARK: - wait_for_change current state

    func testWaitForChangeElementAppearedAlreadyPresentReturnsImmediately() async throws {
        let label = addLabel("WaitForChange-AlreadyPresent")
        defer { label.removeFromSuperview() }

        let result = await waitForChange(
            expectation: .elementAppeared(ElementMatcher(label: "WaitForChange-AlreadyPresent")),
            timeout: 5.0
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .waitForChange)
        XCTAssertEqual(result.message, "expectation already met by current state (0.0s)")
        guard case .noChange = result.interfaceDelta else {
            return XCTFail("Expected noChange delta, got \(String(describing: result.interfaceDelta))")
        }
    }

    func testWaitForChangeElementDisappearedAlreadyAbsentReturnsImmediately() async throws {
        let result = await waitForChange(
            expectation: .elementDisappeared(ElementMatcher(label: "WaitForChange-NeverExisted")),
            timeout: 5.0
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .waitForChange)
        XCTAssertEqual(result.message, "expectation already met by current state (0.0s)")
        guard case .noChange = result.interfaceDelta else {
            return XCTFail("Expected noChange delta, got \(String(describing: result.interfaceDelta))")
        }
    }

    func testWaitForChangeElementAppearedAfterBaselineReturnsThroughChangePath() async throws {
        let baseline = addLabel("WaitForChange-Baseline")
        defer { baseline.removeFromSuperview() }
        XCTAssertTrue(refreshAndRecordSentState())

        let addTask = Task { @MainActor in
            await self.insideJob.tripwire.yieldRealFrames(2)
            _ = self.addLabel("WaitForChange-Delayed")
        }

        let result = await waitForChange(
            expectation: .elementAppeared(ElementMatcher(label: "WaitForChange-Delayed")),
            timeout: 5.0
        )
        await addTask.value
        for subview in window.subviews where subview.accessibilityLabel == "WaitForChange-Delayed" {
            subview.removeFromSuperview()
        }

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .waitForChange)
        XCTAssertTrue(result.message?.contains("expectation met after") == true)
        guard case .elementsChanged = result.interfaceDelta else {
            return XCTFail("Expected elementsChanged delta, got \(String(describing: result.interfaceDelta))")
        }
    }

    func testWaitForChangeElementsChangedFallsThroughCurrentStateCheck() async throws {
        let baseline = addLabel("WaitForChange-ElementsBaseline")
        defer { baseline.removeFromSuperview() }
        XCTAssertTrue(refreshAndRecordSentState())

        let changed = addLabel("WaitForChange-ElementsChanged")
        defer { changed.removeFromSuperview() }

        let result = await waitForChange(
            expectation: .elementsChanged,
            timeout: 5.0
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .waitForChange)
        XCTAssertTrue(result.message?.contains("expectation met after") == true)
        guard case .elementsChanged = result.interfaceDelta else {
            return XCTFail("Expected elementsChanged delta, got \(String(describing: result.interfaceDelta))")
        }
    }

    func testWaitForChangeElementDisappearedTimesOutWhenElementStillPresent() async throws {
        let label = addLabel("WaitForChange-StillPresent")
        defer { label.removeFromSuperview() }

        let result = await waitForChange(
            expectation: .elementDisappeared(ElementMatcher(label: "WaitForChange-StillPresent")),
            timeout: 0.2
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitForChange)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("expected: element_disappeared(WaitForChange-StillPresent)") == true)
        XCTAssertTrue(result.message?.contains("Next: get_interface(scope: \"full\")") == true)
    }

    func testWaitForChangeScreenChangedTimeoutSuggestsElementsChanged() async throws {
        let label = addLabel("WaitForChange-ScreenChangedTimeout")
        defer { label.removeFromSuperview() }

        let result = await waitForChange(
            expectation: .screenChanged,
            timeout: 0.2
        )
        let message = try XCTUnwrap(result.message)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitForChange)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(message.contains("expected: screen_changed"), "Unexpected message: \(message)")
        XCTAssertTrue(message.contains("expect={type: \"elements_changed\"}"), "Unexpected message: \(message)")
    }

    func testWaitForChangeElementsChangedTimeoutDoesNotSuggestElementsChanged() async throws {
        let label = addLabel("WaitForChange-ElementsChangedTimeout")
        defer { label.removeFromSuperview() }

        let result = await waitForChange(
            expectation: .elementsChanged,
            timeout: 0.2
        )
        let message = try XCTUnwrap(result.message)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitForChange)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(message.contains("expected: elements_changed"), "Unexpected message: \(message)")
        XCTAssertFalse(message.contains("expect={type: \"elements_changed\"}"), "Unexpected message: \(message)")
    }

    func testWaitForChangeElementUpdatedWithOldValueRequiresObservedUpdate() async throws {
        let label = addLabel("WaitForChange-UpdateOldValue")
        label.accessibilityValue = "Ready"
        defer { label.removeFromSuperview() }

        let result = await waitForChange(
            expectation: .elementUpdated(
                property: .value,
                oldValue: "Loading",
                newValue: "Ready"
            ),
            timeout: 0.2
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitForChange)
        XCTAssertEqual(result.errorKind, .timeout)
    }

    func testWaitForChangeCompoundTimesOutWhenCurrentStatePartiallyMatches() async throws {
        let label = addLabel("WaitForChange-CompoundPresent")
        defer { label.removeFromSuperview() }

        let result = await waitForChange(
            expectation: .compound([
                .elementAppeared(ElementMatcher(label: "WaitForChange-CompoundPresent")),
                .elementAppeared(ElementMatcher(label: "WaitForChange-CompoundMissing")),
            ]),
            timeout: 0.2
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitForChange)
        XCTAssertEqual(result.errorKind, .timeout)
    }
}
#endif

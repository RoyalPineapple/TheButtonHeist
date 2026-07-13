#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class ActivationPolicyTests: XCTestCase {

    private final class ActivationObject: NSObject {}

    func testElementInflationFailureMapsNoRevealPathToCommandMethod() {
        let result = ElementInflation.ElementInflationFailure.noRevealPath("target has no reveal path")
            .actionDispatchOutcome(commandMethod: .activate)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.message, "element inflation failed [noRevealPath]: target has no reveal path")
    }

    func testElementInflationFailurePreservesElementNotFoundMethod() {
        let result = ElementInflation.ElementInflationFailure.notFound("no such element")
            .actionDispatchOutcome(commandMethod: .activate)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.failureKind, .targetUnavailable)
        XCTAssertEqual(result.message, "element inflation failed [notFound]: no such element")
    }

    func testElementInflationCancellationPreservesTypedTerminalFailure() {
        let failure = ElementInflation.ElementInflationFailure.cancelled(
            "stale live target refresh was cancelled after the live target no longer matched"
        )

        XCTAssertEqual(failure.failedStep, .cancelled)
        XCTAssertEqual(failure.failureKind, .actionFailed)
        XCTAssertEqual(
            failure.message,
            "element inflation failed [cancelled]: stale live target refresh was cancelled "
                + "after the live target no longer matched"
        )
        let result = failure.actionDispatchOutcome(commandMethod: .activate)
        XCTAssertEqual(result.method, .activate)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.failureKind, .actionFailed)
    }

    func testElementInflationTransitionRejectionPreservesCommandMethod() {
        let rejection = ElementInflation.StateTransitionRejection(
            state: .inflated,
            event: .advance(to: .refreshing)
        )
        let failure = ElementInflation.ElementInflationFailure.invalidTransition(rejection)

        XCTAssertEqual(failure.failedStep, .invalidTransition)
        XCTAssertEqual(failure.failureKind, .actionFailed)
        XCTAssertEqual(
            failure.message,
            "element inflation failed [invalidTransition]: cannot transition from inflated to refreshing"
        )
        let result = failure.actionDispatchOutcome(commandMethod: .activate)
        XCTAssertEqual(result.method, .activate)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.failureKind, .actionFailed)
    }

    func testRefreshReresolveActivateSuccessStopsPolicy() async {
        let initialTarget = makeLiveTarget(heistId: "initial", activationPoint: CGPoint(x: 10, y: 20))
        let refreshedTarget = makeLiveTarget(heistId: "refreshed", activationPoint: CGPoint(x: 30, y: 40))
        var events: [String] = []
        var dispatchedPoints: [CGPoint] = []
        var fingerprintPoints: [CGPoint] = []

        let result = await makePolicy(
            accessibilityActivate: { target in
                events.append("activate:\(target.treeElement.heistId)")
                return .success
            },
            refreshAndResolve: {
                events.append("refresh")
                return .resolved(treeElement: refreshedTarget.treeElement, liveTarget: refreshedTarget)
            },
            activationPointDispatch: { point in
                dispatchedPoints.append(point)
                return true
            },
            showFingerprint: { point in
                fingerprintPoints.append(point)
            }
        ).apply(to: initialTarget)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(events, ["refresh", "activate:refreshed"])
        XCTAssertTrue(dispatchedPoints.isEmpty)
        XCTAssertEqual(fingerprintPoints, [CGPoint(x: 30, y: 40)])
        XCTAssertEqual(result.activationTrace, ActivationTrace(.accessibilityActivate))
    }

    func testRefreshReresolveFailureReturnsWithoutActivationAttemptOrDispatch() async {
        let initialTarget = makeLiveTarget(heistId: "initial", activationPoint: CGPoint(x: 10, y: 20))
        var activateCount = 0
        var dispatchedPoints: [CGPoint] = []

        let result = await makePolicy(
            accessibilityActivate: { _ in
                activateCount += 1
                return .refused
            },
            refreshAndResolve: {
                .failure(.failure(.activate, message: "activation refresh failed"))
            },
            activationPointDispatch: { point in
                dispatchedPoints.append(point)
                return true
            }
        ).apply(to: initialTarget)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.message, "activation refresh failed")
        XCTAssertEqual(activateCount, 0)
        XCTAssertTrue(dispatchedPoints.isEmpty)
        XCTAssertEqual(result.activationTrace, ActivationTrace(.refreshFailed))
    }

    func testActivationPointDispatchCanCompleteActivate() async {
        let initialTarget = makeLiveTarget(heistId: "initial", activationPoint: CGPoint(x: 10, y: 20))
        let refreshedTarget = makeLiveTarget(heistId: "refreshed", activationPoint: CGPoint(x: 30, y: 40))
        var activateCount = 0
        var dispatchedPoints: [CGPoint] = []

        let result = await makePolicy(
            accessibilityActivate: { _ in
                activateCount += 1
                return .refused
            },
            refreshAndResolve: {
                .resolved(treeElement: refreshedTarget.treeElement, liveTarget: refreshedTarget)
            },
            activationPointDispatch: { point in
                dispatchedPoints.append(point)
                return true
            }
        ).apply(to: initialTarget)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(activateCount, 1)
        XCTAssertEqual(dispatchedPoints, [CGPoint(x: 30, y: 40)])
        XCTAssertEqual(result.activationTrace, ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 30, y: 40),
            tapActivationSucceeded: true
        )))
    }

    func testTextEntryActivationPointDispatchRequiresFocusConfirmation() async {
        let initialTarget = makeLiveTarget(heistId: "initial", activationPoint: CGPoint(x: 10, y: 20))
        let refreshedTarget = makeLiveTarget(
            heistId: "refreshed",
            traits: .textEntry,
            activationPoint: CGPoint(x: 30, y: 40)
        )
        var focusConfirmationTrace: ActivationTrace?

        let result = await makePolicy(
            accessibilityActivate: { _ in .refused },
            refreshAndResolve: {
                .resolved(treeElement: refreshedTarget.treeElement, liveTarget: refreshedTarget)
            },
            activationPointDispatch: { _ in true },
            textEntryActivationFailure: { _, trace in
                focusConfirmationTrace = trace
                return .failure(.activate, message: "text entry did not focus", activationTrace: trace)
            }
        ).apply(to: initialTarget)

        let expectedTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 30, y: 40),
            tapActivationSucceeded: true
        ))
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "text entry did not focus")
        XCTAssertEqual(result.activationTrace, expectedTrace)
        XCTAssertEqual(focusConfirmationTrace, expectedTrace)
    }

    func testNonTextEntryActivationPointDispatchDoesNotRequireFocusConfirmation() async {
        let initialTarget = makeLiveTarget(heistId: "initial", activationPoint: CGPoint(x: 10, y: 20))
        let refreshedTarget = makeLiveTarget(
            heistId: "refreshed",
            traits: .button,
            activationPoint: CGPoint(x: 30, y: 40)
        )
        var focusConfirmationCount = 0

        let result = await makePolicy(
            accessibilityActivate: { _ in .refused },
            refreshAndResolve: {
                .resolved(treeElement: refreshedTarget.treeElement, liveTarget: refreshedTarget)
            },
            activationPointDispatch: { _ in true },
            textEntryActivationFailure: { _, _ in
                focusConfirmationCount += 1
                return .failure(.activate, message: "unexpected focus confirmation")
            }
        ).apply(to: initialTarget)

        XCTAssertTrue(result.success)
        XCTAssertEqual(focusConfirmationCount, 0)
    }

    func testFinalFailureUsesRefreshedTargetAndFreshActivationPoint() async {
        let initialTarget = makeLiveTarget(heistId: "initial", activationPoint: CGPoint(x: 10, y: 20))
        let refreshedTarget = makeLiveTarget(
            heistId: "refreshed",
            label: "Refreshed Button",
            traits: .button,
            frame: CGRect(x: 12, y: 30, width: 80, height: 44),
            activationPoint: CGPoint(x: 52, y: 52)
        )
        var activateCount = 0
        var dispatchedPoints: [CGPoint] = []

        let result = await makePolicy(
            accessibilityActivate: { _ in
                activateCount += 1
                return .refused
            },
            refreshAndResolve: {
                .resolved(treeElement: refreshedTarget.treeElement, liveTarget: refreshedTarget)
            },
            activationPointDispatch: { point in
                dispatchedPoints.append(point)
                return false
            }
        ).apply(to: initialTarget)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(activateCount, 1)
        XCTAssertEqual(dispatchedPoints, [CGPoint(x: 52, y: 52)])
        XCTAssertEqual(result.activationTrace, ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 52, y: 52),
            tapActivationSucceeded: false
        )))
        XCTAssertDiagnostic(result.message, contains: [
            "activate failed: accessibilityActivate() declined after semantic refresh",
            "activation-point dispatch was attempted at the fresh accessibility activation point",
            "label=\"Refreshed Button\"",
            "actions=[activate]",
            "correction: target an element with primary accessibility activation",
        ])
        XCTAssertDiagnostic(result.message, doesNotContain: [
            "fall" + "back",
            "re" + "covery",
            "synthetic " + "tap",
            "synthetic" + "Tap",
        ])
    }

    private func makePolicy(
        accessibilityActivate: @escaping @MainActor (TheStash.LiveActionTarget) -> AccessibilityActionDispatcher.ActivateOutcome,
        refreshAndResolve: @escaping @MainActor () async -> ActivationPolicy.RefreshResult,
        activationPointDispatch: @escaping @MainActor (CGPoint) async -> Bool,
        showFingerprint: @escaping @MainActor (CGPoint) -> Void = { _ in },
        textEntryActivationFailure: @escaping @MainActor (
            InterfaceTree.Element,
            ActivationTrace
        ) async -> TheSafecracker.ActionDispatchOutcome? = { _, _ in nil }
    ) -> ActivationPolicy {
        ActivationPolicy(
            accessibilityActivate: accessibilityActivate,
            refreshAndResolve: refreshAndResolve,
            activationPointDispatch: activationPointDispatch,
            showFingerprint: showFingerprint,
            textEntryActivationFailure: { treeElement, trace in
                guard treeElement.element.traits.contains(.textEntry) else { return nil }
                return await textEntryActivationFailure(treeElement, trace)
            }
        )
    }

    private func makeLiveTarget(
        heistId: HeistId,
        label: String = "Target",
        traits: UIAccessibilityTraits = [],
        frame: CGRect = CGRect(x: 0, y: 0, width: 44, height: 44),
        activationPoint: CGPoint
    ) -> TheStash.LiveActionTarget {
        let element = AccessibilityElement.make(
            label: label,
            traits: traits,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: activationPoint,
            respondsToUserInteraction: false
        )
        let treeElement = InterfaceTree.Element(
            heistId: heistId,
            scrollMembership: nil,
            element: element
        )
        let object = ActivationObject()
        object.accessibilityFrame = frame
        return TheStash.LiveActionTarget(
            treeElement: treeElement,
            object: object,
            frame: frame,
            activationPoint: activationPoint
        )
    }

    private func XCTAssertDiagnostic(
        _ message: String?,
        contains fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let message else {
            XCTFail("Expected diagnostic message", file: file, line: line)
            return
        }
        for fragment in fragments {
            XCTAssertTrue(
                message.contains(fragment),
                "Expected diagnostic to contain '\(fragment)'. Message: \(message)",
                file: file,
                line: line
            )
        }
    }

    private func XCTAssertDiagnostic(
        _ message: String?,
        doesNotContain fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let message else {
            XCTFail("Expected diagnostic message", file: file, line: line)
            return
        }
        for fragment in fragments {
            XCTAssertFalse(
                message.contains(fragment),
                "Expected diagnostic to omit '\(fragment)'. Message: \(message)",
                file: file,
                line: line
            )
        }
    }
}

#endif

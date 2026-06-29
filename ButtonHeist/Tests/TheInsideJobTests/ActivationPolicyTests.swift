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
            .interactionResult(commandMethod: .activate)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.message, "element inflation failed [noRevealPath]: target has no reveal path")
    }

    func testElementInflationFailurePreservesElementNotFoundMethod() {
        let result = ElementInflation.ElementInflationFailure.notFound("no such element")
            .interactionResult(commandMethod: .activate)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.failureKind, .targetUnavailable)
        XCTAssertEqual(result.message, "element inflation failed [notFound]: no such element")
    }

    func testRefreshReresolveActivateSuccessStopsPolicy() async {
        let initialTarget = makeLiveTarget(heistId: "initial", activationPoint: CGPoint(x: 10, y: 20))
        let refreshedTarget = makeLiveTarget(heistId: "refreshed", activationPoint: CGPoint(x: 30, y: 40))
        var events: [String] = []
        var dispatchedPoints: [CGPoint] = []

        let result = await makePolicy(
            accessibilityActivate: { target in
                events.append("activate:\(target.screenElement.heistId)")
                return .success
            },
            refreshAndResolve: {
                events.append("refresh")
                return .resolved(screenElement: refreshedTarget.screenElement, liveTarget: refreshedTarget)
            },
            activationPointDispatch: { point in
                dispatchedPoints.append(point)
                return true
            }
        ).apply(to: initialTarget)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(events, ["refresh", "activate:refreshed"])
        XCTAssertTrue(dispatchedPoints.isEmpty)
        XCTAssertEqual(result.activationTrace, ActivationTrace(
            axActivateReturned: true,
            tapActivationDispatched: false
        ))
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
        XCTAssertEqual(result.activationTrace, ActivationTrace(
            axActivateReturned: nil,
            tapActivationDispatched: false
        ))
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
                .resolved(screenElement: refreshedTarget.screenElement, liveTarget: refreshedTarget)
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
        XCTAssertEqual(result.activationTrace, ActivationTrace(
            axActivateReturned: false,
            tapActivationDispatched: true,
            tapActivationPoint: ScreenPoint(x: 30, y: 40),
            tapActivationSucceeded: true
        ))
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
                .resolved(screenElement: refreshedTarget.screenElement, liveTarget: refreshedTarget)
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
        XCTAssertEqual(result.activationTrace, ActivationTrace(
            axActivateReturned: false,
            tapActivationDispatched: true,
            tapActivationPoint: ScreenPoint(x: 52, y: 52),
            tapActivationSucceeded: false
        ))
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
        activationPointDispatch: @escaping @MainActor (CGPoint) async -> Bool
    ) -> ActivationPolicy {
        ActivationPolicy(
            accessibilityActivate: accessibilityActivate,
            refreshAndResolve: refreshAndResolve,
            activationPointDispatch: activationPointDispatch
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
        let screenElement = TheStash.ScreenElement(
            heistId: heistId,
            scrollMembership: nil,
            element: element
        )
        let object = ActivationObject()
        object.accessibilityFrame = frame
        return TheStash.LiveActionTarget(
            screenElement: screenElement,
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

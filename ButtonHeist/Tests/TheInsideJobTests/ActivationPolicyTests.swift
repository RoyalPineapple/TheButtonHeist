#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class ActivationPolicyTests: XCTestCase {

    private final class ActivationObject: NSObject {}

    func testSemanticActionabilityFailureMapsNoRevealPathToCommandMethod() {
        let result = SemanticActionability.SemanticActionabilityFailure.noRevealPath("target has no reveal path")
            .interactionResult(commandMethod: .syntheticTap)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .syntheticTap)
        XCTAssertEqual(result.message, "semantic actionability failed [noRevealPath]: target has no reveal path")
    }

    func testSemanticActionabilityFailurePreservesElementNotFoundMethod() {
        let result = SemanticActionability.SemanticActionabilityFailure.notFound("no such element")
            .interactionResult(commandMethod: .syntheticTap)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .syntheticTap)
        XCTAssertEqual(result.failureKind, .targetUnavailable)
        XCTAssertEqual(result.message, "semantic actionability failed [notFound]: no such element")
    }

    func testAccessibilityActivateSuccessStopsPolicy() async {
        let initialTarget = makeLiveTarget(heistId: "initial", activationPoint: CGPoint(x: 10, y: 20))
        var activateCount = 0
        var didRefresh = false
        var tappedPoints: [CGPoint] = []

        let result = await makePolicy(
            activate: { _ in
                activateCount += 1
                return .success
            },
            refreshAndResolve: {
                didRefresh = true
                return .failure(.failure(.activate, message: "unexpected refresh"))
            },
            syntheticTap: { point in
                tappedPoints.append(point)
                return true
            }
        ).apply(to: initialTarget)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(activateCount, 1)
        XCTAssertFalse(didRefresh)
        XCTAssertTrue(tappedPoints.isEmpty)
    }

    func testRefreshReresolveRetryCanSucceed() async {
        let initialTarget = makeLiveTarget(heistId: "initial", activationPoint: CGPoint(x: 10, y: 20))
        let retryTarget = makeLiveTarget(heistId: "retry", activationPoint: CGPoint(x: 30, y: 40))
        var activateCount = 0
        var tappedPoints: [CGPoint] = []

        let result = await makePolicy(
            activate: { _ in
                activateCount += 1
                return activateCount == 1 ? .refused : .success
            },
            refreshAndResolve: {
                .resolved(screenElement: retryTarget.screenElement, liveTarget: retryTarget)
            },
            syntheticTap: { point in
                tappedPoints.append(point)
                return true
            }
        ).apply(to: initialTarget)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(activateCount, 2)
        XCTAssertTrue(tappedPoints.isEmpty)
    }

    func testRefreshReresolveFailureReturnsWithoutSyntheticTap() async {
        let initialTarget = makeLiveTarget(heistId: "initial", activationPoint: CGPoint(x: 10, y: 20))
        var activateCount = 0
        var tappedPoints: [CGPoint] = []

        let result = await makePolicy(
            activate: { _ in
                activateCount += 1
                return .refused
            },
            refreshAndResolve: {
                .failure(.failure(.activate, message: "retry actionability failed"))
            },
            syntheticTap: { point in
                tappedPoints.append(point)
                return true
            }
        ).apply(to: initialTarget)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.message, "retry actionability failed")
        XCTAssertEqual(activateCount, 1)
        XCTAssertTrue(tappedPoints.isEmpty)
    }

    func testSyntheticTapRecoveryCanSucceed() async {
        let initialTarget = makeLiveTarget(heistId: "initial", activationPoint: CGPoint(x: 10, y: 20))
        let retryTarget = makeLiveTarget(heistId: "retry", activationPoint: CGPoint(x: 30, y: 40))
        var activateCount = 0
        var tappedPoints: [CGPoint] = []

        let result = await makePolicy(
            activate: { _ in
                activateCount += 1
                return .refused
            },
            refreshAndResolve: {
                .resolved(screenElement: retryTarget.screenElement, liveTarget: retryTarget)
            },
            syntheticTap: { point in
                tappedPoints.append(point)
                return true
            }
        ).apply(to: initialTarget)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .syntheticTap)
        XCTAssertEqual(activateCount, 2)
        XCTAssertEqual(tappedPoints, [CGPoint(x: 30, y: 40)])
    }

    func testFinalFailureUsesRetryTargetAndFreshActivationPoint() async {
        let initialTarget = makeLiveTarget(heistId: "initial", activationPoint: CGPoint(x: 10, y: 20))
        let retryTarget = makeLiveTarget(
            heistId: "retry",
            label: "Retry Button",
            traits: .button,
            frame: CGRect(x: 12, y: 30, width: 80, height: 44),
            activationPoint: CGPoint(x: 52, y: 52)
        )
        var activateCount = 0
        var tappedPoints: [CGPoint] = []

        let result = await makePolicy(
            activate: { _ in
                activateCount += 1
                return .refused
            },
            refreshAndResolve: {
                .resolved(screenElement: retryTarget.screenElement, liveTarget: retryTarget)
            },
            syntheticTap: { point in
                tappedPoints.append(point)
                return false
            }
        ).apply(to: initialTarget)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(activateCount, 2)
        XCTAssertEqual(tappedPoints, [CGPoint(x: 52, y: 52)])
        XCTAssertDiagnostic(result.message, contains: [
            "activate failed: accessibilityActivate returned false after semantic refresh",
            "synthetic tap at fresh activation point also failed",
            "heistId=\"retry\"",
            "label=\"Retry Button\"",
        ])
    }

    private func makePolicy(
        activate: @escaping @MainActor (TheStash.LiveActionTarget) -> TheStash.ActivateOutcome,
        refreshAndResolve: @escaping @MainActor () async -> ActivationPolicy.RefreshResult,
        syntheticTap: @escaping @MainActor (CGPoint) async -> Bool
    ) -> ActivationPolicy {
        ActivationPolicy(
            activate: activate,
            refreshAndResolve: refreshAndResolve,
            syntheticTap: syntheticTap
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
            contentSpaceOrigin: nil,
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
}

#endif

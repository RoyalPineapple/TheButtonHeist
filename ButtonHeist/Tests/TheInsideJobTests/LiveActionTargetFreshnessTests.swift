#if canImport(UIKit)
import UIKit
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import ThePlans
@testable import TheScore

@MainActor
final class LiveActionTargetFreshnessTests: XCTestCase {

    func testCaptureReplacementReacquiresSameSemanticTargetBeforeDispatch() async throws {
        let stash = TheStash(tripwire: TheTripwire())
        let oldObject = ActivationTrackingView()
        let liveTarget = try installTarget(
            in: stash,
            heistId: "checkout",
            object: oldObject
        )
        let originalCaptureToken = liveTarget.captureToken
        let replacementObject = ActivationTrackingView()
        let replacement = try installTarget(
            in: stash,
            heistId: "checkout",
            object: replacementObject
        )
        XCTAssertNotEqual(replacement.captureToken, originalCaptureToken)

        switch stash.dispatchOnFreshLiveActionTarget(liveTarget, operation: { target in
            (
                target.object.accessibilityActivate(),
                ObjectIdentifier(target.object),
                target.captureToken,
                target.treeElement.heistId
            )
        }) {
        case .success(let evidence):
            XCTAssertTrue(evidence.0)
            XCTAssertEqual(evidence.1, ObjectIdentifier(replacementObject))
            XCTAssertEqual(evidence.2, replacement.captureToken)
            XCTAssertEqual(evidence.3, liveTarget.treeElement.heistId)
        case .failure(let staleness):
            XCTFail("Expected current-target reacquisition, got \(staleness)")
        }
        XCTAssertEqual(oldObject.activationCount, 0)
        XCTAssertEqual(replacementObject.activationCount, 1)
    }

    func testCaptureReplacementWithoutSameHeistIDReturnsTypedStaleTarget() async throws {
        let stash = TheStash(tripwire: TheTripwire())
        let oldObject = ActivationTrackingView()
        let liveTarget = try installTarget(
            in: stash,
            heistId: "checkout",
            object: oldObject
        )
        _ = try installTarget(
            in: stash,
            heistId: "replacement",
            object: ActivationTrackingView()
        )
        var invoked = false

        let dispatch = stash.dispatchOnFreshLiveActionTarget(liveTarget) { target in
            invoked = true
            return target.object.accessibilityActivate()
        }

        guard case .failure(.semanticTargetUnavailable(let heistId)) = dispatch else {
            return XCTFail("Expected a typed stale semantic-target failure")
        }
        XCTAssertEqual(heistId, "checkout")
        XCTAssertFalse(invoked)
        XCTAssertEqual(oldObject.activationCount, 0)
    }

    func testFreshDispatchReturnsOnlyReacquiredValueEvidence() async throws {
        let stash = TheStash(tripwire: TheTripwire())
        let originalFrame = CGRect(x: 20, y: 40, width: 120, height: 44)
        let replacementFrame = CGRect(x: 200, y: 300, width: 80, height: 60)
        let liveTarget = try installTarget(
            in: stash,
            heistId: "checkout",
            object: ActivationTrackingView(),
            frame: originalFrame
        )
        let replacement = try installTarget(
            in: stash,
            heistId: "checkout",
            object: ActivationTrackingView(),
            frame: replacementFrame
        )
        let preparation = stash.dispatchOnFreshLiveActionTarget(liveTarget) { target in
            PreparedGeometryEvidence(
                point: target.activationPoint,
                captureToken: target.captureToken
            )
        }

        switch preparation {
        case .success(let evidence):
            XCTAssertEqual(evidence.point, CGPoint(x: replacementFrame.midX, y: replacementFrame.midY))
            XCTAssertNotEqual(evidence.point, CGPoint(x: originalFrame.midX, y: originalFrame.midY))
            XCTAssertEqual(evidence.captureToken, replacement.captureToken)
        case .failure(let staleness):
            XCTFail("Expected current-geometry preparation, got \(staleness)")
        }
    }

    func testContainerCaptureReplacementReacquiresCurrentFrameBeforeDispatch() async throws {
        let stash = TheStash(tripwire: TheTripwire())
        let original = try installContainer(
            in: stash,
            identifier: "menu",
            object: UIScrollView(),
            frame: CGRect(x: 0, y: 80, width: 320, height: 400)
        )
        let replacementObject = UIScrollView()
        let replacement = try installContainer(
            in: stash,
            identifier: "menu",
            object: replacementObject,
            frame: CGRect(x: 0, y: 140, width: 320, height: 400)
        )
        let dispatch = stash.dispatchOnFreshLiveContainerTarget(original) { current in
            ContainerDispatchEvidence(
                objectID: ObjectIdentifier(current.object),
                frame: current.frame,
                captureToken: current.captureToken
            )
        }

        switch dispatch {
        case .success(let evidence):
            XCTAssertEqual(evidence.objectID, ObjectIdentifier(replacementObject))
            XCTAssertEqual(evidence.frame, replacement.frame)
            XCTAssertEqual(evidence.captureToken, replacement.captureToken)
        case .failure(let staleness):
            XCTFail("Expected current-container reacquisition, got \(staleness)")
        }
    }

    func testContainerSemanticReplacementReturnsTypedStalenessWithoutInvocation() async throws {
        let stash = TheStash(tripwire: TheTripwire())
        let original = try installContainer(
            in: stash,
            identifier: "menu",
            object: UIScrollView(),
            frame: CGRect(x: 0, y: 80, width: 320, height: 400)
        )
        _ = try installContainer(
            in: stash,
            identifier: "checkout",
            object: UIScrollView(),
            frame: CGRect(x: 0, y: 80, width: 320, height: 400)
        )
        var invoked = false

        let dispatch = stash.dispatchOnFreshLiveContainerTarget(original) { _ in
            invoked = true
            return true
        }

        guard case .failure(.semanticTargetUnavailable(let path)) = dispatch else {
            return XCTFail("Expected typed stale-container evidence")
        }
        XCTAssertEqual(path, TreePath([0]))
        XCTAssertFalse(invoked)
    }

    private func installTarget(
        in stash: TheStash,
        heistId: HeistId,
        object: NSObject,
        frame: CGRect = CGRect(x: 20, y: 40, width: 120, height: 44)
    ) throws -> TheStash.LiveActionTarget {
        let element = AccessibilityElement.make(
            label: "Checkout",
            traits: .button,
            frame: frame
        )
        stash.installScreenForTesting(.makeForTests(
            elements: [(element, heistId)],
            objects: [heistId: object]
        ))
        let treeElement = try XCTUnwrap(stash.latestObservation.tree.findElement(heistId: heistId))
        guard case .resolved(let target) = stash.resolveLiveActionTarget(for: treeElement) else {
            throw LiveActionTargetFixtureError.unavailable
        }
        return target
    }

    private func installContainer(
        in stash: TheStash,
        identifier: ContainerName,
        object: NSObject,
        frame: CGRect
    ) throws -> TheStash.LiveContainerTarget {
        let path = TreePath([0])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Menu", value: nil),
            identifier: identifier.rawValue,
            scrollableContentSize: AccessibilitySize(width: 320, height: 1_200),
            frame: AccessibilityRect(frame)
        )
        let semanticContainer = InterfaceTree.Container(
            container: container,
            path: path,
            containerName: identifier,
            contentFrame: frame
        )
        stash.recordParsedObservedEvidence(InterfaceObservation.makeForTests(
            tree: InterfaceTree(elements: [:], containers: [path: semanticContainer]),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [.container(container, children: [])],
                containerNamesByPath: [path: identifier],
                elementRefs: [:],
                containerRefsByPath: [path: .init(object: object)],
                containerContentFramesByPath: [path: ContentRect(frame)],
                firstResponderHeistId: nil
            )
        ))
        guard case .resolved(let target) = stash.resolveLiveContainerTarget(for: semanticContainer) else {
            throw LiveActionTargetFixtureError.unavailable
        }
        return target
    }
}

private struct PreparedGeometryEvidence: Sendable {
    let point: CGPoint
    let captureToken: InterfaceCaptureToken
}

private struct ContainerDispatchEvidence: Sendable {
    let objectID: ObjectIdentifier
    let frame: CGRect
    let captureToken: InterfaceCaptureToken
}

private enum LiveActionTargetFixtureError: Error {
    case unavailable
}

private final class ActivationTrackingView: UIView {
    private(set) var activationCount = 0

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return true
    }
}

#endif // canImport(UIKit)

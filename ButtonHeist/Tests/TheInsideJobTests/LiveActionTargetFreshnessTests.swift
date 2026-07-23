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
        let vault = TheVault(tripwire: TheTripwire())
        let oldObject = ActivationTrackingView()
        let liveTarget = try await installTarget(
            in: vault,
            heistId: "checkout",
            object: oldObject
        )
        let originalCaptureToken = liveTarget.captureID
        let replacementObject = ActivationTrackingView()
        let replacement = try await installTarget(
            in: vault,
            heistId: "checkout",
            object: replacementObject
        )
        XCTAssertNotEqual(replacement.captureID, originalCaptureToken)

        switch vault.dispatchOnFreshLiveActionTarget(liveTarget, operation: { target in
            (
                target.object.accessibilityActivate(),
                ObjectIdentifier(target.object),
                target.captureID,
                target.treeElement.heistId
            )
        }) {
        case .success(let evidence):
            XCTAssertTrue(evidence.0)
            XCTAssertEqual(evidence.1, ObjectIdentifier(replacementObject))
            XCTAssertEqual(evidence.2, replacement.captureID)
            XCTAssertEqual(evidence.3, liveTarget.treeElement.heistId)
        case .failure(let staleness):
            XCTFail("Expected current-target reacquisition, got \(staleness)")
        }
        XCTAssertEqual(oldObject.activationCount, 0)
        XCTAssertEqual(replacementObject.activationCount, 1)
    }

    func testCaptureReplacementWithoutSameHeistIDReturnsTypedStaleTarget() async throws {
        let vault = TheVault(tripwire: TheTripwire())
        let oldObject = ActivationTrackingView()
        let liveTarget = try await installTarget(
            in: vault,
            heistId: "checkout",
            object: oldObject
        )
        _ = try await installTarget(
            in: vault,
            heistId: "replacement",
            object: ActivationTrackingView()
        )
        var invoked = false

        let dispatch = vault.dispatchOnFreshLiveActionTarget(liveTarget) { target in
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
        let vault = TheVault(tripwire: TheTripwire())
        let originalFrame = CGRect(x: 20, y: 40, width: 120, height: 44)
        let replacementFrame = CGRect(x: 200, y: 300, width: 80, height: 60)
        let liveTarget = try await installTarget(
            in: vault,
            heistId: "checkout",
            object: ActivationTrackingView(),
            frame: originalFrame
        )
        let replacement = try await installTarget(
            in: vault,
            heistId: "checkout",
            object: ActivationTrackingView(),
            frame: replacementFrame
        )
        let preparation = vault.dispatchOnFreshLiveActionTarget(liveTarget) { target in
            PreparedGeometryEvidence(
                point: target.activationPoint,
                captureID: target.captureID
            )
        }

        switch preparation {
        case .success(let evidence):
            XCTAssertEqual(evidence.point, CGPoint(x: replacementFrame.midX, y: replacementFrame.midY))
            XCTAssertNotEqual(evidence.point, CGPoint(x: originalFrame.midX, y: originalFrame.midY))
            XCTAssertEqual(evidence.captureID, replacement.captureID)
        case .failure(let staleness):
            XCTFail("Expected current-geometry preparation, got \(staleness)")
        }
    }

    func testContainerCaptureReplacementReacquiresCurrentFrameBeforeDispatch() async throws {
        let vault = TheVault(tripwire: TheTripwire())
        let original = try installContainer(
            in: vault,
            identifier: "menu",
            object: UIScrollView(),
            frame: CGRect(x: 0, y: 80, width: 320, height: 400)
        )
        let replacementObject = UIScrollView()
        let replacement = try installContainer(
            in: vault,
            identifier: "menu",
            object: replacementObject,
            frame: CGRect(x: 0, y: 140, width: 320, height: 400)
        )
        let dispatch = vault.dispatchOnFreshLiveContainerTarget(original) { current in
            ContainerDispatchEvidence(
                objectID: ObjectIdentifier(current.object),
                frame: current.frame,
                captureID: current.captureID
            )
        }

        switch dispatch {
        case .success(let evidence):
            XCTAssertEqual(evidence.objectID, ObjectIdentifier(replacementObject))
            XCTAssertEqual(evidence.frame, replacement.frame)
            XCTAssertEqual(evidence.captureID, replacement.captureID)
        case .failure(let staleness):
            XCTFail("Expected current-container reacquisition, got \(staleness)")
        }
    }

    func testContainerSemanticReplacementReturnsTypedStalenessWithoutInvocation() async throws {
        let vault = TheVault(tripwire: TheTripwire())
        let original = try installContainer(
            in: vault,
            identifier: "menu",
            object: UIScrollView(),
            frame: CGRect(x: 0, y: 80, width: 320, height: 400)
        )
        _ = try installContainer(
            in: vault,
            identifier: "checkout",
            object: UIScrollView(),
            frame: CGRect(x: 0, y: 80, width: 320, height: 400)
        )
        var invoked = false

        let dispatch = vault.dispatchOnFreshLiveContainerTarget(original) { _ in
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
        in vault: TheVault,
        heistId: HeistId,
        object: NSObject,
        frame: CGRect = CGRect(x: 20, y: 40, width: 120, height: 44)
    ) async throws -> TheVault.LiveActionTarget {
        let element = AccessibilityElement.make(
            label: "Checkout",
            traits: .button,
            frame: frame
        )
        await vault.installObservationForTesting(.makeForTests(
            elements: [(element, heistId)],
            objects: [heistId: object]
        ))
        let treeElement = try XCTUnwrap(vault.latestObservation.tree.findElement(heistId: heistId))
        guard case .resolved(let target) = vault.resolveLiveActionTarget(for: treeElement) else {
            throw LiveActionTargetFixtureError.unavailable
        }
        return target
    }

    private func installContainer(
        in vault: TheVault,
        identifier: ContainerName,
        object: NSObject,
        frame: CGRect
    ) throws -> TheVault.LiveContainerTarget {
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
        vault.observeInterface(InterfaceObservation.makeForTests(
            tree: InterfaceTree(elements: [:], containers: [path: semanticContainer]),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [.container(container, children: [])],
                containerNamesByPath: [path: identifier],
                elementRefs: [:],
                containerRefsByPath: [path: .init(object: object)],
                containerContentFramesByPath: [path: try ContentRect(validating: frame)],
                firstResponderHeistId: nil
            )
        ))
        guard case .resolved(let target) = vault.resolveLiveContainerTarget(for: semanticContainer) else {
            throw LiveActionTargetFixtureError.unavailable
        }
        return target
    }
}

private struct PreparedGeometryEvidence: Sendable {
    let point: CGPoint
    let captureID: InterfaceCaptureID
}

private struct ContainerDispatchEvidence: Sendable {
    let objectID: ObjectIdentifier
    let frame: CGRect
    let captureID: InterfaceCaptureID
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

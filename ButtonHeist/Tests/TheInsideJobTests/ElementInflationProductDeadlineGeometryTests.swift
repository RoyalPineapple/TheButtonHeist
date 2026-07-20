#if canImport(UIKit)
import XCTest
import ThePlans

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension ElementInflationProductTests {

    // MARK: - Deadline and Geometry

    func testHandoffTickCountFollowsNestedScrollMembershipGraph() {
        let outerPath = TreePath([0])
        let innerPath = TreePath([0, 0])
        let element = InterfaceTree.Element(
            heistId: "nested_target",
            scrollMembership: .init(containerPath: innerPath, index: nil),
            element: AccessibilityElement.make(label: "Nested Target", traits: .button)
        )
        let container = AccessibilityContainer(
            type: .none,
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 640))
        )
        let tree = InterfaceTree(
            elements: [element.heistId: element],
            containers: [
                outerPath: .init(
                    container: container,
                    path: outerPath,
                    containerName: nil,
                    contentFrame: nil
                ),
                innerPath: .init(
                    container: container,
                    path: innerPath,
                    containerName: nil,
                    contentFrame: nil,
                    scrollMembership: .init(containerPath: outerPath, index: nil)
                ),
            ]
        )

        XCTAssertEqual(
            ElementInflation.handoffTickCount(
                for: InterfaceTree.Element(
                    heistId: "visible_target",
                    scrollMembership: nil,
                    element: AccessibilityElement.make(label: "Visible Target", traits: .button)
                ),
                in: .empty
            ),
            2,
            "A direct target keeps the existing two-tick minimum"
        )
        XCTAssertEqual(
            ElementInflation.handoffTickCount(for: element, in: tree),
            3,
            "Two scroll memberships plus one geometry confirmation require three ticks"
        )
    }

    func testCommittedTargetRefreshReplacesStaleLiveEvidenceAndStartsANewDeadline() async throws {
        let heistId: HeistId = "committed_refresh_target"
        let element = makeElement(
            label: "Committed Refresh Target",
            identifier: heistId.rawValue
        )
        let staleObject = UIButton(frame: CGRect(x: 20, y: 20, width: 160, height: 44))
        brains.vault.installObservationForTesting(.makeForTests([
            .init(element, heistId: heistId, object: staleObject),
        ]))
        let treeElement = try XCTUnwrap(brains.vault.interfaceElement(heistId: heistId))
        guard case .resolved(let liveTarget) = brains.vault.resolveLiveActionTarget(for: treeElement) else {
            return XCTFail("Expected committed refresh fixture to have a live target")
        }
        let completedInflation = ElementInflation.InflatedElementTarget(
            target: try AccessibilityTarget.identifier(heistId.rawValue).resolve(in: .empty),
            treeElement: treeElement,
            liveTarget: liveTarget,
            deadline: SemanticObservationDeadline(start: RuntimeElapsed.now, timeoutSeconds: 0),
            resolution: ActionSubjectResolution(origin: .visible)
        )
        brains.stopSemanticObservation()
        let replacementObject = UIButton(frame: CGRect(x: 20, y: 20, width: 160, height: 44))
        visibleObservationSource.observation = .makeForTests([
            .init(element, heistId: heistId, object: replacementObject),
        ])
        var now = RuntimeElapsed.now
        let deadlineStart = now
        brains.navigation.elementInflation.geometryEnvironment = .init(
            now: { now },
            awaitFrame: { now = now.advanced(by: .milliseconds(10)) }
        )

        let result = await brains.navigation.elementInflation.refreshCommittedTarget(
            completedInflation.committedTarget,
            method: .activate
        )

        guard case .inflated(let refreshedTarget) = result else {
            return XCTFail("Expected a new refresh handoff, got \(result)")
        }
        XCTAssertEqual(refreshedTarget.treeElement.heistId, heistId)
        XCTAssertTrue(refreshedTarget.liveTarget.object === replacementObject)
        XCTAssertFalse(refreshedTarget.liveTarget.object === staleObject)
        XCTAssertEqual(refreshedTarget.deadline.start, deadlineStart)
        XCTAssertEqual(refreshedTarget.deadline.timeoutSeconds, 2)
    }

    func testMovingGeometryRequiresOneMatchingQuietSample() {
        let initial = geometrySample(x: 20)
        let moved = geometrySample(x: 44)
        let stabilization = ElementInflation.LiveGeometryStabilization(
            initial: initial,
            requiresOnscreen: true
        )

        guard case .awaiting(let movedStabilization) = stabilization.reduce(
            .sample(moved, viewport: geometryViewport)
        ) else {
            return XCTFail("Moving geometry must restart the quiet window")
        }
        guard case .stable = movedStabilization.reduce(.sample(moved, viewport: geometryViewport)) else {
            return XCTFail("One unchanged sample must complete the quiet window")
        }
    }

    func testOffscreenActivationPointAfterPlacementIsTerminal() {
        let sample = geometrySample(x: 20)
        let stabilization = ElementInflation.LiveGeometryStabilization(
            initial: sample,
            requiresOnscreen: true
        )

        guard case .offscreen = stabilization.reduce(.sample(sample, viewport: .zero)) else {
            return XCTFail("An offscreen activation point must fail after placement")
        }
    }

    func testGeometryStabilizationDeadlineIsTerminal() {
        let stabilization = ElementInflation.LiveGeometryStabilization(
            initial: geometrySample(x: 20),
            requiresOnscreen: true
        )

        guard case .timedOut = stabilization.reduce(.deadlineExpired) else {
            return XCTFail("The operation deadline must terminate geometry stabilization")
        }
    }

    func testGeometryStabilizationCancellationIsTerminal() {
        let stabilization = ElementInflation.LiveGeometryStabilization(
            initial: geometrySample(x: 20),
            requiresOnscreen: true
        )

        guard case .cancelled = stabilization.reduce(.cancelled) else {
            return XCTFail("Cancellation must terminate geometry stabilization")
        }
    }

    private func geometrySample(x: CGFloat) -> ElementInflation.LiveGeometrySample {
        ElementInflation.LiveGeometrySample(
            frame: CGRect(x: x, y: 40, width: 100, height: 44),
            activationPoint: CGPoint(x: x + 50, y: 62)
        )
    }

    private var geometryViewport: CGRect {
        CGRect(x: 0, y: 0, width: 320, height: 640)
    }
    func testMissingRevealPathIsBoundedByInflationDeadline() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "live_decoy_unrevealable_submit",
            label: "Live Decoy"
        )
        defer { fixture.cleanup() }
        try seedOffViewportTarget(
            fixture,
            semanticIdentifier: "unrevealable_submit",
            semanticLabel: "Submit Order",
            scrollContainerPathOverride: TreePath([99]),
            refreshesFromUIKit: false
        )

        let result = await brains.executeRuntimeAction(
            try HeistActionCommand.activate(
                .element(.identifier("unrevealable_submit"), traits: [.button])
            ).resolve(in: .empty)
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .activate)
        XCTAssertDiagnostic(result.message, contains: [
            "element inflation failed [noRevealPath]",
            "no live scrollable ancestor",
            "expectedScrollContainerPath=[99]",
            "available live scroll containers:",
            "no reveal path appeared before the action deadline",
        ])
        XCTAssertFalse(result.message?.localizedCaseInsensitiveContains("scroll first") ?? false)
        XCTAssertFalse(result.message?.contains("get_interface") ?? false)
        XCTAssertEqual(fixture.target.activationCount, 0)
    }

}

#endif // canImport(UIKit)

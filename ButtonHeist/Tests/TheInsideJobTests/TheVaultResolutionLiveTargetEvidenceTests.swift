#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension TheVaultResolutionTests {

    func testContainerTargetResolutionUsesCommittedSemanticContainers() async throws {
        let path = TreePath([0, 1])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: "actions",
            frame: AccessibilityRect(CGRect(x: 0, y: 900, width: 240, height: 80)),
            customActions: [.init(name: "Archive")]
        )
        await bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [:],
                containers: [
                    path: .init(
                        container: container,
                        path: path,
                        containerName: "semantic_actions__actions",
                        contentFrame: CGRect(x: 0, y: 900, width: 240, height: 80)
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests()
        ))

        let result = bagman.resolveTarget(try resolvedTarget(
            .container(.identifier("actions"))
        ))
        switch result {
        case .resolved(.container(let resolved)):
            XCTAssertEqual(resolved.path, path)
            XCTAssertEqual(resolved.containerName, "semantic_actions__actions")
            XCTAssertEqual(resolved.contentFrame?.origin.y, 900)
        case .resolved(.element), .notFound, .ambiguous:
            XCTFail("Expected semantic container resolution, got \(result.diagnostics)")
        }
    }

    func testContainerTargetResolutionReportsStructuredFacts() async throws {
        let primaryPath = TreePath([0, 1])
        let secondaryPath = TreePath([0, 2])
        await bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [:],
                containers: [
                    primaryPath: .init(
                        container: AccessibilityContainer(
                            type: .semanticGroup(label: "Actions", value: nil), identifier: "primary",
                            frame: AccessibilityRect(CGRect(x: 0, y: 120, width: 240, height: 80))
                        ),
                        path: primaryPath,
                        containerName: "actions_primary",
                        contentFrame: CGRect(x: 0, y: 120, width: 240, height: 80)
                    ),
                    secondaryPath: .init(
                        container: AccessibilityContainer(
                            type: .semanticGroup(label: "Actions", value: nil), identifier: "secondary",
                            frame: AccessibilityRect(CGRect(x: 0, y: 240, width: 240, height: 80))
                        ),
                        path: secondaryPath,
                        containerName: "actions_secondary",
                        contentFrame: CGRect(x: 0, y: 240, width: 240, height: 80)
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests()
        ))

        let predicate = ContainerPredicate.matching(
            .type(.semanticGroup),
            .semantic(.label("Actions"))
        )
        let ambiguous = bagman.resolveTarget(try resolvedTarget(
            .container(predicate)
        ))
        guard case .ambiguous(let facts) = ambiguous else {
            XCTFail("Expected structured ambiguity, got \(ambiguous)")
            return
        }
        XCTAssertEqual(facts.matchedCount, 2)
        XCTAssertEqual(facts.resolutionScope, .interface)
        let ambiguousMatches = try XCTUnwrap(facts.containerMatches)
        XCTAssertEqual(
            ambiguousMatches.exactMatches.map { $0.container.containerPredicateFacts.identifier },
            ["primary", "secondary"]
        )
        XCTAssertEqual(ambiguousMatches.exactMatches.map(\.containerName), ["actions_primary", "actions_secondary"])
        XCTAssertTrue(ambiguous.diagnostics.contains("container target is ambiguous across 2 containers"))
        XCTAssertFalse(ambiguous.diagnostics.contains("containerName"))

        let outOfRange = bagman.resolveTarget(try resolvedTarget(
            .container(predicate, ordinal: 3)
        ))
        guard case .notFound(let notFoundFacts) = outOfRange else {
            XCTFail("Expected structured ordinal miss, got \(outOfRange)")
            return
        }
        XCTAssertEqual(notFoundFacts.reason, .ordinalOutOfRange(requested: 3, matchCount: 2))
        XCTAssertEqual(notFoundFacts.resolutionScope, .interface)
        XCTAssertEqual(notFoundFacts.containerMatches?.exactMatches.map(\.path), [primaryPath, secondaryPath])
        XCTAssertTrue(outOfRange.diagnostics.contains("container target ordinal 3"))
        XCTAssertTrue(outOfRange.diagnostics.contains("target an element inside the intended region"))
    }

    func testGeneratedConcreteTargetUsesMinimumPredicateSelector() async throws {
        let selected = element(label: "Mode", value: "A", traits: [.button, .selected])
        let other = element(label: "Mode", value: "B", traits: [.button, .selected])
        await bagman.installObservationForTesting(InterfaceObservation.makeForTests(elements: [
            (selected, "mode_a"),
            (other, "mode_b"),
        ]))

        let treeElement = try XCTUnwrap(bagman.interfaceElement(heistId: "mode_a"))

        XCTAssertEqual(
            bagman.minimumUniqueTarget(for: treeElement),
            AccessibilityTarget.element(
                .label("Mode"),
                .traits([.button]),
                .value("A")
            )
        )
    }

    // MARK: - Live Geometry Replay

    func testMatcherTargetAcquiresFreshLiveGeometry() async throws {
        let sourceFrame = CGRect(x: 10, y: 20, width: 80, height: 44)
        let sourcePoint = CGPoint(x: 50, y: 42)
        let freshFrame = CGRect(x: 120, y: 240, width: 80, height: 44)
        let freshPoint = CGPoint(x: 160, y: 262)
        let currentElement = AccessibilityElement.make(
            label: "Quantity",
            value: "1",
            identifier: "quantity_stepper",
            traits: .adjustable,
            shape: .frame(AccessibilityRect(freshFrame)),
            activationPoint: freshPoint
        )
        let object = UIAccessibilityElement(accessibilityContainer: NSObject())
        object.accessibilityFrame = sourceFrame
        object.accessibilityActivationPoint = sourcePoint
        await bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [(currentElement, "quantity_1")],
            objects: ["quantity_1": object]
        ))

        let executableTarget = AccessibilityTarget.element(.identifier("quantity_stepper"))

        guard case .predicate(let matcher, let ordinal) = executableTarget else {
            XCTFail("Expected semantic replay target to carry matcher identity, got \(executableTarget)")
            return
        }
        XCTAssertEqual(matcher.checks, [.identifier(.exact("quantity_stepper"))])
        XCTAssertNil(ordinal)

        guard let resolved = bagman.resolveTarget(try resolvedTarget(executableTarget)).resolvedElement else {
            XCTFail("Expected semantic replay selector to resolve against current observation")
            return
        }
        XCTAssertEqual(resolved.heistId, "quantity_1")

        guard case .resolved(let liveTarget) = bagman.resolveLiveActionTarget(for: resolved) else {
            XCTFail("Expected current accessibility capture to provide action geometry")
            return
        }
        XCTAssertEqual(liveTarget.frame, freshFrame)
        XCTAssertEqual(liveTarget.activationPoint, freshPoint)
        XCTAssertNotEqual(liveTarget.frame, object.accessibilityFrame)
        XCTAssertNotEqual(liveTarget.activationPoint, object.accessibilityActivationPoint)
        XCTAssertNotEqual(liveTarget.frame, sourceFrame)
        XCTAssertNotEqual(liveTarget.activationPoint, sourcePoint)
    }

    func testVisibleResolutionKeepsSettledSemanticsWhileLiveTargetUsesFreshGeometry() async throws {
        let staleFrame = CGRect(x: 32, y: 865, width: 240, height: 44)
        let stalePoint = CGPoint(x: staleFrame.midX, y: staleFrame.midY)
        let settledElement = AccessibilityElement.make(
            label: "Rotor Host",
            identifier: "rotor_host",
            traits: .staticText,
            shape: .frame(AccessibilityRect(staleFrame)),
            activationPoint: stalePoint,
            customRotors: [.init(name: "Errors")]
        )
        let liveObject = UIAccessibilityElement(accessibilityContainer: NSObject())
        liveObject.accessibilityFrame = staleFrame
        liveObject.accessibilityActivationPoint = stalePoint
        await bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [(settledElement, "rotor_host")],
            objects: ["rotor_host": liveObject]
        ))

        let freshFrame = CGRect(x: 32, y: 320, width: 240, height: 44)
        let freshPoint = CGPoint(x: freshFrame.midX, y: freshFrame.midY)
        let freshElement = AccessibilityElement.make(
            label: "Rotor Host",
            identifier: "rotor_host",
            traits: .staticText,
            shape: .frame(AccessibilityRect(freshFrame)),
            activationPoint: freshPoint,
            customRotors: [.init(name: "Errors")]
        )
        bagman.observeInterface(InterfaceObservation.makeForTests(
            elements: [(freshElement, "rotor_host")],
            objects: ["rotor_host": liveObject]
        ))

        let target = literalTarget(ResolvedElementPredicate.identifier("rotor_host"))
        let settled = try XCTUnwrap(bagman.resolveTarget(target).resolvedElement)
        XCTAssertEqual(settled.element.shape.frame, staleFrame)
        XCTAssertEqual(settled.element.bhResolvedActivationPoint, stalePoint)

        let visible = try XCTUnwrap(bagman.resolveVisibleTarget(target).resolvedElement)
        XCTAssertEqual(visible.element.shape.frame, staleFrame)
        XCTAssertEqual(visible.element.bhResolvedActivationPoint, stalePoint)

        guard case .resolved(let liveTarget) = bagman.resolveLiveActionTarget(for: settled) else {
            return XCTFail("Expected fresh live action target")
        }
        XCTAssertEqual(liveTarget.frame, freshFrame)
        XCTAssertEqual(liveTarget.activationPoint, freshPoint)
        XCTAssertNotEqual(liveTarget.frame, liveObject.accessibilityFrame)
        XCTAssertNotEqual(liveTarget.activationPoint, liveObject.accessibilityActivationPoint)
    }

    func testRawEvidenceRequiresCommittedHeistIdForLiveObjectAndGeometry() async throws {
        let committedId: HeistId = "committed_control"
        let rawId: HeistId = "raw_control"
        let settledFrame = CGRect(x: 20, y: 40, width: 120, height: 44)
        let settledElement = AccessibilityElement.make(
            label: "Shared Control",
            traits: .adjustable,
            frame: settledFrame
        )
        await bagman.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(settledElement, committedId)])
        )
        let target = try resolvedTarget(
            AccessibilityTarget.element(.label("Shared Control"), traits: [.adjustable])
        )
        let semanticTarget = try XCTUnwrap(bagman.resolveVisibleTarget(target).resolvedElement)

        let rawObject = NSObject()
        let rawFrame = CGRect(x: 80, y: 160, width: 180, height: 52)
        let rawElement = AccessibilityElement.make(
            label: "Shared Control",
            traits: .adjustable,
            frame: rawFrame
        )
        bagman.observeInterface(InterfaceObservation.makeForTests(
            elements: [(rawElement, rawId)],
            objects: [rawId: rawObject]
        ))

        XCTAssertNil(bagman.interfaceElement(heistId: rawId))
        XCTAssertEqual(bagman.resolveVisibleTarget(target).resolvedElement?.heistId, committedId)
        XCTAssertNil(bagman.liveInterfaceElement(heistId: committedId))
        guard case .objectUnavailable = bagman.resolveLiveActionTarget(for: semanticTarget) else {
            return XCTFail("Expected different-HeistId raw evidence to remain non-dispatchable")
        }

        bagman.observeInterface(InterfaceObservation.makeForTests(
            elements: [(rawElement, committedId)],
            objects: [committedId: rawObject]
        ))

        guard case .resolved(let liveTarget) = bagman.resolveLiveActionTarget(for: semanticTarget) else {
            return XCTFail("Expected committed identity to admit raw live evidence")
        }
        XCTAssertTrue(liveTarget.object === rawObject)
        XCTAssertEqual(liveTarget.treeElement.heistId, committedId)
        XCTAssertEqual(liveTarget.frame, rawFrame)
    }

    func testVisibleSettleCommitStripsLiveHandlesFromSettledProjection() async {
        let liveObject = UIAccessibilityElement(accessibilityContainer: NSObject())
        liveObject.accessibilityFrame = CGRect(x: 10, y: 10, width: 100, height: 44)
        let observation = InterfaceObservation.makeForTests(
            elements: [(element(label: "Save", traits: .button), "save")],
            objects: ["save": liveObject]
        )

        await bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        XCTAssertNotNil(bagman.liveObject(for: "save"))
        XCTAssertNil(LiveCapture.makeForTests(snapshot: bagman.interfaceTree.viewportCapture).object(for: "save"))
    }

    func testLiveContainerTargetAcquiresFreshGeometryFromLatestLiveCapture() async throws {
        let path = TreePath([0])
        let staleFrame = CGRect(x: 0, y: 800, width: 240, height: 80)
        let freshFrame = CGRect(x: 0, y: 120, width: 240, height: 80)
        let staleContainer = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: "actions",
            frame: AccessibilityRect(staleFrame)
        )
        let freshContainer = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: "actions",
            frame: AccessibilityRect(freshFrame)
        )
        let liveObject = NSObject()
        let settledObservationScreen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [:],
                containers: [
                    path: .init(
                        container: staleContainer,
                        path: path,
                        containerName: "actions",
                        contentFrame: staleFrame
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [.container(staleContainer, children: [])],
                containerNamesByPath: [path: "actions"],
                elementRefs: [:],
                containerRefsByPath: [:],
                containerContentFramesByPath: [path: try ContentRect(validating: staleFrame)],
                firstResponderHeistId: nil,
            )
        )
        await bagman.semanticObservationStream.commitDiscoveryObservationForTesting(settledObservationScreen)
        let liveScreen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [:],
                containers: [
                    path: .init(
                        container: freshContainer,
                        path: path,
                        containerName: "actions",
                        contentFrame: freshFrame
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [.container(freshContainer, children: [])],
                containerNamesByPath: [path: "actions"],
                elementRefs: [:],
                containerRefsByPath: [path: .init(object: liveObject)],
                containerContentFramesByPath: [path: try ContentRect(validating: freshFrame)],
                firstResponderHeistId: nil,
            )
        )
        bagman.observeInterface(liveScreen)

        let resolved = bagman.resolveTarget(try resolvedTarget(
            .container(.identifier("actions"))
        ))
        guard case .resolved(.container(let semanticTarget)) = resolved else {
            return XCTFail("Expected semantic container, got \(resolved.diagnostics)")
        }
        guard case .resolved(let liveTarget) = bagman.resolveLiveContainerTarget(for: semanticTarget) else {
            return XCTFail("Expected fresh live container target")
        }

        XCTAssertTrue(liveTarget.object === liveObject)
        XCTAssertEqual(liveTarget.containerTarget.container.frame.cgRect, staleFrame)
        XCTAssertEqual(liveTarget.frame, freshFrame)
        XCTAssertEqual(liveTarget.activationPoint, CGPoint(x: freshFrame.midX, y: freshFrame.midY))
    }

    func testViewportUpdatePreservesKnownDiscoveryUnionWhenRefreshingSameScreen() async throws {
        let controls = element(label: "Controls Demo", traits: .button)
        let customRotors = element(label: "Custom Rotors", traits: .button)
        let discovery = InterfaceObservation.makeForTests(
            elements: [(customRotors, "custom_rotors")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    controls,
                    heistId: "controls_demo",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        await bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        let refreshedBottom = InterfaceObservation.makeForTests(elements: [(customRotors, "custom_rotors")])
        await bagman.semanticObservationStream.commitVisibleObservationForTesting(refreshedBottom)

        XCTAssertEqual(bagman.viewportElementIDs, ["custom_rotors"])
        XCTAssertEqual(bagman.interfaceElementIDs, ["controls_demo", "custom_rotors"])
        XCTAssertEqual(
            bagman.resolveTarget(try resolvedTarget(
                AccessibilityTarget.element(.label("Controls Demo"), traits: [.button])
            )).resolvedElement?.heistId,
            "controls_demo"
        )
    }

    func testViewportUpdateDoesNotPreserveOffViewportMemoryForDisjointCommittedViewport() async {
        let bottom = element(label: "Bottom Row", traits: .button)
        let staleOffscreen = element(label: "Stale Row", traits: .button)
        let discovery = InterfaceObservation.makeForTests(
            elements: [(bottom, "bottom_row")],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    staleOffscreen,
                    heistId: "shared_row",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        await bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        let freshVisible = element(label: "Fresh Row", traits: .button)
        let refreshedTop = InterfaceObservation.makeForTests(elements: [(freshVisible, "shared_row")])
        await bagman.semanticObservationStream.commitVisibleObservationForTesting(refreshedTop)

        XCTAssertEqual(bagman.viewportElementIDs, ["shared_row"])
        XCTAssertEqual(bagman.interfaceElementIDs, ["shared_row"])
        XCTAssertEqual(bagman.interfaceElement(heistId: "shared_row")?.element.label, "Fresh Row")
        XCTAssertNil(bagman.interfaceElement(heistId: "bottom_row"))
    }

    func testViewportUpdateDropsDiscoveryMemoryWhenScreenIdChangesDespiteSharedVisibleElement() async {
        let previousHeader = element(label: "Controls Demo", traits: .header)
        let sharedPreviousAction = element(label: "Shared Action", traits: .button)
        let staleOffscreen = element(label: "Stale Offscreen", traits: .button)
        let previousDiscovery = InterfaceObservation.makeForTests(
            elements: [
                (previousHeader, "controls_demo"),
                (sharedPreviousAction, "shared_action"),
            ],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    staleOffscreen,
                    heistId: "stale_offscreen",
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )
        XCTAssertEqual(previousDiscovery.tree.id, "controls_demo")
        await bagman.semanticObservationStream.commitDiscoveryObservationForTesting(previousDiscovery)

        let currentHeader = element(label: "ButtonHeist Demo", traits: .header)
        let sharedCurrentAction = element(label: "Shared Action", traits: .button)
        let currentVisible = InterfaceObservation.makeForTests(elements: [
            (currentHeader, "buttonheist_demo"),
            (sharedCurrentAction, "shared_action"),
        ])
        XCTAssertEqual(currentVisible.tree.id, "buttonheist_demo")
        await bagman.semanticObservationStream.commitVisibleObservationForTesting(currentVisible)

        XCTAssertEqual(bagman.viewportElementIDs, ["buttonheist_demo", "shared_action"])
        XCTAssertEqual(bagman.interfaceElementIDs, ["buttonheist_demo", "shared_action"])
        XCTAssertNil(bagman.interfaceElement(heistId: "controls_demo"))
        XCTAssertNil(bagman.interfaceElement(heistId: "stale_offscreen"))
    }

}

#endif

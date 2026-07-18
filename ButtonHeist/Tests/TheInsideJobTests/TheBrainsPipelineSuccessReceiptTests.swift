#if canImport(UIKit)
import Foundation
import XCTest
import ThePlans
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension TheBrainsPipelineTests {

    // MARK: - Post-Action Success Path

    func testAdvertisedActivateNoChangeCanRemainSuccessful() async throws {
        let frame = CGRect(x: 424, y: 336, width: 928, height: 72)
        let element = AccessibilityElement.make(
            label: "Inert option",
            identifier: "inert_option",
            traits: .none,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: CGPoint(x: 888, y: 372),
            respondsToUserInteraction: true
        )
        let screen = InterfaceObservation.makeForTests(elements: [(element, HeistId(rawValue: "inert_option"))])
        brains.vault.installObservationForTesting(screen)
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(
                subjectEvidence: try activationSubjectEvidence(
                    target: .identifier("inert_option"),
                    element: element,
                    settledObservationSequence: before.settledObservationSequence
                )
            ),
            before: before,
            settleOutcome: settledOutcome(finalScreen: screen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "activate unexpectedly failed")
        XCTAssertEqual(result.method, .activate)
        XCTAssertNil(result.outcome.errorKind)
        XCTAssertNil(result.message)
        XCTAssertNotNil(result.accessibilityTrace)
        XCTAssertEqual(result.accessibilityTrace?.captures.first?.hash, before.capture.hash)
        XCTAssertNotNil(result.accessibilityTrace?.captures.last?.hash)
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 2)
        XCTAssertTrue(result.accessibilityTrace?.changeFacts.isEmpty == true)
    }

    func testViewportPostActionCommitPreservesDiscoveryMemory() async {
        let topScreen = makeScreen(elements: [
            ("Widget 0, Hardware", .button, "top_row"),
            ("Long List", .header, "long_list_header"),
        ])
        brains.vault.installObservationForTesting(topScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let bottomScreen = makeScreen(elements: [
            ("Widget 90, Hardware", .button, "bottom_row"),
            ("Long List", .header, "long_list_header"),
        ])
        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(method: .scrollToEdge),
            before: before,
            postActionCommitScope: .discovery,
            settleOutcome: settledOutcome(finalScreen: bottomScreen)
        )

        let labels = Set(brains.vault.interfaceTree.elements.values.compactMap(\.element.label))
        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertTrue(labels.contains("Widget 0, Hardware"), "Discovery commit should retain the previously observed page")
        XCTAssertTrue(labels.contains("Widget 90, Hardware"), "Discovery commit should include the newly observed page")
    }

    func testSyntheticTapNoChangeCanRemainSuccessful() async {
        let beforeScreen = makeScreen(elements: [("Map", .button, "map_button")])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(method: .syntheticTap),
            before: before,
            settleOutcome: settledOutcome(finalScreen: beforeScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "tap unexpectedly failed")
        XCTAssertEqual(result.method, .syntheticTap)
        XCTAssertNil(result.outcome.errorKind)
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 2)
        XCTAssertTrue(result.accessibilityTrace?.changeFacts.isEmpty == true)
    }

    func testActivateNoChangeAfterTapActivationDispatchRemainsSuccessfulAndLegible() async throws {
        let frame = CGRect(x: 424, y: 336, width: 928, height: 72)
        let element = AccessibilityElement.make(
            label: "Tap activated option",
            identifier: "tap_activated_option",
            traits: .none,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: CGPoint(x: 888, y: 372),
            respondsToUserInteraction: true
        )
        let screen = InterfaceObservation.makeForTests(elements: [(element, HeistId(rawValue: "tap_activated_option"))])
        brains.vault.installObservationForTesting(screen)
        let before = brains.postActionObservation.captureSemanticState()
        let activationTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 888, y: 372),
            tapActivationSucceeded: true
        ))

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(
                subjectEvidence: try activationSubjectEvidence(
                    target: .identifier("tap_activated_option"),
                    element: element,
                    settledObservationSequence: before.settledObservationSequence
                ),
                activationTrace: activationTrace
            ),
            before: before,
            settleOutcome: settledOutcome(finalScreen: screen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "activate unexpectedly failed")
        XCTAssertNil(result.outcome.errorKind)
        XCTAssertNil(result.message)
        XCTAssertEqual(result.activationTrace, activationTrace)
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 2)
        XCTAssertTrue(result.accessibilityTrace?.changeFacts.isEmpty == true)
    }

    func testActionResultWithDeltaSuccessReturnsTraceAfterElementChange() async {
        let beforeScreen = makeScreen(elements: [("Total", .staticText, "total")])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let afterScreen = makeScreen(elements: [("Total $12.00", .staticText, "total")])

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen, outcome: .settled(timeMs: 87))
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(result.settled, true)
        XCTAssertEqual(result.settleTimeMs, 87)
        XCTAssertNotNil(result.accessibilityTrace)
        XCTAssertNotNil(result.accessibilityTrace?.captures.last)
    }

    func testActionResultWithDeltaPreservesSubjectEvidence() async throws {
        let beforeScreen = makeScreen(elements: [("Delete", .button, "delete_button")])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let evidence = ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: try AccessibilityTarget.element(
                .label("Delete"),
                traits: [.button]
            ).resolve(in: .empty),
            element: HeistElement(
                description: "Delete",
                label: "Delete",
                value: nil,
                identifier: "delete_button",
                traits: [.button],
                frameX: 0,
                frameY: 0,
                frameWidth: 100,
                frameHeight: 44,
                actions: [.activate]
            ),
            resolution: ActionSubjectResolution(origin: .visible),
            settledObservationSequence: before.settledObservationSequence
        )

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(subjectEvidence: evidence),
            before: before,
            settleOutcome: settledOutcome(finalScreen: beforeScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(result.subjectEvidence, evidence)
    }

    func testActionFailurePreservesResolvedSubjectEvidence() async throws {
        let beforeScreen = makeScreen(elements: [("Delete", .button, "delete_button")])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let target = try AccessibilityTarget.element(
            .label("Delete"),
            traits: [.button]
        ).resolve(in: .empty)
        let evidence = ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: target,
            element: HeistElement(
                description: "Delete",
                label: "Delete",
                value: nil,
                identifier: "delete_button",
                traits: [.button],
                frameX: 0,
                frameY: 0,
                frameWidth: 100,
                frameHeight: 44,
                actions: [.activate]
            ),
            resolution: ActionSubjectResolution(
                origin: .known,
                adjustments: [.staleTargetRefresh]
            )
        )

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: failureOutcome(subjectEvidence: evidence),
            before: before,
            settleOutcome: settledOutcome(finalScreen: beforeScreen)
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.subjectEvidence, evidence)
    }

    func testPostActionReceiptResolvesDeferredPayloadFromFinalSemanticState() async {
        let beforeScreen = makeScreen(elements: [("Status", .staticText, "status")])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let afterScreen = InterfaceObservation.makeForTests(elements: [
            (
                AccessibilityElement.make(
                    label: "Status",
                    value: "Saved",
                    traits: .staticText,
                    respondsToUserInteraction: false
                ),
                HeistId(rawValue: "status")
            ),
        ])
        let outcome = TheSafecracker.ActionDispatchOutcome.success(method: .typeText)

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: outcome,
            afterStatePayload: { context in
                guard let value = context.baseline.observation.tree.findElement(heistId: "status")?.element.value else {
                    return nil
                }
                return .typeText(value)
            },
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(result.payload, .value("Saved"))
    }

    func testPostActionReceiptDoesNotResolveDeferredPayloadFromUnsettledDiagnosticEvidence() async {
        let beforeScreen = makeScreen(elements: [("Status", .staticText, "status")])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let diagnosticScreen = InterfaceObservation.makeForTests(elements: [
            (
                AccessibilityElement.make(
                    label: "Status",
                    value: "Saved",
                    traits: .staticText,
                    respondsToUserInteraction: false
                ),
                HeistId(rawValue: "status")
            ),
        ])
        let outcome = TheSafecracker.ActionDispatchOutcome.success(method: .typeText)

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: outcome,
            afterStatePayload: { context in
                guard let value = context.baseline.observation.tree.findElement(heistId: "status")?.element.value else {
                    return nil
                }
                return .typeText(value)
            },
            before: before,
            settleOutcome: settledOutcome(
                finalScreen: diagnosticScreen,
                outcome: .timedOut(timeMs: 250)
            )
        )

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .typeText)
        XCTAssertNil(result.payload)
        XCTAssertEqual(result.settled, false)
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.interface.projectedElements.first?.value,
            "Saved"
        )
    }

    func testTypeTextPayloadUsesCommittedElementIdentity() {
        let selectedId: HeistId = "selected_message"
        let replacementId: HeistId = "replacement_message"
        let afterScreen = InterfaceObservation.makeForTests(elements: [
            (
                AccessibilityElement.make(
                    label: "Message",
                    value: "Selected",
                    traits: .textEntry,
                    respondsToUserInteraction: false
                ),
                selectedId
            ),
            (
                AccessibilityElement.make(
                    label: "Message",
                    value: "Replacement",
                    traits: .textEntry,
                    respondsToUserInteraction: false
                ),
                replacementId
            ),
        ])
        brains.vault.installObservationForTesting(afterScreen)
        let afterState = brains.postActionObservation.captureSemanticState()

        XCTAssertEqual(
            brains.actions.typeTextPayload(resolvedElementId: selectedId, in: afterState),
            .typeText("Selected")
        )
    }

    func testActionResultWithDeltaReportsTypedFallbackScreenChange() async {
        let beforeScreen = makeScreen(elements: [("Menu", .header, "menu_header")])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let afterScreen = makeScreen(elements: [("Checkout", .header, "checkout_header")])

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(
            result.accessibilityTrace?.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.transition.fallbackReason,
            .primaryHeaderChanged
        )
    }

    func testFallbackScreenChangeReceiptPublishesSettledReplacementSurface() async throws {
        let beforeScreen = makeScreen(elements: [
            ("ButtonHeist Demo", .header, "root_header"),
            ("Controls Demo", .button, "controls_demo"),
            ("Todo List", .button, "todo_list"),
            ("Words", .button, "words"),
        ])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let cleanSettledScreen = makeScreen(elements: [
            ("Section A", .header, "section_a_header"),
            ("A acid", .button, "a_acid"),
            ("abacus major", .button, "abacus_major"),
            ("ButtonHeist Demo", .backButton, "back_button"),
        ])
        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: cleanSettledScreen)
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(
            result.accessibilityTrace?.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.transition.fallbackReason,
            .navigationMarkerChanged
        )
        let labels = result.accessibilityTrace?.captures.last?.interface.projectedElements.compactMap { $0.label } ?? []
        XCTAssertTrue(labels.contains("Section A"), "Expected new screen labels: \(labels)")
        XCTAssertTrue(labels.contains("A acid"), "Expected new screen labels: \(labels)")
        XCTAssertTrue(labels.contains("abacus major"), "Expected new screen labels: \(labels)")
        XCTAssertTrue(labels.contains("ButtonHeist Demo"), "Expected back button to remain: \(labels)")
        XCTAssertFalse(labels.contains("Controls Demo"))
        XCTAssertFalse(labels.contains("Todo List"))
        XCTAssertEqual(
            brains.vault.interfaceTree.orderedElements.compactMap(\.element.label),
            ["Section A", "A acid", "abacus major", "ButtonHeist Demo"]
        )
    }

    func testGappedElementChangedNotificationReferencesAreRemappedToCommittedScreen() async throws {
        let beforeScreen = makeScreen(elements: [
            ("ButtonHeist Demo", .header, "root_header"),
            ("Controls Demo", .button, "controls_demo"),
            ("Todo List", .button, "todo_list"),
            ("Words", .button, "words"),
        ])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let section = AccessibilityElement.make(
            label: "Section A",
            traits: .header,
            respondsToUserInteraction: false
        )
        let acid = AccessibilityElement.make(
            label: "A acid",
            traits: .button,
            respondsToUserInteraction: false
        )
        let abacus = AccessibilityElement.make(
            label: "abacus major",
            traits: .button,
            respondsToUserInteraction: false
        )
        let back = AccessibilityElement.make(
            label: "ButtonHeist Demo",
            traits: .backButton,
            respondsToUserInteraction: false
        )
        let acidObject = NSObject()
        let cleanSettledScreen = InterfaceObservation.makeForTests([
            .init(section, heistId: "section_a_header"),
            .init(acid, heistId: "a_acid", object: acidObject),
            .init(abacus, heistId: "abacus_major"),
            .init(back, heistId: "back_button"),
        ])
        let notificationWindow = brains.vault.accessibilityNotifications.beginActionWindow()
        defer { notificationWindow.cancel() }
        for _ in 0..<64 {
            brains.vault.accessibilityNotifications.recordForTesting(
                code: 99_999,
                notificationData: .none,
                associatedElement: .none
            )
        }
        brains.vault.accessibilityNotifications.recordForTesting(
            code: 1001,
            notificationData: CapturedAccessibilityNotificationPayload(acidObject),
            associatedElement: .none
        )

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: cleanSettledScreen),
            notificationWindow: notificationWindow
        )

        let notification = try XCTUnwrap(
            result.accessibilityTrace?.captures.last?.transition.accessibilityNotifications.last {
                $0.kind == .elementChanged(.layout)
            }
        )
        XCTAssertEqual(notification.kind, .elementChanged(.layout))
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.transition.fallbackReason,
            .navigationMarkerChanged
        )
        guard case .element(let reference) = notification.notificationData else {
            return XCTFail("Expected notification data to resolve to final trace element, got \(notification.notificationData)")
        }
        XCTAssertEqual(reference.path, TreePath([1]))
        XCTAssertEqual(reference.traversalIndex, 1)
        XCTAssertEqual(reference.resolution, .identity)
        XCTAssertEqual(result.accessibilityTrace?.captures.last?.interface.projectedElements[1].label, "A acid")
    }

    func testPassiveSemanticPublishDoesNotDrainPostActionAccessibilityNotifications() async throws {
        let beforeScreen = makeScreen(elements: [("Save", .button, "save")])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()

        let notifiedObject = NSObject()
        let saved = AccessibilityElement.make(
            label: "Saved",
            traits: .staticText,
            respondsToUserInteraction: false
        )
        let finalScreen = InterfaceObservation.makeForTests([
            .init(saved, heistId: "saved", object: notifiedObject),
        ])
        let notificationWindow = brains.vault.accessibilityNotifications.beginActionWindow()
        defer { notificationWindow.cancel() }
        brains.vault.accessibilityNotifications.recordForTesting(
            code: 1001,
            notificationData: CapturedAccessibilityNotificationPayload(notifiedObject),
            associatedElement: .none
        )

        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            makeScreen(elements: [("Passive", .staticText, "passive")])
        )

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: finalScreen),
            notificationWindow: notificationWindow
        )

        let notification = try XCTUnwrap(
            result.accessibilityTrace?.captures.last?.transition.accessibilityNotifications.first
        )
        guard case .element(let reference) = notification.notificationData else {
            return XCTFail("Expected notification data to survive passive publish, got \(notification.notificationData)")
        }
        XCTAssertEqual(reference.resolution, .identity)
        XCTAssertEqual(result.accessibilityTrace?.captures.last?.interface.projectedElements.first?.label, "Saved")
    }

    func testActionResultFinalTraceUsesVisibleSettleNotLaterDiscovery() async throws {
        let beforeScreen = makeScreen(elements: [("Text Input", .header, "text_input")])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let visibleAfter = makeScreen(elements: [("Controls Demo", .header, "controls_demo")])
        let discoveredOnly = AccessibilityElement.make(
            label: "ButtonHeist Demo",
            traits: .button,
            respondsToUserInteraction: false
        )
        let discoveryAfter = InterfaceObservation.makeForTests(
            elements: [(AccessibilityElement.make(
                label: "Controls Demo",
                traits: .header,
                respondsToUserInteraction: false
                ), HeistId(rawValue: "controls_demo"))],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    discoveredOnly,
                    heistId: HeistId(rawValue: "buttonheist_demo"),
                    scrollContainerPath: TreePath([0])
                ),
            ]
        )

        let resultTask = Task { @MainActor in
            await brains.interactionObservation.finishAfterAction(
                outcome: successOutcome(),
                before: before,
                settleOutcome: settledOutcome(finalScreen: visibleAfter)
            )
        }

        for _ in 0..<50 where brains.vault.semanticObservationStream.observationWaiterCount == 0 {
            await Task.yield()
        }
        brains.vault.semanticObservationStream.commitDiscoveryObservationForTesting(discoveryAfter)

        let result = await resultTask.value
        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")

        let labels = try XCTUnwrap(result.accessibilityTrace?.captures.last)
            .interface
            .projectedElements
            .compactMap { $0.label }
        XCTAssertEqual(labels, ["Controls Demo"])
        XCTAssertFalse(labels.contains("ButtonHeist Demo"))
    }

    func testActionResultWithDeltaSettleTimeoutUsesObservedFinalEvidenceWithoutPublishingTruth() async {
        let beforeScreen = makeScreen(elements: [("Menu", .header, "menu_header")])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let settledSequence = brains.vault.semanticObservationStream.latestEvent?.sequence
        let afterScreen = makeScreen(elements: [("Details", .header, "details_header")])

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: afterScreen, outcome: .timedOut(timeMs: 250))
        )

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertNil(result.message)
        XCTAssertEqual(result.settled, false)
        XCTAssertEqual(result.settleTimeMs, 250)
        XCTAssertEqual(
            brains.vault.semanticObservationStream.latestEvent?.sequence,
            settledSequence,
            "timeout evidence must not be published as a new settled observation"
        )
        XCTAssertEqual(
            brains.vault.semanticObservationStream.latestEvent?.settledObservation.observation.tree.orderedElements.first?.element.label,
            "Menu"
        )
        XCTAssertTrue(brains.vault.semanticObservationStream.latestSettledObservationInvalidated)
        XCTAssertEqual(brains.vault.interfaceTree.orderedElements.first?.element.label, "Menu")
        XCTAssertEqual(
            brains.vault.latestFailedSettleDiagnosticEvidence?.tree.orderedElements.first?.element.label,
            "Details"
        )
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 2)
        XCTAssertEqual(result.accessibilityTrace?.captures.last?.interface.projectedElements.first?.label, "Details")
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.transition.fallbackReason,
            .primaryHeaderChanged
        )
    }

    func testActionBaselineDoesNotPromoteDiagnosticOnlyEvidence() {
        let diagnosticScreen = makeScreen(elements: [("Timeout", .staticText, "timeout")])
        brains.vault.recordFailedSettleDiagnosticEvidence(diagnosticScreen)

        let baseline = brains.interactionObservation.baselineState(from: nil)

        XCTAssertNil(baseline)
        XCTAssertEqual(
            brains.vault.latestFailedSettleDiagnosticEvidence?.tree.orderedElements.first?.element.label,
            "Timeout"
        )
    }

    func testActionResultWithDeltaCancelledSettleFailsActionResult() async {
        let beforeScreen = makeScreen(elements: [("Save", .button, "save")])
        brains.vault.installObservationForTesting(beforeScreen)
        let before = brains.postActionObservation.captureSemanticState()
        let settledSequence = brains.vault.semanticObservationStream.latestEvent?.sequence

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: beforeScreen, outcome: .cancelled(timeMs: 125))
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.message, "cancelled after 125ms")
        XCTAssertEqual(result.outcome.errorKind, .actionFailed)
        XCTAssertEqual(result.settled, false)
        XCTAssertEqual(result.settleTimeMs, 125)
        XCTAssertEqual(brains.vault.semanticObservationStream.latestEvent?.sequence, settledSequence)
        XCTAssertTrue(brains.vault.semanticObservationStream.latestSettledObservationInvalidated)
        XCTAssertEqual(brains.vault.interfaceTree.orderedElements.first?.element.label, "Save")
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 1)
        XCTAssertEqual(result.accessibilityTrace?.captures.first?.interface.projectedElements.first?.label, "Save")
    }

    func testActionResultWithDeltaParseFailureFailsActionResult() async {
        seedScreen(elements: [("Save", .button, "save")])
        let before = brains.postActionObservation.captureSemanticState()
        brains.vault.installObservationForTesting(.empty)

        let result = await brains.interactionObservation.finishAfterAction(
            outcome: successOutcome(),
            before: before,
            settleOutcome: settledOutcome(finalScreen: nil, outcome: .timedOut(timeMs: 300))
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.message, "Could not parse post-action accessibility tree")
        XCTAssertEqual(result.outcome.errorKind, .actionFailed)
        XCTAssertEqual(result.settled, false)
        XCTAssertEqual(result.settleTimeMs, 300)
        XCTAssertEqual(result.accessibilityTrace?.captures.count, 1)
        XCTAssertEqual(result.accessibilityTrace?.captures.first?.interface.projectedElements.first?.label, "Save")
    }

}

#endif

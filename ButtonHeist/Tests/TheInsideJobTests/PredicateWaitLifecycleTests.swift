#if canImport(UIKit)
#if DEBUG
import XCTest
import ButtonHeistSupport
import ThePlans
import UIKit

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class PredicateWaitLifecycleTests: XCTestCase {
    private enum Check: Equatable {
        case visible
        case reveal
        case discovery
    }

    func testLifecycleMachineCarriesEvidenceThroughDeadlineSequence() {
        var lifecycle = StateDriver(
            initial: PredicateWaitLifecycleState<String>.initialVisible("initial"),
            machine: PredicateWaitLifecycleMachine<String>(continuesAfterInitialMiss: true)
        )

        let effects = [
            lifecycle.send(.evaluated(PredicateWaitLifecycleEvaluation(
                evidence: "visible",
                matched: false
            ))).predicateWaitEffect,
            lifecycle.send(.evaluated(PredicateWaitLifecycleEvaluation(
                evidence: "discovery",
                matched: false
            ))).predicateWaitEffect,
            lifecycle.send(.deadlineReached).predicateWaitEffect,
            lifecycle.send(.evaluated(PredicateWaitLifecycleEvaluation(
                evidence: "terminal visible",
                matched: false
            ))).predicateWaitEffect,
            lifecycle.send(.evaluated(PredicateWaitLifecycleEvaluation(
                evidence: "terminal discovery",
                matched: false
            ))).predicateWaitEffect,
        ]

        XCTAssertEqual(effects, [
            .discover(.overall),
            .awaitObservation,
            .settleVisible(.viewportTransition),
            .discover(.unbounded),
            .finish(.timedOut),
        ])
        XCTAssertEqual(lifecycle.state.phase, .finished(.timedOut))
        XCTAssertEqual(lifecycle.state.evidence, "terminal discovery")
    }

    func testImmediateCaseSelectionMissFinishesInLifecycleMachine() {
        var lifecycle = StateDriver(
            initial: PredicateWaitLifecycleState<String>.initialVisible("unevaluated"),
            machine: PredicateWaitLifecycleMachine<String>(continuesAfterInitialMiss: false)
        )

        let effect = lifecycle.send(.evaluated(PredicateWaitLifecycleEvaluation(
            evidence: "evaluated",
            matched: false
        ))).predicateWaitEffect

        XCTAssertEqual(effect, .finish(.timedOut))
        XCTAssertEqual(lifecycle.state.phase, .finished(.timedOut))
        XCTAssertEqual(lifecycle.state.evidence, "evaluated")
    }

    func testSettledVisibleExistsMatchSkipsDiscovery() async throws {
        let brains = TheBrains(tripwire: TheTripwire())
        let visible = committedEvent(
            in: brains,
            scope: .visible,
            label: "Ready",
            heistId: "ready"
        )
        var discoveryCount = 0
        let wait = predicateWait(
            brains: brains,
            settleVisible: { _ in visible },
            discover: { _, _, _ in
                discoveryCount += 1
                return nil
            }
        )

        let receipt = await wait.wait(for: try waitInput(predicate: .exists(.label("Ready"))))

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(discoveryCount, 0)
    }

    func testSettledVisibleMissingMatchSkipsDiscovery() async throws {
        let brains = TheBrains(tripwire: TheTripwire())
        let visible = committedEvent(
            in: brains,
            scope: .visible,
            label: "Loading",
            heistId: "loading"
        )
        var discoveryCount = 0
        let wait = predicateWait(
            brains: brains,
            settleVisible: { _ in visible },
            discover: { _, _, _ in
                discoveryCount += 1
                return nil
            }
        )

        let receipt = await wait.wait(for: try waitInput(predicate: .missing(.label("Ready"))))

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.expectation.met)
        XCTAssertEqual(discoveryCount, 0)
    }

    func testInitialVisibleMissPerformsExactlyOneBoundedDiscovery() async throws {
        let brains = TheBrains(tripwire: TheTripwire())
        let visible = committedEvent(
            in: brains,
            scope: .visible,
            label: "Loading",
            heistId: "loading"
        )
        let discovered = committedEvent(
            in: brains,
            scope: .discovery,
            label: "Ready",
            heistId: "ready"
        )
        var visibleDeadline: SemanticObservationDeadline?
        var discoveryDeadlines: [SemanticObservationDeadline] = []
        var discoveryTargets: [ResolvedAccessibilityTarget?] = []
        let wait = predicateWait(
            brains: brains,
            settleVisible: { deadline in
                visibleDeadline = deadline
                return visible
            },
            discover: { target, deadline, observer in
                guard let deadline else {
                    XCTFail("Initial discovery must retain the wait deadline")
                    return nil
                }
                discoveryTargets.append(target)
                discoveryDeadlines.append(deadline)
                XCTAssertTrue(observer(discovered))
                return discovered
            }
        )

        let receipt = await wait.wait(
            for: try waitInput(predicate: .exists(.label("Ready")), timeout: 5)
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(discoveryDeadlines.count, 1)
        XCTAssertEqual(discoveryDeadlines.first, visibleDeadline)
        XCTAssertEqual(discoveryDeadlines.first?.timeoutSeconds, 5)
        XCTAssertEqual(discoveryTargets, [literalTarget(.label("Ready"))])
    }

    func testUnmatchedObservationEntryTriggersAnotherDiscovery() async throws {
        let brains = TheBrains(tripwire: TheTripwire())
        let stream = brains.stash.semanticObservationStream
        let initialVisible = committedEvent(
            in: brains,
            scope: .visible,
            label: "Loading",
            heistId: "initial_loading"
        )
        let observedEntry = committedEvent(
            in: brains,
            scope: .visible,
            label: "Still Loading",
            heistId: "observed_loading"
        )
        let initialDiscovery = committedEvent(
            in: brains,
            scope: .discovery,
            label: "Searching",
            heistId: "initial_search"
        )
        let triggeredDiscovery = committedEvent(
            in: brains,
            scope: .discovery,
            label: "Ready",
            heistId: "ready"
        )
        let initialCursor = try XCTUnwrap(initialVisible.cursor)
        var discoveryEvents = [initialDiscovery, triggeredDiscovery]
        var discoveryCount = 0
        var requestedCursor: ObservationCursor?
        var evaluatedSequences: [SettledObservationSequence] = []
        let wait = predicateWait(
            brains: brains,
            settleVisible: { _ in initialVisible },
            discover: { _, _, observer in
                discoveryCount += 1
                let event = discoveryEvents.removeFirst()
                _ = observer(event)
                return event
            },
            latestObservationCursor: { initialCursor },
            observationEntries: { cursor in
                requestedCursor = cursor
                return stream.observationEntries(after: initialCursor, scope: .visible)
            },
            onSemanticObservation: { event in
                evaluatedSequences.append(event.sequence)
            }
        )

        let receipt = await wait.wait(
            for: try waitInput(predicate: .exists(.label("Ready")), timeout: 5)
        )

        XCTAssertNotEqual(observedEntry.sequence, initialVisible.sequence)
        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(requestedCursor, initialCursor)
        XCTAssertEqual(evaluatedSequences, [
            initialVisible.sequence,
            initialDiscovery.sequence,
            observedEntry.sequence,
            triggeredDiscovery.sequence,
        ])
        XCTAssertEqual(discoveryCount, 2)
        XCTAssertTrue(discoveryEvents.isEmpty)
    }

    func testDeadlinePerformsFinalVisibleSettleAndFullDiscovery() async throws {
        let brains = TheBrains(tripwire: TheTripwire())
        var visibleEvents = [
            committedEvent(
                in: brains,
                scope: .visible,
                label: "Initial Loading",
                heistId: "initial_loading"
            ),
            committedEvent(
                in: brains,
                scope: .visible,
                label: "Final Loading",
                heistId: "final_loading"
            ),
        ]
        var discoveryEvents = [
            committedEvent(
                in: brains,
                scope: .discovery,
                label: "Initial Search",
                heistId: "initial_search"
            ),
            committedEvent(
                in: brains,
                scope: .discovery,
                label: "Ready",
                heistId: "ready"
            ),
        ]
        var checks: [Check] = []
        var deadlines: [SemanticObservationDeadline?] = []
        let wait = predicateWait(
            brains: brains,
            settleVisible: { deadline in
                checks.append(.visible)
                deadlines.append(deadline)
                return visibleEvents.removeFirst()
            },
            discover: { _, deadline, observer in
                checks.append(.discovery)
                deadlines.append(deadline)
                let event = discoveryEvents.removeFirst()
                _ = observer(event)
                return event
            }
        )

        let receipt = await wait.wait(
            for: try waitInput(predicate: .exists(.label("Ready")), timeout: .milliseconds(1))
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(checks, [.visible, .discovery, .visible, .discovery])
        XCTAssertEqual(deadlines[0]?.timeoutSeconds, try WaitTimeout.milliseconds(1).seconds)
        XCTAssertEqual(deadlines[1]?.timeoutSeconds, try WaitTimeout.milliseconds(1).seconds)
        XCTAssertEqual(
            deadlines[2]?.timeoutSeconds,
            Double(SettleSession.viewportTransitionTimeoutMs) / 1_000
        )
        XCTAssertNil(deadlines[3])
        XCTAssertTrue(visibleEvents.isEmpty)
        XCTAssertTrue(discoveryEvents.isEmpty)
    }

    func testIntermediateDiscoveryMatchSurvivesRestoredEndpoint() async throws {
        let brains = TheBrains(tripwire: TheTripwire())
        let visible = committedEvent(
            in: brains,
            scope: .visible,
            label: "Loading",
            heistId: "loading"
        )
        let intermediate = committedEvent(
            in: brains,
            scope: .discovery,
            label: "Ready",
            heistId: "ready"
        )
        let restored = committedEvent(
            in: brains,
            scope: .discovery,
            label: "Loading",
            heistId: "restored_loading"
        )
        var evaluatedSequences: [SettledObservationSequence] = []
        let wait = predicateWait(
            brains: brains,
            settleVisible: { _ in visible },
            discover: { _, _, observer in
                XCTAssertTrue(observer(intermediate))
                return restored
            },
            onSemanticObservation: { event in
                evaluatedSequences.append(event.sequence)
            }
        )

        let receipt = await wait.wait(
            for: try waitInput(predicate: .exists(.label("Ready")), timeout: 5)
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(evaluatedSequences, [visible.sequence, intermediate.sequence])
    }

    func testTemporalTargetIsRevealedBeforeObservationBegins() async throws {
        let brains = TheBrains(tripwire: TheTripwire())
        let stream = brains.stash.semanticObservationStream
        let initial = committedEvent(
            in: brains,
            scope: .visible,
            label: "Total",
            heistId: "total"
        )
        _ = committedEvent(
            in: brains,
            scope: .visible,
            label: "Unrelated",
            heistId: "unrelated"
        )
        let initialCursor = try XCTUnwrap(initial.cursor)
        var checks: [Check] = []
        let wait = predicateWait(
            brains: brains,
            settleVisible: { _ in
                checks.append(.visible)
                return initial
            },
            revealTarget: { target, _ in
                checks.append(.reveal)
                XCTAssertEqual(target, literalTarget(.label("Total")))
                return initial
            },
            discover: { _, _, _ in
                checks.append(.discovery)
                return nil
            },
            latestObservationCursor: { initialCursor },
            observationEntries: { _ in
                stream.observationEntries(after: initialCursor, scope: .visible)
            }
        )

        let receipt = await wait.wait(
            for: try waitInput(
                predicate: .changed(.elements([.disappeared(.label("Total"))])),
                timeout: 5
            )
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(checks, [.visible, .reveal])
    }

    func testUnmatchedObservationRevealsTemporalTargetAgain() async throws {
        let brains = TheBrains(tripwire: TheTripwire())
        let stream = brains.stash.semanticObservationStream
        let initial = committedEvent(
            in: brains,
            scope: .visible,
            label: "Total",
            heistId: "total"
        )
        _ = committedEvent(
            in: brains,
            scope: .visible,
            label: "Total",
            heistId: "total"
        )
        let initialCursor = try XCTUnwrap(initial.cursor)
        var revealCount = 0
        let wait = predicateWait(
            brains: brains,
            settleVisible: { _ in initial },
            revealTarget: { target, _ in
                XCTAssertEqual(target, literalTarget(.label("Total")))
                revealCount += 1
                if revealCount == 1 { return initial }
                return self.committedEvent(
                    in: brains,
                    scope: .visible,
                    label: "Complete",
                    heistId: "complete"
                )
            },
            discover: { _, _, _ in
                XCTFail("A resolved temporal target should not run generic discovery")
                return nil
            },
            latestObservationCursor: { initialCursor },
            observationEntries: { _ in
                stream.observationEntries(after: initialCursor, scope: .visible)
            }
        )

        let receipt = await wait.wait(
            for: try waitInput(
                predicate: .changed(.elements([.disappeared(.label("Total"))])),
                timeout: 5
            )
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(revealCount, 2)
    }

    private func predicateWait(
        brains: TheBrains,
        settleVisible: @escaping PredicateWait.SettleVisible,
        revealTarget: @escaping PredicateWait.RevealTarget = { _, _ in nil },
        discover: @escaping PredicateWait.Discover,
        latestObservationCursor: @escaping PredicateWait.LatestObservationCursor = { nil },
        observationEntries: @escaping PredicateWait.ObservationEntries = { _ in nil },
        onSemanticObservation: @escaping @MainActor (SettledSemanticObservationEvent) -> Void = { _ in }
    ) -> PredicateWait {
        PredicateWait(
            observeEvent: { _, _, _ in nil },
            latestEvent: { nil },
            latestSettleFailure: { nil },
            semanticObservation: { event in
                onSemanticObservation(event)
                return brains.postActionObservation.semanticObservation(from: event)
            },
            buildObservationWindow: { baseline, event in
                brains.stash.semanticObservationStream.observationWindow(
                    from: baseline,
                    through: event
                )
            },
            presenceTimeoutMessage: { _, _ in nil },
            announcementCursor: { _ in .origin },
            waitForAnnouncement: { _, _, _ in nil },
            settleVisible: settleVisible,
            revealTarget: revealTarget,
            discover: discover,
            latestObservationCursor: latestObservationCursor,
            observationEntries: observationEntries
        )
    }

    private func committedEvent(
        in brains: TheBrains,
        scope: SemanticObservationScope,
        label: String,
        heistId: HeistId
    ) -> SettledSemanticObservationEvent {
        let screen = InterfaceObservation.makeForTests(elements: [
            (
                AccessibilityElement.make(
                    label: label,
                    traits: .staticText,
                    respondsToUserInteraction: false
                ),
                heistId
            ),
        ])
        switch scope {
        case .visible:
            return brains.stash.semanticObservationStream.commitVisibleObservationForTesting(screen)
        case .discovery:
            return brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(screen)
        }
    }

    private func waitInput(
        predicate: AccessibilityPredicate,
        timeout: WaitTimeout = 1
    ) throws -> ResolvedWaitRuntimeInput {
        try resolvedWait(WaitStep(
            predicate: predicate,
            timeout: timeout
        ))
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

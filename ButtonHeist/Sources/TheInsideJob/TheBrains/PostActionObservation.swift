#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotModel
import TheScore

/// Projects supplied semantic states into traces, captures, and deltas.
@MainActor
final class PostActionObservation {
    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let navigation: Navigation

    /// State captured before an action for delta computation.
    struct BeforeState {
        let snapshot: [Screen.ScreenElement]
        let elements: [AccessibilityElement]
        let hierarchy: [AccessibilityHierarchy]
        let interface: Interface
        let interfaceHash: String
        let semanticHash: String
        let capture: AccessibilityTrace.Capture
        let tripwireSignal: TheTripwire.TripwireSignal
        let screenSnapshot: ScreenClassifier.Snapshot
        let screenId: String?
        let settledObservationSequence: UInt64?
    }

    struct SettleEvidence {
        let outcome: SettleSession.Outcome
        let visibleEvent: SettledSemanticObservationEvent?

        var didSettleCleanly: Bool {
            outcome.outcome.didSettleCleanly
        }

        var timeMs: Int {
            outcome.outcome.timeMs
        }
    }

    struct FinalEvidence {
        let state: BeforeState
        let trace: AccessibilityTrace

        var capture: AccessibilityTrace.Capture? {
            trace.captures.last
        }
    }

    init(stash: TheStash, safecracker: TheSafecracker, tripwire: TheTripwire, navigation: Navigation) {
        self.stash = stash
        self.safecracker = safecracker
        self.tripwire = tripwire
        self.navigation = navigation
    }

    func captureSemanticState(from observation: SettledSemanticObservation) -> BeforeState {
        captureSemanticState(
            from: observation.screen,
            tripwireSignal: observation.tripwireSignal,
            settledObservationSequence: observation.sequence
        )
    }

    func semanticObservation(from event: SettledSemanticObservationEvent) -> HeistSemanticObservation {
        let current = captureSemanticState(from: event.observation)
        return InteractionObservationProjection.semanticObservation(event: event, state: current)
    }

    func settleEvidence(
        before: BeforeState,
        outcome: SettleSession.Outcome?
    ) async -> SettleEvidence {
        let settledObservation = await stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            settleOutcome: outcome
        )
        return SettleEvidence(
            outcome: settledObservation.settle,
            visibleEvent: settledObservation.event
        )
    }

    func finalSemanticEvidence(
        before: BeforeState,
        settleEvidence: SettleEvidence
    ) async -> FinalEvidence? {
        guard let visibleEvent = settleEvidence.visibleEvent else { return nil }
        let finalState = await captureFinalSemanticState(after: visibleEvent)
        let trace = buildPostActionTrace(
            before: before,
            final: finalState,
            settleEvidence: settleEvidence
        )
        return FinalEvidence(state: finalState, trace: trace)
    }

    func captureSemanticState(
        from screen: Screen,
        tripwireSignal: TheTripwire.TripwireSignal,
        settledObservationSequence: UInt64?
    ) -> BeforeState {
        let snapshot = stash.selectElements(in: screen)
        let (interface, interfaceHash) = stash.semanticInterfaceWithHash(for: screen)
        let capture = makeTraceCapture(interface: interface, sequence: 0, tripwireSignal: tripwireSignal)
        return BeforeState(
            snapshot: snapshot,
            elements: snapshot.map(\.element),
            hierarchy: screen.liveCapture.hierarchy,
            interface: interface,
            interfaceHash: interfaceHash,
            semanticHash: screen.semantic.semanticHash,
            capture: capture,
            tripwireSignal: tripwireSignal,
            screenSnapshot: ScreenClassifier.snapshot(of: screen),
            screenId: screen.id,
            settledObservationSequence: settledObservationSequence
        )
    }

    static func shouldRecordAccessibilityTrace(
        baseline: BeforeState,
        current: BeforeState,
        classification: ScreenClassifier.Classification
    ) -> Bool {
        classification.isScreenChange
            || current.capture.context != baseline.capture.context
            || current.semanticHash != baseline.semanticHash
    }

    func makeTraceCapture(
        interface: Interface,
        sequence: Int = 1,
        parentHash: String? = nil,
        tripwireSignal: TheTripwire.TripwireSignal? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(
            sequence: sequence,
            interface: interface,
            parentHash: parentHash,
            context: makeCaptureContext(tripwireSignal: tripwireSignal),
            transition: transition
        )
    }

    func makeAccessibilityTrace(
        afterInterface: Interface,
        parentCapture: AccessibilityTrace.Capture? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace {
        let capture = makeTraceCapture(
            interface: afterInterface,
            sequence: parentCapture == nil ? 1 : 2,
            parentHash: parentCapture?.hash,
            transition: transition
        )
        if let parentCapture {
            return AccessibilityTrace(captures: [parentCapture, capture])
        }
        return AccessibilityTrace(capture: capture)
    }

    func makeAccessibilityTrace(
        afterInterface: Interface,
        parentCapture: AccessibilityTrace.Capture,
        classification: ScreenClassifier.Classification,
        transient: [HeistElement] = []
    ) -> AccessibilityTrace {
        makeAccessibilityTrace(
            afterInterface: afterInterface,
            parentCapture: parentCapture,
            transition: AccessibilityTrace.Transition(
                screenChangeReason: classification.reason?.rawValue,
                transient: transient
            )
        )
    }

    func makeClassifiedAccessibilityTrace(after: BeforeState, parent: BeforeState) -> AccessibilityTrace {
        let classification = ScreenClassifier.classify(
            before: parent.screenSnapshot,
            after: after.screenSnapshot
        )
        let capture = AccessibilityTrace.Capture(
            sequence: after.capture.sequence,
            interface: after.capture.interface,
            parentHash: after.capture.parentHash,
            context: after.capture.context,
            transition: AccessibilityTrace.Transition(screenChangeReason: classification.reason?.rawValue),
            hash: after.capture.hash
        )
        return AccessibilityTrace(captures: [parent.capture, capture])
    }

    private func semanticStateAfterDiscovery(after sequence: UInt64?) async -> BeforeState? {
        guard let event = await stash.observeSettledSemanticObservation(
            scope: .discovery,
            after: sequence,
            timeout: 2.0
        ) else { return nil }
        return captureSemanticState(from: event.observation)
    }

    private func captureFinalSemanticState(after visibleEvent: SettledSemanticObservationEvent) async -> BeforeState {
        await semanticStateAfterDiscovery(after: visibleEvent.sequence)
            ?? captureSemanticState(from: visibleEvent.observation)
    }

    private func buildPostActionTrace(
        before: BeforeState,
        final: BeforeState,
        settleEvidence: SettleEvidence
    ) -> AccessibilityTrace {
        let classification = ScreenClassifier.classify(
            before: before.screenSnapshot,
            after: final.screenSnapshot
        )
        return makeAccessibilityTrace(
            afterInterface: final.interface,
            parentCapture: before.capture,
            classification: classification,
            transient: InteractionObservationProjection.transientElements(
                settleResult: settleEvidence.outcome,
                before: before,
                final: final,
                classification: classification
            )
        )
    }

    private func makeCaptureContext(tripwireSignal: TheTripwire.TripwireSignal? = nil) -> AccessibilityTrace.Context {
        let signal = tripwireSignal ?? tripwire.tripwireSignal()
        let windows = signal.windowStack.windows.enumerated().map { index, window in
            AccessibilityTrace.WindowContext(
                index: index,
                level: Double(window.level),
                isKeyWindow: window.isKeyWindow
            )
        }
        return AccessibilityTrace.Context(
            keyboardVisible: safecracker.isKeyboardVisible(),
            screenId: stash.lastScreenId,
            windowStack: windows
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

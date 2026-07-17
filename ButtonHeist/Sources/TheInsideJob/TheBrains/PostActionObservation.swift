#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotModel
import ThePlans
import TheScore

/// A settled semantic observation paired with its trace and summary.
struct HeistSemanticObservation {
    let event: SettledSemanticObservationEvent
    let state: PostActionObservation.BeforeState
    let accessibilityTrace: AccessibilityTrace
    let summary: String
}

enum SemanticObservationTiming {
    static let defaultTimeout: Double = 1
    static let visibleTickIntervalSeconds: Double = 0.1
}

struct SemanticObservationDeadline: Sendable, Equatable {
    let start: CFAbsoluteTime
    let timeoutSeconds: Double

    init(start: CFAbsoluteTime, timeoutSeconds: Double) {
        self.start = start
        self.timeoutSeconds = max(0, timeoutSeconds)
    }

    init(start: CFAbsoluteTime, timeoutMs: Int) {
        self.init(start: start, timeoutSeconds: Double(max(0, timeoutMs)) / 1_000)
    }

    func hasTimeRemaining(at now: CFAbsoluteTime) -> Bool {
        now < deadline
    }

    func remainingSeconds(at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> Double {
        max(0, deadline - now)
    }

    func elapsedMilliseconds(at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> Int {
        max(0, Int((now - start) * 1_000))
    }

    private var deadline: CFAbsoluteTime {
        start + timeoutSeconds
    }
}

/// Builds traces, captures, change facts, and action receipts from supplied semantic
/// states. The post-action contract is: refresh/settle → before → action →
/// refresh/settle → after → result.
@MainActor
final class PostActionObservation {
    let stash: TheStash
    let safecracker: TheSafecracker

    enum StateInterfaceProjection {
        case semantic
        case discovery
    }

    /// State captured before an action for delta computation.
    struct BeforeState {
        let screen: InterfaceObservation
        let capture: AccessibilityTrace.Capture
        let tripwireSignal: TheTripwire.TripwireSignal
        let settledObservationSequence: SettledObservationSequence?

        var elements: [AccessibilityElement] { screen.tree.orderedElements.map(\.element) }
        var interface: Interface { capture.interface }
        var interfaceHash: String { screen.tree.interfaceHash }
        @MainActor var screenSnapshot: ScreenClassifier.Snapshot { ScreenClassifier.snapshot(of: screen.tree) }
        var screenId: String? { screen.tree.id }
    }

    enum SettledObservationResult {
        case committed(settle: SettleSession.Outcome, finalState: BeforeState, trace: AccessibilityTrace)
        case diagnostic(settle: SettleSession.Outcome, trace: AccessibilityTrace)
        case unavailable(
            settle: SettleSession.Outcome,
            trace: AccessibilityTrace,
            failureMessage: String
        )
    }

    init(stash: TheStash, safecracker: TheSafecracker) {
        self.stash = stash
        self.safecracker = safecracker
    }

    func captureSemanticState(from observation: SettledSemanticObservation) -> BeforeState {
        captureSemanticState(
            from: observation.screen,
            tripwireSignal: stash.tripwire.tripwireSignal(),
            settledObservationSequence: observation.sequence,
            interfaceProjection: observation.scope.stateInterfaceProjection
        )
    }

    func captureSemanticState(from evidence: VisibleSemanticObservationEvidence) -> BeforeState {
        captureSemanticState(
            from: evidence.screen,
            tripwireSignal: stash.tripwire.tripwireSignal(),
            settledObservationSequence: evidence.settledObservationSequence
        )
    }

    func semanticObservation(from event: SettledSemanticObservationEvent) -> HeistSemanticObservation {
        let screen = event.scope == .visible
            ? event.observation.screen.viewportOnly
            : event.observation.screen
        let current = captureSemanticState(
            from: screen,
            tripwireSignal: stash.tripwire.tripwireSignal(),
            settledObservationSequence: event.sequence,
            interfaceProjection: event.scope.stateInterfaceProjection
        )
        return HeistSemanticObservation(
            event: event,
            state: current,
            accessibilityTrace: event.trace,
            summary: Self.observationSummary(current)
        )
    }

    func settleObservation(
        before: BeforeState,
        commitScope: SemanticObservationScope = .visible,
        outcome: SettleSession.Outcome?,
        notificationWindow: AccessibilityNotificationActionWindow? = nil
    ) async -> PostActionSettleObservation {
        await stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            commitScope: commitScope,
            settleOutcome: outcome,
            notificationWindow: notificationWindow
        )
    }

    func settledObservationResult(
        before: BeforeState,
        observation: PostActionSettleObservation
    ) -> SettledObservationResult {
        switch observation.result {
        case .committed(let event):
            precondition(
                observation.settle.outcome.didSettleCleanly,
                "committed observation requires clean settle"
            )
            let finalState = captureFinalSemanticState(after: event)
            let trace = observedTrace(
                before: before,
                finalState: finalState,
                settle: observation.settle,
                continuity: event.continuity,
                transitionEvidence: event.trace.captures.last?.transition
            )
            return .committed(
                settle: observation.settle,
                finalState: finalState,
                trace: trace
            )

        case .observedUnsettled(let tree, let notificationBatch):
            guard case .timedOut = observation.settle.outcome else {
                preconditionFailure("unsettled observation requires settle timeout")
            }
            let screen: InterfaceObservation
            do {
                screen = try InterfaceObservation.build(tree: tree)
            } catch {
                preconditionFailure("Unsettled semantic observation failed validation: \(error)")
            }
            let finalState = captureSemanticState(
                from: screen,
                tripwireSignal: before.tripwireSignal,
                settledObservationSequence: nil
            )
            let trace = diagnosticObservedTrace(
                before: before,
                finalState: finalState,
                settle: observation.settle,
                transitionEvidence: diagnosticTransitionEvidence(
                    notificationBatch,
                    in: finalState.screen
                )
            )
            return .diagnostic(settle: observation.settle, trace: trace)

        case .unavailable(let notificationBatch):
            let trace: AccessibilityTrace
            if let notificationBatch {
                trace = diagnosticObservedTrace(
                    before: before,
                    finalState: before,
                    settle: observation.settle,
                    transitionEvidence: diagnosticTransitionEvidence(
                        notificationBatch,
                        in: before.screen
                    )
                )
            } else {
                trace = AccessibilityTrace(capture: before.capture)
            }
            switch observation.settle.outcome {
            case .cancelled(let timeMs):
                return .unavailable(
                    settle: observation.settle,
                    trace: trace,
                    failureMessage: "cancelled after \(timeMs)ms"
                )
            case .timedOut:
                return .unavailable(
                    settle: observation.settle,
                    trace: trace,
                    failureMessage: "Could not parse post-action accessibility tree"
                )
            case .settled:
                preconditionFailure("clean settle requires committed observation")
            }
        }
    }

    private func observedTrace(
        before: BeforeState,
        finalState: BeforeState,
        settle: SettleSession.Outcome,
        continuity: ScreenContinuity,
        transitionEvidence: AccessibilityTrace.Transition?
    ) -> AccessibilityTrace {
        return makeAccessibilityTrace(
            afterCapture: finalState.capture,
            parentCapture: before.capture,
            classification: continuity,
            transient: Self.transientElements(
                settleResult: settle,
                before: before,
                final: finalState,
                classification: continuity
            ),
            accessibilityNotifications: transitionEvidence?.accessibilityNotifications ?? [],
            accessibilityNotificationGap: transitionEvidence?.accessibilityNotificationGap
        )
    }

    private func diagnosticObservedTrace(
        before: BeforeState,
        finalState: BeforeState,
        settle: SettleSession.Outcome,
        transitionEvidence: AccessibilityTrace.Transition?
    ) -> AccessibilityTrace {
        let continuity = SemanticObservationGenerationClassifier.continuity(
            from: before.screen,
            to: finalState.screen,
            notifications: transitionEvidence?.accessibilityNotifications.map(\.kind) ?? []
        )
        return observedTrace(
            before: before,
            finalState: finalState,
            settle: settle,
            continuity: continuity,
            transitionEvidence: transitionEvidence
        )
    }

    private func diagnosticTransitionEvidence(
        _ notificationBatch: AccessibilityNotificationBatch?,
        in screen: InterfaceObservation
    ) -> AccessibilityTrace.Transition? {
        guard let notificationBatch else { return nil }
        return AccessibilityTrace.Transition(
            accessibilityNotifications: stash.resolveAccessibilityNotificationEvidence(
                notificationBatch.events,
                in: screen
            ),
            accessibilityNotificationGap: notificationBatch.gap
        )
    }

    func captureSemanticState(
        from screen: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        settledObservationSequence: SettledObservationSequence?,
        interfaceProjection: StateInterfaceProjection = .semantic
    ) -> BeforeState {
        let interfaceSnapshot = interfaceSnapshot(for: screen, projection: interfaceProjection)
        let capture = makeTraceCapture(
            interface: interfaceSnapshot.interface,
            sequence: 0,
            screen: screen,
            tripwireSignal: tripwireSignal,
            screenId: screen.tree.id
        )
        return BeforeState(
            screen: screen,
            capture: capture,
            tripwireSignal: tripwireSignal,
            settledObservationSequence: settledObservationSequence
        )
    }

    private func interfaceSnapshot(
        for screen: InterfaceObservation,
        projection: StateInterfaceProjection
    ) -> TheStash.SemanticInterfaceSnapshot {
        switch projection {
        case .semantic:
            return stash.semanticInterfaceWithHash(for: screen)
        case .discovery:
            return stash.discoveryInterfaceWithHash(for: screen)
        }
    }

    static func shouldRecordAccessibilityTrace(
        baseline: BeforeState,
        current: BeforeState,
        classification: ScreenContinuity
    ) -> Bool {
        switch classification {
        case .replacement:
            return true
        case .sameGeneration:
            return current.capture.context != baseline.capture.context
                || current.interfaceHash != baseline.interfaceHash
        }
    }

    func makeTraceCapture(
        interface: Interface,
        sequence: Int = 1,
        parentHash: String? = nil,
        screen: InterfaceObservation? = nil,
        tripwireSignal: TheTripwire.TripwireSignal,
        screenId: String? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(
            sequence: sequence,
            interface: interface,
            parentHash: parentHash,
            context: makeCaptureContext(screen: screen, tripwireSignal: tripwireSignal, screenId: screenId),
            transition: transition
        )
    }

    func makeAccessibilityTrace(
        afterCapture: AccessibilityTrace.Capture,
        parentCapture: AccessibilityTrace.Capture? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace {
        let capture = AccessibilityTrace.Capture(
            sequence: parentCapture == nil ? 1 : 2,
            interface: afterCapture.interface,
            parentHash: parentCapture?.hash,
            context: afterCapture.context,
            transition: transition
        )
        if let parentCapture {
            return AccessibilityTrace(captures: [parentCapture, capture])
        }
        return AccessibilityTrace(capture: capture)
    }

    func makeAccessibilityTrace(
        afterCapture: AccessibilityTrace.Capture,
        parentCapture: AccessibilityTrace.Capture,
        classification: ScreenContinuity,
        transient: [HeistElement] = [],
        accessibilityNotifications: [AccessibilityNotificationEvidence] = [],
        accessibilityNotificationGap: AccessibilityNotificationGap? = nil
    ) -> AccessibilityTrace {
        let transition: AccessibilityTrace.Transition
        switch classification {
        case .sameGeneration, .replacement(.screenChangedNotification):
            transition = AccessibilityTrace.Transition(
                transient: transient,
                accessibilityNotifications: accessibilityNotifications,
                accessibilityNotificationGap: accessibilityNotificationGap
            )
        case .replacement(.inferred(let reason)):
            AccessibilityObservationFallbackLog.record(
                reason,
                source: .postAction
            )
            transition = AccessibilityTrace.Transition(
                fallbackReason: reason,
                transient: transient,
                accessibilityNotifications: accessibilityNotifications,
                accessibilityNotificationGap: accessibilityNotificationGap
            )
        }
        return makeAccessibilityTrace(
            afterCapture: afterCapture,
            parentCapture: parentCapture,
            transition: transition
        )
    }

    private func captureFinalSemanticState(after visibleEvent: SettledSemanticObservationEvent) -> BeforeState {
        let observation = visibleEvent.observation
        let screen = visibleEvent.scope == .visible
            ? observation.screen.viewportOnly
            : observation.screen
        return captureSemanticState(
            from: screen,
            tripwireSignal: stash.tripwire.tripwireSignal(),
            settledObservationSequence: observation.sequence
        )
    }

    private func makeCaptureContext(
        screen: InterfaceObservation?,
        tripwireSignal: TheTripwire.TripwireSignal,
        screenId: String? = nil
    ) -> AccessibilityTrace.Context {
        let windows = tripwireSignal.windowStack.windows.enumerated().map { index, window in
            AccessibilityTrace.WindowContext(
                index: index,
                level: Double(window.level),
                isKeyWindow: window.isKeyWindow
            )
        }
        return AccessibilityTrace.Context(
            firstResponder: screen.flatMap { stash.firstResponderTarget(in: $0.tree) },
            keyboardVisible: safecracker.isKeyboardVisible(),
            screenId: screenId ?? stash.lastScreenId,
            windowStack: windows
        )
    }

    // MARK: - Observation Helpers

    static func observationSummary(_ state: BeforeState) -> String {
        var parts = ["interface: \(state.interface.projectedElements.count) elements"]
        if let screenId = state.screenId {
            parts.insert("screen: \(screenId)", at: 0)
        }
        return parts.joined(separator: "; ")
    }

    static func transientElements(
        settleResult: SettleSession.Outcome,
        before: BeforeState,
        final: BeforeState,
        classification: ScreenContinuity
    ) -> [HeistElement] {
        guard case .sameGeneration = classification,
              !settleResult.events.containsTripwireSignalChange else {
            return []
        }
        return SettleSession.transientElements(
            seenByKey: settleResult.elementsByKey,
            baseline: before.elements,
            final: final.elements
        ).map { TheStash.WireConversion.convert($0) }
    }
}

private extension SemanticObservationScope {
    var stateInterfaceProjection: PostActionObservation.StateInterfaceProjection {
        switch self {
        case .visible:
            return .semantic
        case .discovery:
            return .discovery
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

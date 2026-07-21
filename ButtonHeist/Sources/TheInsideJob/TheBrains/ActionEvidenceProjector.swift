#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotModel
import ThePlans
import TheScore

/// A settled semantic observation paired with its trace and summary.
struct SettledObservationEvidence {
    let event: SettledObservationEvent
    let baseline: ActionEvidenceProjector.Baseline
    let accessibilityTrace: AccessibilityTrace
    let summary: String
}

enum SemanticObservationTiming {
    static let defaultTimeout: Double = 1
}

struct SemanticObservationDeadline: Sendable, Equatable {
    let start: RuntimeElapsed.Instant
    private let timeout: Duration

    init(start: RuntimeElapsed.Instant, timeoutSeconds: Double) {
        precondition(timeoutSeconds.isFinite && timeoutSeconds >= 0, "observation timeout must be finite and non-negative")
        self.start = start
        timeout = .seconds(timeoutSeconds)
    }

    init(start: RuntimeElapsed.Instant, timeoutMs: Int) {
        precondition(timeoutMs >= 0, "observation timeout must be non-negative")
        self.init(start: start, timeoutSeconds: Double(timeoutMs) / 1_000)
    }

    var timeoutSeconds: Double {
        timeout / .seconds(1)
    }

    func hasTimeRemaining(at now: RuntimeElapsed.Instant) -> Bool {
        now < deadline
    }

    func remainingSeconds(at now: RuntimeElapsed.Instant = RuntimeElapsed.now) -> Double {
        max(0, now.duration(to: deadline) / .seconds(1))
    }

    func remainingDuration(at now: RuntimeElapsed.Instant = RuntimeElapsed.now) -> Duration {
        let remaining = now.duration(to: deadline)
        return remaining > .zero ? remaining : .zero
    }

    func elapsedMilliseconds(at now: RuntimeElapsed.Instant = RuntimeElapsed.now) -> Int {
        max(0, Int(start.duration(to: now) / .milliseconds(1)))
    }

    func reserving(
        _ seconds: Double,
        at now: RuntimeElapsed.Instant = RuntimeElapsed.now
    ) -> Self {
        precondition(seconds.isFinite && seconds >= 0, "observation reservation must be finite and non-negative")
        return Self(start: now, timeoutSeconds: max(0, remainingSeconds(at: now) - seconds))
    }

    private var deadline: RuntimeElapsed.Instant {
        start.advanced(by: timeout)
    }
}

/// Projects traces, captures, change facts, and action results from supplied semantic
/// states. The action contract is: admitted state → before → action →
/// refresh/settle → after → result.
@MainActor
final class ActionEvidenceProjector {
    let vault: TheVault
    let safecracker: TheSafecracker

    /// State captured before an action for delta computation.
    struct Baseline {
        let observation: InterfaceObservation
        let capture: AccessibilityTrace.Capture
        let tripwireSignal: TheTripwire.TripwireSignal
        let settledObservationSequence: SettledObservationSequence?

        var elements: [AccessibilityElement] { observation.tree.orderedElements.map(\.element) }
        var interface: Interface { capture.interface }
        var interfaceHash: String { observation.tree.interfaceHash }
        @MainActor var screenSnapshot: ScreenClassifier.Snapshot {
            ScreenClassifier.snapshot(of: observation.tree)
        }
        var screenId: String? { observation.tree.id }
    }

    enum Result {
        case committed(settleResult: SettleSession.Result, committedBaseline: Baseline, trace: AccessibilityTrace)
        case diagnostic(settleResult: SettleSession.Result, trace: AccessibilityTrace)
        case unavailable(
            settleResult: SettleSession.Result,
            trace: AccessibilityTrace,
            failureMessage: String
        )
    }

    init(vault: TheVault, safecracker: TheSafecracker) {
        self.vault = vault
        self.safecracker = safecracker
    }

    func projectBaseline(from observation: SettledObservation) -> Baseline {
        projectBaseline(
            from: observation.observation,
            tripwireSignal: vault.tripwire.tripwireSignal(),
            settledObservationSequence: observation.sequence
        )
    }

    func projectBaseline(from evidence: SemanticObservationStore.AdmittedObservation) -> Baseline {
        projectBaseline(
            from: evidence.event.settledObservation.observation,
            tripwireSignal: evidence.tripwireSignal,
            settledObservationSequence: evidence.event.sequence
        )
    }

    func projectSettledEvidence(from event: SettledObservationEvent) -> SettledObservationEvidence {
        let current = projectBaseline(
            from: event.settledObservation.observation,
            tripwireSignal: vault.tripwire.tripwireSignal(),
            settledObservationSequence: event.sequence
        )
        return SettledObservationEvidence(
            event: event,
            baseline: current,
            accessibilityTrace: event.trace,
            summary: Self.observationSummary(current)
        )
    }

    func projectResult(
        before: Baseline,
        observation: ObservationSettlement
    ) -> Result {
        switch observation.commitOutcome {
        case .committed(let event):
            precondition(
                observation.settleResult.outcome.didSettleCleanly,
                "committed observation requires successful settlement"
            )
            let committedBaseline = projectCommittedBaseline(from: event)
            let trace = observedTrace(
                before: before,
                finalBaseline: committedBaseline,
                settleResult: observation.settleResult,
                continuity: event.continuity,
                transitionEvidence: event.trace.captures.last?.transition
            )
            return .committed(
                settleResult: observation.settleResult,
                committedBaseline: committedBaseline,
                trace: trace
            )

        case .observedUnsettled(let viewportObservation, let notificationBatch):
            guard case .timedOut = observation.settleResult.outcome else {
                preconditionFailure("unsettled observation requires settle timeout")
            }
            let finalBaseline = projectBaseline(
                from: viewportObservation,
                tripwireSignal: before.tripwireSignal,
                settledObservationSequence: nil
            )
            let trace = diagnosticObservedTrace(
                before: before,
                finalBaseline: finalBaseline,
                settleResult: observation.settleResult,
                transitionEvidence: diagnosticTransitionEvidence(
                    notificationBatch,
                    in: finalBaseline.observation
                )
            )
            return .diagnostic(settleResult: observation.settleResult, trace: trace)

        case .unavailable(let notificationBatch):
            let trace: AccessibilityTrace
            if let notificationBatch {
                trace = diagnosticObservedTrace(
                    before: before,
                    finalBaseline: before,
                    settleResult: observation.settleResult,
                    transitionEvidence: diagnosticTransitionEvidence(
                        notificationBatch,
                        in: before.observation
                    )
                )
            } else {
                trace = AccessibilityTrace(capture: before.capture)
            }
            switch observation.settleResult.outcome {
            case .cancelled(let timeMs):
                return .unavailable(
                    settleResult: observation.settleResult,
                    trace: trace,
                    failureMessage: "cancelled after \(timeMs)ms"
                )
            case .timedOut:
                return .unavailable(
                    settleResult: observation.settleResult,
                    trace: trace,
                    failureMessage: "Could not capture accessibility tree after action"
                )
            case .settled:
                preconditionFailure("successful settlement requires a committed observation")
            }
        }
    }

    private func observedTrace(
        before: Baseline,
        finalBaseline: Baseline,
        settleResult: SettleSession.Result,
        continuity: ScreenContinuity,
        transitionEvidence: AccessibilityTrace.Transition?
    ) -> AccessibilityTrace {
        return makeAccessibilityTrace(
            afterCapture: finalBaseline.capture,
            parentCapture: before.capture,
            classification: continuity,
            transient: Self.transientElements(
                settleResult: settleResult,
                before: before,
                final: finalBaseline,
                classification: continuity
            ),
            accessibilityNotifications: transitionEvidence?.accessibilityNotifications ?? [],
            accessibilityNotificationGap: transitionEvidence?.accessibilityNotificationGap
        )
    }

    private func diagnosticObservedTrace(
        before: Baseline,
        finalBaseline: Baseline,
        settleResult: SettleSession.Result,
        transitionEvidence: AccessibilityTrace.Transition?
    ) -> AccessibilityTrace {
        let continuity = ScreenClassifier.classify(
            from: before.observation.tree,
            to: finalBaseline.observation.tree,
            notifications: transitionEvidence?.accessibilityNotifications.map(\.kind) ?? []
        )
        return observedTrace(
            before: before,
            finalBaseline: finalBaseline,
            settleResult: settleResult,
            continuity: continuity,
            transitionEvidence: transitionEvidence
        )
    }

    private func diagnosticTransitionEvidence(
        _ notificationBatch: AccessibilityNotificationBatch?,
        in observation: InterfaceObservation
    ) -> AccessibilityTrace.Transition? {
        guard let notificationBatch else { return nil }
        return AccessibilityTrace.Transition(
            accessibilityNotifications: vault.resolveAccessibilityNotificationEvidence(
                notificationBatch.events,
                in: observation
            ),
            accessibilityNotificationGap: notificationBatch.gap
        )
    }

    func projectBaseline(
        from observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        settledObservationSequence: SettledObservationSequence?
    ) -> Baseline {
        let interface = vault.semanticInterface(for: observation)
        let capture = makeTraceCapture(
            interface: interface,
            sequence: 1,
            observation: observation,
            tripwireSignal: tripwireSignal,
            screenId: observation.tree.id
        )
        return Baseline(
            observation: observation,
            capture: capture,
            tripwireSignal: tripwireSignal,
            settledObservationSequence: settledObservationSequence
        )
    }

    static func shouldRecordAccessibilityTrace(
        baseline: Baseline,
        current: Baseline,
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
        observation: InterfaceObservation? = nil,
        tripwireSignal: TheTripwire.TripwireSignal,
        screenId: String? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(
            sequence: sequence,
            interface: interface,
            parentHash: parentHash,
            context: makeCaptureContext(
                observation: observation,
                tripwireSignal: tripwireSignal,
                screenId: screenId
            ),
            transition: transition
        )
    }

    func makeAccessibilityTrace(
        afterCapture: AccessibilityTrace.Capture,
        parentCapture: AccessibilityTrace.Capture? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace {
        let capture = AccessibilityTrace.Capture(
            sequence: (parentCapture?.sequence ?? 0) + 1,
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

    private func projectCommittedBaseline(from visibleEvent: SettledObservationEvent) -> Baseline {
        let settledObservation = visibleEvent.settledObservation
        return projectBaseline(
            from: settledObservation.observation,
            tripwireSignal: vault.tripwire.tripwireSignal(),
            settledObservationSequence: settledObservation.sequence
        )
    }

    private func makeCaptureContext(
        observation: InterfaceObservation?,
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
            firstResponder: observation.flatMap { vault.firstResponderTarget(in: $0.tree) },
            keyboardVisible: safecracker.isKeyboardVisible,
            screenId: screenId ?? vault.lastScreenId,
            windowStack: windows
        )
    }

    // MARK: - Observation Helpers

    static func observationSummary(_ state: Baseline) -> String {
        var parts = ["interface: \(state.interface.projectedElements.count) elements"]
        if let screenId = state.screenId {
            parts.insert("screen: \(screenId)", at: 0)
        }
        return parts.joined(separator: "; ")
    }

    static func transientElements(
        settleResult: SettleSession.Result,
        before: Baseline,
        final: Baseline,
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
        ).map { TheVault.WireConversion.convert($0) }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

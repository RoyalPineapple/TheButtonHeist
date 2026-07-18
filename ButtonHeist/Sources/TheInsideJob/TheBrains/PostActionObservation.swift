#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotModel
import ThePlans
import TheScore

/// A settled semantic observation paired with its trace and summary.
struct SettledObservationEvidence {
    let event: SettledObservationEvent
    let baseline: PostActionObservation.ObservationBaseline
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
/// states. The post-action contract is: admitted clean state → before → action →
/// refresh/settle → after → result.
@MainActor
final class PostActionObservation {
    let vault: TheVault
    let safecracker: TheSafecracker

    /// State captured before an action for delta computation.
    struct ObservationBaseline {
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

    enum SettlementResult {
        case committed(settle: SettleSession.Outcome, finalBaseline: ObservationBaseline, trace: AccessibilityTrace)
        case diagnostic(settle: SettleSession.Outcome, trace: AccessibilityTrace)
        case unavailable(
            settle: SettleSession.Outcome,
            trace: AccessibilityTrace,
            failureMessage: String
        )
    }

    init(vault: TheVault, safecracker: TheSafecracker) {
        self.vault = vault
        self.safecracker = safecracker
    }

    func captureSemanticState(from observation: SettledObservation) -> ObservationBaseline {
        captureSemanticState(
            from: observation.observation,
            tripwireSignal: vault.tripwire.tripwireSignal(),
            settledObservationSequence: observation.sequence
        )
    }

    func captureSemanticState(from evidence: CleanSettledObservation) -> ObservationBaseline {
        captureSemanticState(
            from: evidence.event.settledObservation.observation,
            tripwireSignal: evidence.tripwireSignal,
            settledObservationSequence: evidence.event.sequence
        )
    }

    func semanticObservation(from event: SettledObservationEvent) -> SettledObservationEvidence {
        let current = captureSemanticState(
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

    func settleObservation(
        before: ObservationBaseline,
        commitScope: SemanticObservationScope = .visible,
        outcome: SettleSession.Outcome?,
        notificationWindow: AccessibilityNotificationActionWindow? = nil
    ) async -> ObservationSettlement {
        await vault.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            commitScope: commitScope,
            settleOutcome: outcome,
            notificationWindow: notificationWindow
        )
    }

    func settledObservationResult(
        before: ObservationBaseline,
        observation: ObservationSettlement
    ) -> SettlementResult {
        switch observation.result {
        case .committed(let event):
            precondition(
                observation.settle.outcome.didSettleCleanly,
                "committed observation requires clean settle"
            )
            let finalBaseline = captureFinalBaseline(after: event)
            let trace = observedTrace(
                before: before,
                finalBaseline: finalBaseline,
                settle: observation.settle,
                continuity: event.continuity,
                transitionEvidence: event.trace.captures.last?.transition
            )
            return .committed(
                settle: observation.settle,
                finalBaseline: finalBaseline,
                trace: trace
            )

        case .observedUnsettled(let tree, let notificationBatch):
            guard case .timedOut = observation.settle.outcome else {
                preconditionFailure("unsettled observation requires settle timeout")
            }
            let viewportObservation: InterfaceObservation
            do {
                viewportObservation = try InterfaceObservation.build(tree: tree)
            } catch {
                preconditionFailure("Unsettled semantic observation failed validation: \(error)")
            }
            let finalBaseline = captureSemanticState(
                from: viewportObservation,
                tripwireSignal: before.tripwireSignal,
                settledObservationSequence: nil
            )
            let trace = diagnosticObservedTrace(
                before: before,
                finalBaseline: finalBaseline,
                settle: observation.settle,
                transitionEvidence: diagnosticTransitionEvidence(
                    notificationBatch,
                    in: finalBaseline.observation
                )
            )
            return .diagnostic(settle: observation.settle, trace: trace)

        case .unavailable(let notificationBatch):
            let trace: AccessibilityTrace
            if let notificationBatch {
                trace = diagnosticObservedTrace(
                    before: before,
                    finalBaseline: before,
                    settle: observation.settle,
                    transitionEvidence: diagnosticTransitionEvidence(
                        notificationBatch,
                        in: before.observation
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
        before: ObservationBaseline,
        finalBaseline: ObservationBaseline,
        settle: SettleSession.Outcome,
        continuity: ScreenContinuity,
        transitionEvidence: AccessibilityTrace.Transition?
    ) -> AccessibilityTrace {
        return makeAccessibilityTrace(
            afterCapture: finalBaseline.capture,
            parentCapture: before.capture,
            classification: continuity,
            transient: Self.transientElements(
                settleResult: settle,
                before: before,
                final: finalBaseline,
                classification: continuity
            ),
            accessibilityNotifications: transitionEvidence?.accessibilityNotifications ?? [],
            accessibilityNotificationGap: transitionEvidence?.accessibilityNotificationGap
        )
    }

    private func diagnosticObservedTrace(
        before: ObservationBaseline,
        finalBaseline: ObservationBaseline,
        settle: SettleSession.Outcome,
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
            settle: settle,
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

    func captureSemanticState(
        from observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        settledObservationSequence: SettledObservationSequence?
    ) -> ObservationBaseline {
        let interface = vault.semanticInterface(for: observation)
        let capture = makeTraceCapture(
            interface: interface,
            sequence: 1,
            observation: observation,
            tripwireSignal: tripwireSignal,
            screenId: observation.tree.id
        )
        return ObservationBaseline(
            observation: observation,
            capture: capture,
            tripwireSignal: tripwireSignal,
            settledObservationSequence: settledObservationSequence
        )
    }

    static func shouldRecordAccessibilityTrace(
        baseline: ObservationBaseline,
        current: ObservationBaseline,
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

    private func captureFinalBaseline(after visibleEvent: SettledObservationEvent) -> ObservationBaseline {
        let settledObservation = visibleEvent.settledObservation
        return captureSemanticState(
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
            keyboardVisible: safecracker.isKeyboardVisible(),
            screenId: screenId ?? vault.lastScreenId,
            windowStack: windows
        )
    }

    // MARK: - Observation Helpers

    static func observationSummary(_ state: ObservationBaseline) -> String {
        var parts = ["interface: \(state.interface.projectedElements.count) elements"]
        if let screenId = state.screenId {
            parts.insert("screen: \(screenId)", at: 0)
        }
        return parts.joined(separator: "; ")
    }

    static func transientElements(
        settleResult: SettleSession.Outcome,
        before: ObservationBaseline,
        final: ObservationBaseline,
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

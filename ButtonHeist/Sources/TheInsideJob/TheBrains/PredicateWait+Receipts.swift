#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension PredicateWait {
    internal func waitReceiptWithoutInitialObservation(
        for step: ResolvedWaitStep,
        initialTrace: AccessibilityTrace?,
        start: CFAbsoluteTime,
        shouldPoll: Bool,
        observationScope: SemanticObservationScope
    ) async -> HeistWaitReceipt {
        var state = State(predicate: step.predicate)
        var stream = PredicateObservationStreamState()
        let timeout = Self.clampedWaitTimeout(step.timeout)
        let reducer = Reducer(
            step: step,
            timeout: timeout
        )

        if shouldPoll {
            var waitState = state
            let pollResult = await PredicatePollingEngine<Decision>(
                observeSemanticState: observeSemanticState
            ).poll(
                scope: observationScope,
                timeout: step.timeout,
                start: start,
                after: nil,
                pollWhenTimeoutZero: false,
                discoveryBootstrap: .afterInitialDiscoveryAttempt,
                evaluate: { observation in
                    let baselineSeed: PredicateObservationBaselineSeed =
                        step.predicate.requiresChangeBaseline && stream.changeBaseline == nil
                            ? .previousObservationIfAvailable
                            : .preserve
                    let reduced = reduceObservation(
                        observation,
                        predicate: step.predicate,
                        baselineSeed: baselineSeed,
                        stream: stream
                    )
                    stream = reduced.state
                    let decision = reducer.decision(
                        after: .observation(Snapshot(reduced.reduction)),
                        reducing: waitState,
                        timedOutWhenUnmatched: false
                    )
                    waitState = decision.state
                    return decision
                },
                isMatched: \.isSatisfied
            )

            state = pollResult.last?.evaluation.state ?? waitState
            if let decision = pollResult.last?.evaluation {
                if let receipt = terminalReceipt(for: decision, step: step, state: &state, start: start) {
                    return receipt
                }
            }
        }

        if let receipt = terminalReceipt(
            for: reducer.decision(state, timedOutWhenUnmatched: false),
            step: step,
            state: &state,
            start: start
        ) {
            return receipt
        }

        if let traceEvaluation = initialTraceChangeEvaluation(
            for: step.predicate,
            initialTrace: initialTrace
        ) {
            return waitReceipt(
                for: step,
                trace: initialTrace,
                observationSummary: nil,
                expectation: traceEvaluation,
                start: start,
                success: traceEvaluation.met
            )
        }
        return waitReceipt(for: step, state: state, start: start, success: false)
    }

    internal func terminalReceipt(
        for decision: Decision,
        step: ResolvedWaitStep,
        state: inout State,
        start: CFAbsoluteTime
    ) -> HeistWaitReceipt? {
        state = decision.state
        switch decision {
        case .satisfied(_, let warning):
            return waitReceipt(for: step, state: state, start: start, success: true, warning: warning)
        case .failed:
            return waitReceipt(for: step, state: state, start: start, success: false)
        case .poll:
            return nil
        }
    }

    internal func waitForAnnouncementPredicate(
        _ predicate: AnnouncementPredicate,
        step: ResolvedWaitStep,
        initialTrace: AccessibilityTrace?,
        start: CFAbsoluteTime,
        timeout: Double,
        cursorStrategy: AnnouncementWaitCursorStrategy
    ) async -> HeistWaitReceipt {
        if let initialTrace {
            return announcementReceiptFromInitialTrace(
                predicate,
                step: step,
                trace: initialTrace,
                start: start
            )
        }

        let cursor = announcementCursor(cursorStrategy)
        guard let announcement = await waitForAnnouncement(cursor, predicate, timeout) else {
            let message = Self.announcementTimeoutMessage(predicate, timeout: timeout)
            let expectation = ExpectationResult(
                met: false,
                predicate: step.predicate,
                actual: message
            )
            return .timedOut(
                message: message,
                accessibilityTrace: nil,
                expectation: expectation
            )
        }

        let elapsed = Self.elapsedSeconds(since: start)
        let expectation = ExpectationResult(
            met: true,
            predicate: step.predicate,
            actual: announcement.text
        )
        return .matched(
            message: Self.announcementMatchedMessage(announcement, elapsed: elapsed),
            accessibilityTrace: nil,
            expectation: expectation,
            announcement: announcement.text
        )
    }

    private func announcementReceiptFromInitialTrace(
        _ predicate: AnnouncementPredicate,
        step: ResolvedWaitStep,
        trace: AccessibilityTrace,
        start: CFAbsoluteTime
    ) -> HeistWaitReceipt {
        guard let announcement = trace.capturedAnnouncements.first else {
            let message = Self.missingActionAnnouncementMessage(predicate)
            return .timedOut(
                message: message,
                accessibilityTrace: trace,
                expectation: ExpectationResult(
                    met: false,
                    predicate: step.predicate,
                    actual: message
                )
            )
        }

        guard predicate.matches(announcement.text) else {
            let message = Self.mismatchedActionAnnouncementMessage(
                predicate,
                actual: announcement.text
            )
            return .failed(
                errorKind: .actionFailed,
                message: message,
                accessibilityTrace: trace,
                expectation: ExpectationResult(
                    met: false,
                    predicate: step.predicate,
                    actual: message
                ),
                announcement: announcement.text
            )
        }

        return .matched(
            message: Self.announcementMatchedMessage(
                announcement,
                elapsed: Self.elapsedSeconds(since: start)
            ),
            accessibilityTrace: trace,
            expectation: ExpectationResult(
                met: true,
                predicate: step.predicate,
                actual: announcement.text
            ),
            announcement: announcement.text
        )
    }

    internal func waitReceipt(
        for step: ResolvedWaitStep,
        trace: AccessibilityTrace? = nil,
        observationSummary: String? = nil,
        expectation: ExpectationResult,
        start: CFAbsoluteTime,
        success: Bool,
        warning: HeistPredicateWarning? = nil,
        baseline: SettledCapture? = nil,
        window: ObservationWindow? = nil,
        observedSequence: SettledObservationSequence? = nil
    ) -> HeistWaitReceipt {
        let elapsed = Self.elapsedSeconds(since: start)
        let presenceMessage = success || observationSummary == nil
            ? nil
            : presenceTimeoutMessage(step.predicate, elapsed)
        let latest = latestEvent()
        let settledDiagnostics = success ? nil : SettledWaitDiagnostics(
            baseline: baseline,
            window: window,
            last: latest.map(SettledEventSummary.init(event:)),
            lastChangeFact: trace?.changeFacts.last ?? latest?.trace.changeFacts.last,
            settleFailure: latestSettleFailure()
        )
        return Self.waitReceipt(
            for: step,
            trace: trace,
            observationSummary: observationSummary,
            expectation: expectation,
            elapsed: elapsed,
            success: success,
            warning: warning,
            presenceTimeoutMessage: presenceMessage,
            settledDiagnostics: settledDiagnostics,
            observedSequence: observedSequence
        )
    }

    internal func waitReceipt(
        for step: ResolvedWaitStep,
        state: State,
        start: CFAbsoluteTime,
        success: Bool,
        warning: HeistPredicateWarning? = nil
    ) -> HeistWaitReceipt {
        let expectation = warning.map {
            ExpectationResult(met: true, predicate: step.predicate, actual: $0.message)
        } ?? state.evaluation
        return waitReceipt(
            for: step,
            trace: state.lastTrace,
            observationSummary: state.lastObservationSummary,
            expectation: expectation,
            start: start,
            success: success,
            warning: warning,
            baseline: state.changeBaseline,
            window: state.observationWindow,
            observedSequence: state.observedSequence
        )
    }

    internal nonisolated static func clampedWaitTimeout(_ timeout: Double) -> Double {
        max(immediateTimeout, min(timeout, defaultWaitTimeout))
    }

    internal static func unresolvedWaitPredicate() -> AccessibilityPredicate<RootContext> {
        .missing(.identifier("__unresolved_heist_predicate__"))
    }

    internal static let changePredicateNeedsFutureObservationMessage =
        PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage

    private static func elapsedSeconds(since start: CFAbsoluteTime) -> String {
        String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
    }

    private static func waitReceipt(
        for step: ResolvedWaitStep,
        trace: AccessibilityTrace?,
        observationSummary: String?,
        expectation: ExpectationResult,
        elapsed: String,
        success: Bool,
        warning: HeistPredicateWarning? = nil,
        presenceTimeoutMessage: String? = nil,
        settledDiagnostics: SettledWaitDiagnostics? = nil,
        observedSequence: SettledObservationSequence? = nil
    ) -> HeistWaitReceipt {
        let message = warning?.message ?? (success
            ? waitSuccessMessage(for: step.predicate, elapsed: elapsed)
            : waitTimeoutMessage(
                for: step,
                expectation: expectation,
                observationSummary: observationSummary,
                elapsed: elapsed,
                presenceTimeoutMessage: presenceTimeoutMessage,
                settledDiagnostics: settledDiagnostics
            ))
        if success {
            return .matched(
                message: message,
                accessibilityTrace: trace,
                expectation: expectation,
                observedSequence: observedSequence,
                observationSummary: observationSummary,
                warning: warning
            )
        }
        return .timedOut(
            message: message,
            accessibilityTrace: trace,
            expectation: expectation,
            observedSequence: observedSequence,
            observationSummary: observationSummary
        )
    }

    private static func waitSuccessMessage(
        for predicate: AccessibilityPredicate<RootContext>,
        elapsed: String
    ) -> String {
        switch predicate.node {
        case .exists:
            return elapsed == "0.0" ? "matched immediately" : "matched after \(elapsed)s"
        case .missing:
            return "absent confirmed after \(elapsed)s"
        default:
            return "predicate met after \(elapsed)s"
        }
    }

    private static func announcementMatchedMessage(
        _ announcement: CapturedAnnouncement,
        elapsed: String
    ) -> String {
        let message = "announcement \"\(announcement.text)\""
        return elapsed == "0.0" ? message : "\(message) after \(elapsed)s"
    }

    private static func missingActionAnnouncementMessage(_ predicate: AnnouncementPredicate) -> String {
        "expected \(expectedActionAnnouncement(predicate)) but none was posted"
    }

    private static func mismatchedActionAnnouncementMessage(
        _ predicate: AnnouncementPredicate,
        actual: String
    ) -> String {
        "expected \(expectedActionAnnouncement(predicate)) but got '\(singleQuoted(actual))'"
    }

    private static func announcementTimeoutMessage(
        _ predicate: AnnouncementPredicate,
        timeout: Double
    ) -> String {
        "no \(matchingAnnouncement(predicate)) within \(String(format: "%.1f", timeout))s"
    }

    private static func expectedActionAnnouncement(_ predicate: AnnouncementPredicate) -> String {
        announcementMatchDescription(
            predicate,
            any: "an announcement",
            exact: { "'\($0)'" },
            contains: { "announcement containing '\($0)'" },
            empty: "an empty announcement"
        )
    }

    private static func matchingAnnouncement(_ predicate: AnnouncementPredicate) -> String {
        announcementMatchDescription(
            predicate,
            any: "announcement",
            exact: { "announcement matching '\($0)'" },
            contains: { "announcement matching '\($0)'" },
            empty: "empty announcement"
        )
    }

    private static func announcementMatchDescription(
        _ predicate: AnnouncementPredicate,
        any: String,
        exact: (String) -> String,
        contains: (String) -> String,
        empty: String
    ) -> String {
        guard let match = predicate.match else { return any }
        switch match.mode {
        case .exact:
            return exact(singleQuoted(match.value))
        case .contains:
            return contains(singleQuoted(match.value))
        case .prefix:
            return "announcement prefixed by '\(singleQuoted(match.value))'"
        case .suffix:
            return "announcement suffixed by '\(singleQuoted(match.value))'"
        case .isEmpty:
            return empty
        }
    }

    private static func singleQuoted(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "\\'")
    }

    private static func waitTimeoutMessage(
        for step: ResolvedWaitStep,
        expectation: ExpectationResult,
        observationSummary: String?,
        elapsed: String,
        presenceTimeoutMessage: String?,
        settledDiagnostics: SettledWaitDiagnostics?
    ) -> String {
        let diagnostics = settledDiagnostics.map(settledDiagnosticsMessage) ?? []
        guard let observationSummary else {
            return ([
                "timed out after \(elapsed)s waiting for heist predicate",
                "expected: \(step.predicate.description)",
                "last result: \(expectation.actual ?? "not met")",
                "last observed: no settled semantic observation available",
            ] + diagnostics).joined(separator: "; ")
        }

        if let presenceTimeoutMessage {
            return ([presenceTimeoutMessage] + diagnostics).joined(separator: "; ")
        }

        return ([
            "timed out after \(elapsed)s waiting for heist predicate",
            "expected: \(step.predicate.description)",
            "last result: \(expectation.actual ?? "not met")",
            "last observed: \(observationSummary)",
        ] + diagnostics).joined(separator: "; ")
    }

    private static func settledDiagnosticsMessage(_ diagnostics: SettledWaitDiagnostics) -> [String] {
        var parts: [String] = []
        if let baseline = diagnostics.baseline {
            parts.append("baseline: \(baseline.description)")
        }
        if let last = diagnostics.last {
            parts.append("last settled: \(last.description)")
        }
        parts.append("last change: \(changeFactSummary(diagnostics.lastChangeFact))")
        if let settleFailure = diagnostics.settleFailure {
            parts.append(settleFailure)
        }
        if diagnostics.baseline != nil, !diagnostics.observedChangeAfterBaseline {
            parts.append("no settled observation arrived after baseline")
        }
        return parts
    }

    private static func changeFactSummary(_ fact: AccessibilityTrace.ChangeFact?) -> String {
        guard let fact else { return "none" }
        switch fact {
        case .elementsChanged:
            return "elements"
        case .screenChanged:
            return "screen"
        }
    }

    private struct SettledEventSummary {
        private let sequence: SettledObservationSequence
        private let hash: String?

        fileprivate init(event: SettledSemanticObservationEvent) {
            sequence = event.sequence
            hash = event.latestCaptureRef?.hash
        }

        fileprivate init(baseline: SettledCapture) {
            sequence = baseline.cursor.sequence
            hash = baseline.capture.hash
        }

        fileprivate var description: String {
            if let hash {
                return "sequence \(sequence), hash \(hash)"
            }
            return "sequence \(sequence), hash unavailable"
        }
    }

    private struct SettledWaitDiagnostics {
        fileprivate let baselineCapture: SettledCapture?
        fileprivate let window: ObservationWindow?
        fileprivate let last: SettledEventSummary?
        fileprivate let lastChangeFact: AccessibilityTrace.ChangeFact?
        fileprivate let settleFailure: String?

        fileprivate init(
            baseline: SettledCapture?,
            window: ObservationWindow?,
            last: SettledEventSummary?,
            lastChangeFact: AccessibilityTrace.ChangeFact?,
            settleFailure: String?
        ) {
            self.baselineCapture = baseline
            self.window = window
            self.last = last
            self.lastChangeFact = lastChangeFact
            self.settleFailure = settleFailure
        }

        fileprivate var baseline: SettledEventSummary? {
            baselineCapture.map(SettledEventSummary.init(baseline:))
        }

        fileprivate var observedChangeAfterBaseline: Bool {
            guard let baselineCapture, let window else { return false }
            return window.current.cursor.sequence > baselineCapture.cursor.sequence
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

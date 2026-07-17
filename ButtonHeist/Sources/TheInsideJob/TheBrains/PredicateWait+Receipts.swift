#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension PredicateWait {
    internal func waitForAnnouncementPredicate(
        _ predicate: ResolvedAnnouncementPredicate,
        step: ResolvedWaitRuntimeInput,
        initialTrace: AccessibilityTrace?,
        start: CFAbsoluteTime,
        timeout: WaitTimeout,
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
        guard let announcement = await waitForAnnouncement(cursor, predicate, timeout.seconds) else {
            let message = Self.announcementTimeoutMessage(predicate, timeout: timeout)
            let expectation = ExpectationResult.Unmet(
                predicate: step.predicateExpression,
                actual: message
            )
            return .timedOut(
                message: message,
                traceEvidence: nil,
                expectation: expectation
            )
        }
        let announcementText: ActionAnnouncementText
        do {
            announcementText = try ActionAnnouncementText(validating: announcement.text)
        } catch {
            let message = String(describing: error)
            return .failed(
                errorKind: .validationError,
                message: message,
                traceEvidence: nil,
                expectation: ExpectationResult.Unmet(
                    predicate: step.predicateExpression,
                    actual: message
                )
            )
        }

        let elapsed = Self.elapsedSeconds(since: start)
        let expectation = ExpectationResult.Met(
            predicate: step.predicateExpression,
            actual: announcement.text
        )
        return .matched(
            message: Self.announcementMatchedMessage(announcement, elapsed: elapsed),
            traceEvidence: nil,
            expectation: expectation,
            announcement: announcementText
        )
    }

    private func announcementReceiptFromInitialTrace(
        _ predicate: ResolvedAnnouncementPredicate,
        step: ResolvedWaitRuntimeInput,
        trace: AccessibilityTrace,
        start: CFAbsoluteTime
    ) -> HeistWaitReceipt {
        guard let announcement = trace.capturedAnnouncements.first else {
            let message = Self.missingActionAnnouncementMessage(predicate)
            return .timedOut(
                message: message,
                traceEvidence: Self.incompleteTraceEvidence(trace),
                expectation: ExpectationResult.Unmet(
                    predicate: step.predicateExpression,
                    actual: message
                )
            )
        }
        let announcementText: ActionAnnouncementText
        do {
            announcementText = try ActionAnnouncementText(validating: announcement.text)
        } catch {
            let message = String(describing: error)
            return .failed(
                errorKind: .validationError,
                message: message,
                traceEvidence: Self.incompleteTraceEvidence(trace),
                expectation: ExpectationResult.Unmet(
                    predicate: step.predicateExpression,
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
                traceEvidence: Self.incompleteTraceEvidence(trace),
                expectation: ExpectationResult.Unmet(
                    predicate: step.predicateExpression,
                    actual: message
                ),
                announcement: announcementText
            )
        }

        return .matched(
            message: Self.announcementMatchedMessage(
                announcement,
                elapsed: Self.elapsedSeconds(since: start)
            ),
            traceEvidence: Self.incompleteTraceEvidence(trace),
            expectation: ExpectationResult.Met(
                predicate: step.predicateExpression,
                actual: announcement.text
            ),
            announcement: announcementText
        )
    }

    internal func waitReceipt(
        for step: ResolvedWaitRuntimeInput,
        trace: AccessibilityTrace? = nil,
        observationSummary: String? = nil,
        expectation: ExpectationResult,
        start: CFAbsoluteTime,
        success: Bool,
        baseline: SettledCapture? = nil,
        window: ObservationWindow? = nil,
        observedSequence: SettledObservationSequence? = nil
    ) -> HeistWaitReceipt {
        let elapsed = Self.elapsedSeconds(since: start)
        let presenceMessage = success || observationSummary == nil
            ? nil
            : presenceTimeoutMessage(step.predicate, elapsed)
        let latest = latestEvent()
        let traceEvidence = window?.traceEvidence ?? trace.flatMap {
            AccessibilityTraceEvidence(trace: $0, completeness: .incomplete)
        }
        let settledDiagnostics = success ? nil : SettledWaitDiagnostics(
            baseline: baseline,
            window: window,
            last: latest.map(SettledEventSummary.init(event:)),
            lastChangeFact: trace?.changeFacts.last ?? latest?.trace.changeFacts.last,
            settleFailure: latestSettleFailure()
        )
        return Self.waitReceipt(
            for: step,
            traceEvidence: traceEvidence,
            observationSummary: observationSummary,
            expectation: expectation,
            elapsed: elapsed,
            success: success,
            presenceTimeoutMessage: presenceMessage,
            settledDiagnostics: settledDiagnostics,
            observedSequence: observedSequence
        )
    }

    internal func waitReceipt(
        for step: ResolvedWaitRuntimeInput,
        evidence: LifecycleEvidence,
        start: CFAbsoluteTime,
        success: Bool
    ) -> HeistWaitReceipt {
        return waitReceipt(
            for: step,
            trace: evidence.lastTrace,
            observationSummary: evidence.lastObservationSummary,
            expectation: evidence.evaluation,
            start: start,
            success: success,
            baseline: evidence.changeBaseline,
            window: evidence.observationWindow,
            observedSequence: evidence.observedSequence
        )
    }

    internal static let changePredicateNeedsFutureObservationMessage =
        PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage

    private static func elapsedSeconds(since start: CFAbsoluteTime) -> String {
        String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
    }

    private static func waitReceipt(
        for step: ResolvedWaitRuntimeInput,
        traceEvidence: AccessibilityTraceEvidence?,
        observationSummary: String?,
        expectation: ExpectationResult,
        elapsed: String,
        success: Bool,
        presenceTimeoutMessage: String? = nil,
        settledDiagnostics: SettledWaitDiagnostics? = nil,
        observedSequence: SettledObservationSequence? = nil
    ) -> HeistWaitReceipt {
        let message = success
            ? waitSuccessMessage(for: step.predicate, elapsed: elapsed)
            : waitTimeoutMessage(
                for: step,
                expectation: expectation,
                observationSummary: observationSummary,
                elapsed: elapsed,
                presenceTimeoutMessage: presenceTimeoutMessage,
                settledDiagnostics: settledDiagnostics
            )
        switch (success, expectation) {
        case (true, .met(let expectation)):
            return .matched(
                message: message,
                traceEvidence: traceEvidence,
                expectation: expectation,
                observedSequence: observedSequence,
                observationSummary: observationSummary
            )
        case (false, .unmet(let expectation)):
            return .timedOut(
                message: message,
                traceEvidence: traceEvidence,
                expectation: expectation,
                observedSequence: observedSequence,
                observationSummary: observationSummary
            )
        case (true, .unmet):
            preconditionFailure("Successful predicate wait requires a met expectation")
        case (false, .met):
            preconditionFailure("Timed-out predicate wait requires an unmet expectation")
        }
    }

    private static func waitSuccessMessage(
        for predicate: ResolvedAccessibilityPredicate,
        elapsed: String
    ) -> String {
        switch predicate.core {
        case .presence(.exists):
            return elapsed == "0.0" ? "matched immediately" : "matched after \(elapsed)s"
        case .presence(.missing):
            return "absent confirmed after \(elapsed)s"
        default:
            return "predicate met after \(elapsed)s"
        }
    }

    private static func incompleteTraceEvidence(_ trace: AccessibilityTrace) -> AccessibilityTraceEvidence {
        guard let evidence = AccessibilityTraceEvidence(
            trace: trace,
            completeness: .incomplete
        ) else {
            preconditionFailure("predicate wait trace evidence requires a current capture")
        }
        return evidence
    }

    private static func announcementMatchedMessage(
        _ announcement: CapturedAnnouncement,
        elapsed: String
    ) -> String {
        let message = "announcement \"\(announcement.text)\""
        return elapsed == "0.0" ? message : "\(message) after \(elapsed)s"
    }

    private static func missingActionAnnouncementMessage(_ predicate: ResolvedAnnouncementPredicate) -> String {
        "expected \(expectedActionAnnouncement(predicate)) but none was posted"
    }

    private static func mismatchedActionAnnouncementMessage(
        _ predicate: ResolvedAnnouncementPredicate,
        actual: String
    ) -> String {
        "expected \(expectedActionAnnouncement(predicate)) but got '\(singleQuoted(actual))'"
    }

    private static func announcementTimeoutMessage(
        _ predicate: ResolvedAnnouncementPredicate,
        timeout: WaitTimeout
    ) -> String {
        "no \(matchingAnnouncement(predicate)) within \(String(format: "%.1f", timeout.seconds))s"
    }

    private static func expectedActionAnnouncement(_ predicate: ResolvedAnnouncementPredicate) -> String {
        announcementMatchDescription(
            predicate,
            any: "an announcement",
            exact: { "'\($0)'" },
            contains: { "announcement containing '\($0)'" },
            empty: "an empty announcement"
        )
    }

    private static func matchingAnnouncement(_ predicate: ResolvedAnnouncementPredicate) -> String {
        announcementMatchDescription(
            predicate,
            any: "announcement",
            exact: { "announcement matching '\($0)'" },
            contains: { "announcement matching '\($0)'" },
            empty: "empty announcement"
        )
    }

    private static func announcementMatchDescription(
        _ predicate: ResolvedAnnouncementPredicate,
        any: String,
        exact: (String) -> String,
        contains: (String) -> String,
        empty: String
    ) -> String {
        guard let match = predicate.match else { return any }
        switch match.core {
        case .exact(let value):
            return exact(singleQuoted(value))
        case .contains(let value):
            return contains(singleQuoted(value))
        case .prefix(let value):
            return "announcement prefixed by '\(singleQuoted(value))'"
        case .suffix(let value):
            return "announcement suffixed by '\(singleQuoted(value))'"
        case .isEmpty:
            return empty
        }
    }

    private static func singleQuoted(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "\\'")
    }

    private static func waitTimeoutMessage(
        for step: ResolvedWaitRuntimeInput,
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

        fileprivate init(event: SettledObservationEvent) {
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

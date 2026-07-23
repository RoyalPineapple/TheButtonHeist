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
        start: RuntimeElapsed.Instant,
        timeout: WaitTimeout,
        cursor: AccessibilityNotificationCursor,
        isActionExpectation: Bool
    ) async -> HeistWaitResult {
        if let initialTrace {
            return announcementResultFromInitialTrace(
                predicate,
                step: step,
                trace: initialTrace,
                start: start
            )
        }

        switch await vault.accessibilityNotifications.waitForAnnouncement(
            after: cursor,
            matching: predicate,
            timeout: timeout.seconds
        ) {
        case .matched(let announcement):
            return announcementResult(
                announcement,
                predicate: predicate,
                step: step,
                start: start
            )
        case .timedOut:
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
        case .historyUnavailable(let gap):
            let message = isActionExpectation
                ? "Action expectation announcement history unavailable: dropped through sequence \(gap.droppedThroughSequence)"
                : "Announcement history unexpectedly unavailable: dropped through sequence \(gap.droppedThroughSequence)"
            return .failed(
                failureKind: .actionFailed,
                message: message,
                traceEvidence: nil,
                expectation: ExpectationResult.Unmet(
                    predicate: step.predicateExpression,
                    actual: message
                )
            )
        }
    }

    private func announcementResult(
        _ announcement: CapturedAnnouncement,
        predicate: ResolvedAnnouncementPredicate,
        step: ResolvedWaitRuntimeInput,
        start: RuntimeElapsed.Instant
    ) -> HeistWaitResult {
        let announcementText: ActionAnnouncementText
        do {
            announcementText = try ActionAnnouncementText(validating: announcement.text)
        } catch {
            let message = String(describing: error)
            return .failed(
                failureKind: .validationError,
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

    private func announcementResultFromInitialTrace(
        _ predicate: ResolvedAnnouncementPredicate,
        step: ResolvedWaitRuntimeInput,
        trace: AccessibilityTrace,
        start: RuntimeElapsed.Instant
    ) -> HeistWaitResult {
        let announcements = trace.capturedAnnouncements
        guard let firstAnnouncement = announcements.first else {
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
        let announcement = announcements.first {
            predicate.matches($0.text)
        } ?? firstAnnouncement
        let announcementText: ActionAnnouncementText
        do {
            announcementText = try ActionAnnouncementText(validating: announcement.text)
        } catch {
            let message = String(describing: error)
            return .failed(
                failureKind: .validationError,
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
                failureKind: .actionFailed,
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

    internal func waitResult(
        for step: ResolvedWaitRuntimeInput,
        trace: AccessibilityTrace? = nil,
        observationSummary: String? = nil,
        expectation: ExpectationResult,
        start: RuntimeElapsed.Instant,
        success: Bool,
        baseline: Observation.Moment? = nil,
        eventsSinceBaseline: Observation.EventsSince? = nil,
        observedSequence: SettledObservationSequence? = nil,
        timeoutMismatchMessage: String? = nil
    ) async -> HeistWaitResult {
        let elapsed = Self.elapsedSeconds(since: start)
        let presenceMessage = success || observationSummary == nil
            ? nil
            : presenceTimeoutMessage(step.predicate, elapsed)
        let latest = await latestCommittedEvent()
        let traceEvidence = PredicateObservationEvidence.traceEvidence(
            baseline: baseline,
            eventsSinceBaseline: eventsSinceBaseline,
            through: latest
        ) ?? trace.flatMap {
            AccessibilityTraceEvidence(trace: $0, completeness: .incomplete)
        }
        let settledDiagnostics = success ? nil : SettledWaitDiagnostics(
            baseline: baseline,
            observedSequence: observedSequence,
            last: latest.map(SettledEventSummary.init(event:)),
            lastChangeFact: trace?.changeFacts.last ?? latest?.trace.changeFacts.last,
            settleFailure: await latestSettleFailure()
        )
        return Self.waitResult(
            for: step,
            traceEvidence: traceEvidence,
            observationSummary: observationSummary,
            expectation: expectation,
            elapsed: elapsed,
            success: success,
            presenceTimeoutMessage: presenceMessage,
            settledDiagnostics: settledDiagnostics,
            observedSequence: observedSequence,
            timeoutMismatchMessage: timeoutMismatchMessage
        )
    }

    internal static let changePredicateNeedsFutureObservationMessage =
        PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage

    private static func elapsedSeconds(since start: RuntimeElapsed.Instant) -> String {
        String(format: "%.1f", RuntimeElapsed.seconds(since: start))
    }

    private static func waitResult(
        for step: ResolvedWaitRuntimeInput,
        traceEvidence: AccessibilityTraceEvidence?,
        observationSummary: String?,
        expectation: ExpectationResult,
        elapsed: String,
        success: Bool,
        presenceTimeoutMessage: String? = nil,
        settledDiagnostics: SettledWaitDiagnostics? = nil,
        observedSequence: SettledObservationSequence? = nil,
        timeoutMismatchMessage: String? = nil
    ) -> HeistWaitResult {
        let message = success
            ? waitSuccessMessage(for: step.predicate, elapsed: elapsed)
            : [
                waitTimeoutMessage(
                    for: step,
                    expectation: expectation,
                    observationSummary: observationSummary,
                    elapsed: elapsed,
                    presenceTimeoutMessage: presenceTimeoutMessage,
                    settledDiagnostics: settledDiagnostics
                ),
                timeoutMismatchMessage,
            ].compactMap { $0 }.joined(separator: "; ")
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

        fileprivate init(event: Observation.SnapshotEvent) {
            sequence = event.sequence
            hash = event.latestCaptureRef?.hash
        }

        fileprivate init(baseline: Observation.Moment) {
            sequence = baseline.sequence
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
        fileprivate let baselineCapture: Observation.Moment?
        fileprivate let observedSequence: SettledObservationSequence?
        fileprivate let last: SettledEventSummary?
        fileprivate let lastChangeFact: AccessibilityTrace.ChangeFact?
        fileprivate let settleFailure: String?

        fileprivate init(
            baseline: Observation.Moment?,
            observedSequence: SettledObservationSequence?,
            last: SettledEventSummary?,
            lastChangeFact: AccessibilityTrace.ChangeFact?,
            settleFailure: String?
        ) {
            self.baselineCapture = baseline
            self.observedSequence = observedSequence
            self.last = last
            self.lastChangeFact = lastChangeFact
            self.settleFailure = settleFailure
        }

        fileprivate var baseline: SettledEventSummary? {
            baselineCapture.map(SettledEventSummary.init(baseline:))
        }

        fileprivate var observedChangeAfterBaseline: Bool {
            guard let baselineCapture, let observedSequence else { return false }
            return observedSequence > baselineCapture.sequence
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

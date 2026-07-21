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
        cursorStrategy: AnnouncementWaitCursorStrategy,
        continuity: PredicateWaitContinuity
    ) async -> HeistWaitResult {
        if let initialTrace {
            return announcementResultFromInitialTrace(
                predicate,
                step: step,
                trace: initialTrace,
                start: start
            )
        }

        let cursor = announcementCursor(cursorStrategy)
        let waitStart = vault.accessibilityNotifications.cursor()
        var continuityEvidence = continuity.initialEvidence(for: .announcement)
        if case .candidate(_, let boundary) = continuity {
            let notifications = vault.accessibilityNotifications
            let retained = notifications.announcements(after: boundary.notificationCursor)
            if let current = retained.first(where: {
                $0.sequence > cursor.sequence && predicate.matches($0.text)
            }) {
                recordAnnouncementMatch(current)
                continuityEvidence = continuityEvidence?.recordingAnnouncementCurrent(
                    observedThrough: notifications.cursor().continuityPosition
                )
                return announcementResult(
                    current,
                    predicate: predicate,
                    step: step,
                    start: start,
                    continuity: continuityEvidence
                )
            }
            if !notifications.retainsHistory(after: boundary.notificationCursor) {
                continuityEvidence = EvidenceContinuity.WaitEvidence(
                    status: .fallback(reason: .announcementHistoryUnavailable)
                )
            } else if let historical = retained.first(where: { predicate.matches($0.text) }) {
                recordAnnouncementMatch(historical)
                let position = AccessibilityNotificationCursor(
                    sequence: historical.sequence
                ).continuityPosition
                let match: EvidenceContinuity.MatchSource = historical.sequence > waitStart.sequence
                    ? .current
                    : .backdated(position: position)
                continuityEvidence = continuityEvidence?.recordingAnnouncementApplied(
                    observedThrough: notifications.cursor().continuityPosition,
                    match: match
                )
                if case .backdated = match {
                    recordBackdatedContinuityMatch()
                }
                return announcementResult(
                    historical,
                    predicate: predicate,
                    step: step,
                    start: start,
                    continuity: continuityEvidence
                )
            }
        }

        guard let announcement = await waitForAnnouncement(cursor, predicate, timeout.seconds) else {
            if case .candidate(_, let boundary) = continuity {
                let notifications = vault.accessibilityNotifications
                continuityEvidence = notifications.retainsHistory(after: boundary.notificationCursor)
                    ? continuityEvidence?.recordingAnnouncementApplied(
                        observedThrough: notifications.cursor().continuityPosition
                    )
                    : EvidenceContinuity.WaitEvidence(
                        status: .fallback(reason: .announcementHistoryUnavailable)
                    )
            }
            let message = Self.announcementTimeoutMessage(predicate, timeout: timeout)
            let expectation = ExpectationResult.Unmet(
                predicate: step.predicateExpression,
                actual: message
            )
            return .timedOut(
                message: message,
                traceEvidence: nil,
                expectation: expectation,
                continuity: continuityEvidence
            )
        }
        if case .candidate(_, let boundary) = continuity,
           !vault.accessibilityNotifications.retainsHistory(after: boundary.notificationCursor) {
            continuityEvidence = EvidenceContinuity.WaitEvidence(
                status: .fallback(reason: .announcementHistoryUnavailable),
                match: .current
            )
        } else {
            continuityEvidence = continuityEvidence?.recordingAnnouncementCurrent(
                observedThrough: vault.accessibilityNotifications.cursor().continuityPosition
            )
        }
        return announcementResult(
            announcement,
            predicate: predicate,
            step: step,
            start: start,
            continuity: continuityEvidence
        )
    }

    private func announcementResult(
        _ announcement: CapturedAnnouncement,
        predicate: ResolvedAnnouncementPredicate,
        step: ResolvedWaitRuntimeInput,
        start: RuntimeElapsed.Instant,
        continuity: EvidenceContinuity.WaitEvidence?
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
                ),
                continuity: continuity
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
            announcement: announcementText,
            continuity: continuity
        )
    }

    private func announcementResultFromInitialTrace(
        _ predicate: ResolvedAnnouncementPredicate,
        step: ResolvedWaitRuntimeInput,
        trace: AccessibilityTrace,
        start: RuntimeElapsed.Instant
    ) -> HeistWaitResult {
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
        baseline: SettledCapture? = nil,
        window: ObservationWindow? = nil,
        observedSequence: SettledObservationSequence? = nil,
        continuity: EvidenceContinuity.WaitEvidence? = nil
    ) -> HeistWaitResult {
        let elapsed = Self.elapsedSeconds(since: start)
        let presenceMessage = success || observationSummary == nil
            ? nil
            : presenceTimeoutMessage(step.predicate, elapsed)
        let latest = latestCommittedEvent()
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
            continuity: continuity
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
        continuity: EvidenceContinuity.WaitEvidence? = nil
    ) -> HeistWaitResult {
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
                observationSummary: observationSummary,
                continuity: continuity
            )
        case (false, .unmet(let expectation)):
            return .timedOut(
                message: message,
                traceEvidence: traceEvidence,
                expectation: expectation,
                observedSequence: observedSequence,
                observationSummary: observationSummary,
                continuity: continuity
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

private extension EvidenceContinuity.WaitEvidence {
    func recordingAnnouncementCurrent(
        observedThrough: EvidenceContinuity.Position
    ) -> EvidenceContinuity.WaitEvidence {
        switch status {
        case .applied:
            return recordingAnnouncementApplied(
                observedThrough: observedThrough,
                match: .current
            )
        case .fallback, .ineligible, .notProvided:
            return EvidenceContinuity.WaitEvidence(status: status, match: .current)
        }
    }

    func recordingAnnouncementApplied(
        observedThrough: EvidenceContinuity.Position,
        match: EvidenceContinuity.MatchSource? = nil
    ) -> EvidenceContinuity.WaitEvidence {
        EvidenceContinuity.WaitEvidence(
            status: status,
            match: match,
            actionBoundary: actionBoundary,
            observedThrough: observedThrough
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

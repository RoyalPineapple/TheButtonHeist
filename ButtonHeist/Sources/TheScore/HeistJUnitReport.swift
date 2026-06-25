import ThePlans
import Foundation

// MARK: - Heist JUnit Report

/// JUnit-compatible summary derived from a `HeistExecutionResult`.
///
/// The XML steps are an adapter traversal of the structured heist execution tree,
/// not the product model for heist results.
public struct HeistJUnitReport: Sendable, Equatable {
    /// Name derived from the input file (e.g. "navigation-flow" from "navigation-flow.heist").
    public let heistName: String
    /// Bundle identifier of the app the heist targets.
    public let app: String
    /// Total number of receipt nodes surfaced in the JUnit adapter.
    public let receiptNodeCount: Int
    /// Total wall-clock time for the entire heist, in seconds.
    public let totalTimeSeconds: Double
    /// Step outcomes in execution order for the JUnit adapter.
    public let steps: [StepResult]

    public init(
        heistName: String,
        app: String,
        receiptNodeCount: Int,
        totalTimeSeconds: Double,
        steps: [StepResult]
    ) {
        self.heistName = heistName
        self.app = app
        self.receiptNodeCount = receiptNodeCount
        self.totalTimeSeconds = totalTimeSeconds
        self.steps = steps
    }

    // MARK: - Derived Properties

    public var passedReceiptNodeCount: Int { steps.count(where: { $0.passed }) }
    public var failedReceiptNodeCount: Int { steps.count(where: { $0.failed }) }
    public var allPassed: Bool { !steps.contains(where: \.failed) }
}

// MARK: - Step Result

extension HeistJUnitReport {
    /// The outcome of executing a single heist step.
    public struct StepResult: Sendable, Equatable {
        /// 0-based display index in the report.
        public let index: Int
        /// Heist report action or structural step name.
        public let command: String
        /// Durable matcher target used to target the element, if any.
        public let target: ElementTarget?
        /// Wall-clock time for this step, in seconds.
        public let timeSeconds: Double
        /// Pass or fail with diagnostic detail.
        public let outcome: Outcome

        public init(
            index: Int,
            command: String,
            target: ElementTarget?,
            timeSeconds: Double,
            outcome: Outcome
        ) {
            self.index = index
            self.command = command
            self.target = target
            self.timeSeconds = timeSeconds
            self.outcome = outcome
        }

        public var passed: Bool {
            if case .passed = outcome { return true }
            return false
        }

        public var failed: Bool {
            if case .failed = outcome { return true }
            return false
        }

        /// Human-readable name for this step (used as testcase name in JUnit).
        public var displayName: String {
            var name = "[\(index)] \(command)"
            if case .predicate(let predicate, _)? = target {
                if let summary = predicate.checks.compactMap(ScoreDescription.predicateCheckField).first {
                    name += " \(summary)"
                }
            }
            return name
        }
    }
}

// MARK: - Report Error Kind

extension HeistJUnitReport {
    /// Classification of why a step failed.
    ///
    /// Command-level failures collapse to `commandError`; action-level failures
    /// wrap `ErrorKind` directly so there's no mirrored case list to keep in sync.
    public enum ReportErrorKind: Sendable, Equatable {
        /// Command-level error (invalid command, missing connection, etc.).
        case commandError
        /// An action-level error reported by the server.
        case action(ErrorKind)

        /// String name for JUnit XML `type` attribute.
        public var typeName: String {
            switch self {
            case .commandError: return "commandError"
            case .action(let kind): return kind.rawValue
            }
        }
    }
}

// MARK: - Outcome

extension HeistJUnitReport {
    /// Whether a step passed or failed, with failure diagnostics.
    public enum Outcome: Sendable, Equatable {
        case passed
        case skipped
        case failed(message: String, errorKind: ReportErrorKind?)

        public var failureMessage: String? {
            if case .failed(let message, _) = self { return message }
            return nil
        }

        public var failureType: ReportErrorKind? {
            if case .failed(_, let kind) = self { return kind }
            return nil
        }
    }
}

// MARK: - JUnit XML

extension HeistJUnitReport {
    /// Generate a JUnit XML report string.
    ///
    /// The structure follows the JUnit XML schema consumed by CI systems
    /// (GitHub Actions, Jenkins, CircleCI, etc.):
    /// ```
    /// <testsuites> → <testsuite> → <testcase> [→ <failure>]
    /// ```
    /// Each heist is one `<testcase>`. A failed heist includes a `<failure>`
    /// element with step-level diagnostics in the body.
    public func junitXML() -> String {
        let totalTime = String(format: "%.3f", totalTimeSeconds)
        let failed = allPassed ? 0 : 1

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<testsuites name=\"heist\" tests=\"1\""
        xml += " failures=\"\(failed)\" time=\"\(totalTime)\">\n"

        xml += "  <testsuite name=\"\(xmlEscape(heistName))\""
        xml += " tests=\"1\" failures=\"\(failed)\""
        xml += " time=\"\(totalTime)\">\n"

        xml += "    <testcase name=\"\(xmlEscape(heistName))\""
        xml += " classname=\"\(xmlEscape(app))\""
        xml += " time=\"\(totalTime)\""

        if allPassed {
            xml += "/>\n"
        } else if let failedStep = steps.first(where: \.failed) {
            xml += ">\n"
            let message = failedStep.outcome.failureMessage ?? "heist failed"
            let failureType = failedStep.outcome.failureType?.typeName ?? "heistFailure"
            xml += "      <failure message=\"\(xmlEscape(message))\""
            xml += " type=\"\(xmlEscape(failureType))\">"
            xml += xmlEscape(failureBody(failedStep: failedStep))
            xml += "</failure>\n"
            xml += "    </testcase>\n"
        }

        xml += "  </testsuite>\n"
        xml += "</testsuites>\n"
        return xml
    }

    // MARK: - Private Helpers

    private func failureBody(failedStep: StepResult) -> String {
        var body = "Completed \(passedReceiptNodeCount)/\(receiptNodeCount) receipt node(s) before failure.\n"
        body += "step: [\(failedStep.index)] \(failedStep.command)\n"
        if let target = failedStep.target {
            var parts: [String] = []
            if case .predicate(let predicate, _) = target {
                parts = predicate.checks.compactMap(ScoreDescription.predicateCheckField)
            }
            if !parts.isEmpty {
                body += "target: \(parts.joined(separator: ", "))\n"
            }
        }
        body += "error: \(failedStep.outcome.failureMessage ?? "unknown")"
        return body
    }
}

/// Escape special XML characters in text content and attribute values.
private func xmlEscape(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

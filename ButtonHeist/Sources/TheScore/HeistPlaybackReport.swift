import Foundation

// MARK: - Heist Playback Report

/// Per-step results from playing back a `.heist` file. Built by the playback
/// engine and consumed by report formatters (JUnit XML, future formats).
public struct HeistPlaybackReport: Sendable, Equatable {
    /// Name derived from the input file (e.g. "navigation-flow" from "navigation-flow.heist").
    public let heistName: String
    /// Bundle identifier of the app the heist targets.
    public let app: String
    /// Total wall-clock time for the entire playback, in seconds.
    public let totalTimeSeconds: Double
    /// Per-step outcomes, in execution order.
    public let steps: [StepResult]

    public init(
        heistName: String,
        app: String,
        totalTimeSeconds: Double,
        steps: [StepResult]
    ) {
        self.heistName = heistName
        self.app = app
        self.totalTimeSeconds = totalTimeSeconds
        self.steps = steps
    }

    // MARK: - Derived Properties

    public var passedCount: Int { steps.count(where: { $0.passed }) }
    public var failedCount: Int { steps.count(where: { !$0.passed }) }
    public var allPassed: Bool { steps.allSatisfy(\.passed) }
}

// MARK: - Step Result

extension HeistPlaybackReport {
    /// The outcome of executing a single heist step.
    public struct StepResult: Sendable, Equatable {
        /// 0-based index of this step in the heist.
        public let index: Int
        /// TheFence command name (e.g. "activate", "swipe", "type_text").
        public let command: String
        /// Element matcher used to target the element, if any.
        public let target: ElementMatcher?
        /// Wall-clock time for this step, in seconds.
        public let timeSeconds: Double
        /// Pass or fail with diagnostic detail.
        public let outcome: Outcome

        public init(
            index: Int,
            command: String,
            target: ElementMatcher?,
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

        /// Human-readable name for this step (used as testcase name in JUnit).
        public var displayName: String {
            var name = "[\(index)] \(command)"
            if let target, let label = target.label {
                name += " label=\"\(label)\""
            } else if let target, let identifier = target.identifier {
                name += " identifier=\"\(identifier)\""
            }
            return name
        }
    }
}

// MARK: - Outcome

extension HeistPlaybackReport {
    /// Whether a step passed or failed, with failure diagnostics.
    public enum Outcome: Sendable, Equatable {
        case passed
        case failed(message: String, errorKind: String?)

        public var failureMessage: String? {
            if case .failed(let message, _) = self { return message }
            return nil
        }

        public var failureType: String? {
            if case .failed(_, let kind) = self { return kind }
            return nil
        }
    }
}

// MARK: - JUnit XML

extension HeistPlaybackReport {
    /// Generate a JUnit XML report string.
    ///
    /// The structure follows the JUnit XML schema consumed by CI systems
    /// (GitHub Actions, Jenkins, CircleCI, etc.):
    /// ```
    /// <testsuites> → <testsuite> → <testcase> [→ <failure>]
    /// ```
    /// Each heist step becomes a `<testcase>`. Failed steps include a
    /// `<failure>` element with the error message and type.
    public func junitXML() -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        let totalTests = steps.count
        let totalFailures = failedCount
        let totalTime = String(format: "%.3f", totalTimeSeconds)

        xml += "<testsuites name=\"heist-playback\" tests=\"\(totalTests)\""
        xml += " failures=\"\(totalFailures)\" time=\"\(totalTime)\">\n"

        xml += "  <testsuite name=\"\(xmlEscape(heistName))\""
        xml += " tests=\"\(totalTests)\" failures=\"\(totalFailures)\""
        xml += " time=\"\(totalTime)\">\n"

        for step in steps {
            let stepTime = String(format: "%.3f", step.timeSeconds)
            xml += "    <testcase name=\"\(xmlEscape(step.displayName))\""
            xml += " classname=\"\(xmlEscape(heistName))\""
            xml += " time=\"\(stepTime)\""

            switch step.outcome {
            case .passed:
                xml += "/>\n"
            case .failed(let message, let errorKind):
                xml += ">\n"
                let failureType = errorKind ?? "playbackFailure"
                xml += "      <failure message=\"\(xmlEscape(message))\""
                xml += " type=\"\(xmlEscape(failureType))\">"
                xml += xmlEscape(failureBody(step: step, message: message))
                xml += "</failure>\n"
                xml += "    </testcase>\n"
            }
        }

        xml += "  </testsuite>\n"
        xml += "</testsuites>\n"
        return xml
    }

    // MARK: - Private Helpers

    private func failureBody(step: StepResult, message: String) -> String {
        var body = "command: \(step.command)\n"
        if let target = step.target {
            var parts: [String] = []
            if let label = target.label { parts.append("label=\"\(label)\"") }
            if let identifier = target.identifier { parts.append("identifier=\"\(identifier)\"") }
            if let value = target.value { parts.append("value=\"\(value)\"") }
            if !parts.isEmpty {
                body += "target: \(parts.joined(separator: ", "))\n"
            }
        }
        body += "error: \(message)"
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

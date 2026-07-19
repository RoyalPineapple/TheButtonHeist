import ThePlans

extension FenceResponse {
    func compactHeistValidation(_ report: HeistValidation.Report) -> String {
        var lines = [validationSummary(report)]
        lines.append(contentsOf: report.plan.diagnostics.map(Self.compactBuildDiagnostic))
        lines.append(contentsOf: report.invocation.diagnostics.map(Self.compactBuildDiagnostic))
        lines.append(contentsOf: report.lint.findings.flatMap(Self.compactLintFinding))
        if report.canonicalPlan != nil {
            lines.append("canonical source in structuredContent")
        }
        return lines.joined(separator: "\n")
    }

    func formatHeistValidationHuman(_ report: HeistValidation.Report) -> String {
        var lines = [validationSummary(report).capitalizedFirst]
        lines.append(contentsOf: report.plan.diagnostics.map(Self.humanBuildDiagnostic))
        lines.append(contentsOf: report.invocation.diagnostics.map(Self.humanBuildDiagnostic))
        lines.append(contentsOf: report.lint.findings.flatMap(Self.humanLintFinding))
        if let canonicalPlan = report.canonicalPlan {
            lines.append("Canonical plan:\n\(canonicalPlan)")
        }
        return lines.joined(separator: "\n")
    }

    private func validationSummary(_ report: HeistValidation.Report) -> String {
        if !report.plan.isValid {
            return "heist validation: not admissible; plan invalid"
        }
        guard report.invocation.isValid else {
            return "heist validation: not admissible; plan valid; invocation invalid"
        }
        switch report.lint {
        case .notEvaluated(let mode):
            return "heist validation: admissible; lint \(mode.rawValue): not_evaluated"
        case .passed(let mode):
            return "heist validation: admissible; lint \(mode.rawValue): passed"
        case .findings(let mode, let findings):
            let errors = findings.filter { $0.severity == .error }.count
            let warnings = findings.filter { $0.severity == .warning }.count
            return "heist validation: admissible; lint \(mode.rawValue): \(errors) error(s), \(warnings) warning(s)"
        }
    }

    private static func compactBuildDiagnostic(_ diagnostic: HeistBuildDiagnostic) -> String {
        var lines = [
            "diagnostic[\(diagnostic.code.rawValue) \(diagnostic.phase.rawValue) \(diagnostic.kind.rawValue)]: \(diagnostic.message)",
        ]
        if let hint = diagnostic.hint {
            lines.append("hint: \(hint)")
        }
        return lines.joined(separator: "\n")
    }

    private static func humanBuildDiagnostic(_ diagnostic: HeistBuildDiagnostic) -> String {
        var text = "Diagnostic [\(diagnostic.code.rawValue)]: \(diagnostic.message)"
        if let hint = diagnostic.hint {
            text += "\nHint: \(hint)"
        }
        return text
    }

    private static func compactLintFinding(_ finding: HeistPlanLintFinding) -> [String] {
        var lines = ["lint[\(finding.severity.rawValue) \(finding.path)]: \(finding.message)"]
        if let suggestion = finding.suggestion {
            lines.append("suggestion: \(suggestion)")
        }
        return lines
    }

    private static func humanLintFinding(_ finding: HeistPlanLintFinding) -> [String] {
        var lines = ["Lint [\(finding.severity.rawValue) \(finding.path)]: \(finding.message)"]
        if let suggestion = finding.suggestion {
            lines.append("Suggestion: \(suggestion)")
        }
        return lines
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

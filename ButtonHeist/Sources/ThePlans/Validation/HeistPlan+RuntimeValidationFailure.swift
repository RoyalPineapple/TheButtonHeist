import Foundation

package struct HeistPlanRuntimeSafetyFailure: Sendable, Equatable, CustomStringConvertible {
    package let path: String
    package let contract: String
    package let observed: String
    package let correction: String

    package init(
        path: String,
        contract: String,
        observed: String,
        correction: String
    ) {
        self.path = path
        self.contract = contract
        self.observed = observed
        self.correction = correction
    }

    package var description: String {
        "\(path): \(contract); observed \(observed); \(correction)"
    }
}

package struct HeistPlanRuntimeSafetyError: Error, Sendable, Equatable, CustomStringConvertible {
    package let failures: [HeistPlanRuntimeSafetyFailure]

    package init(failures: [HeistPlanRuntimeSafetyFailure]) {
        self.failures = failures
    }

    package var description: String {
        guard let first = failures.first else { return "heist plan runtime safety validation failed" }
        let suffix = failures.count > 1 ? " (+\(failures.count - 1) more)" : ""
        return "heist plan runtime safety validation failed: \(first)\(suffix)"
    }
}

extension HeistPlanRuntimeSafetyValidator {
    private static let durableHeistActionCorrection =
        "Use a direct client command for viewport/debug/session actions, or replace " +
        "this with a canonical durable DSL action."

    mutating func fail(
        path: String,
        contract: String,
        observed: String,
        correction: String
    ) {
        failures.append(HeistPlanRuntimeSafetyFailure(
            path: path,
            contract: contract,
            observed: observed,
            correction: correction
        ))
    }

    mutating func failNonDurableAction(
        at path: HeistTraversalPath,
        observed: String
    ) {
        fail(
            path: path.description,
            contract: "durable heist action",
            observed: observed,
            correction: Self.durableHeistActionCorrection
        )
    }

    func summarize(_ error: Error) -> String {
        let text = String(describing: error)
        guard text.count > 220 else { return text }
        return "\(text.prefix(217))..."
    }

    func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\0", with: "\\0")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

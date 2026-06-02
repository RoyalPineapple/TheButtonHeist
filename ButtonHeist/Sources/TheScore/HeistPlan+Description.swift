import Foundation

extension HeistPlan: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("heistPlan", [
            ScoreDescription.valueField("version", version),
            "steps=\(steps.count)",
        ].compactMap { $0 })
    }
}

extension HeistStep: CustomStringConvertible {
    public var description: String {
        switch self {
        case .action(let step): return step.description
        case .wait(let step): return step.description
        case .conditional(let step): return step.description
        case .waitForCases(let step): return step.description
        case .forEach(let step): return step.description
        case .warn(let step): return step.description
        case .fail(let step): return step.description
        }
    }
}

extension ActionStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("action", [
            "command=\(command.wireType.rawValue)",
            expectation.map { "expect=\($0)" },
        ].compactMap { $0 })
    }
}

extension WaitStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("wait", [
            predicate.description,
            "timeout=\(ScoreDescription.decimal(timeout))",
        ])
    }
}

extension ConditionalStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("if", [
            "cases=\(cases.count)",
            elseSteps.map { "else=\($0.count)" },
        ].compactMap { $0 })
    }
}

extension WaitForCasesStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("waitForCases", [
            "timeout=\(ScoreDescription.decimal(timeout))",
            "cases=\(cases.count)",
            elseSteps.map { "else=\($0.count)" },
        ].compactMap { $0 })
    }
}

extension PredicateCase: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("case", [
            predicate.description,
            "steps=\(steps.count)",
        ])
    }
}

extension ForEachStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("forEach", [
            matching.description,
            "limit=\(limit)",
            "steps=\(steps.count)",
        ])
    }
}

extension WarnStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("warn", [ScoreDescription.quoted(message)])
    }
}

extension FailStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("fail", [ScoreDescription.quoted(message)])
    }
}

import Foundation

extension HeistPlan: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("heistPlan", [
            ScoreDescription.valueField("version", version),
            "body=\(body.count)",
        ].compactMap { $0 })
    }
}

extension HeistStep: CustomStringConvertible {
    public var description: String {
        switch self {
        case .action(let step): return step.description
        case .wait(let step): return step.description
        case .conditional(let step): return step.description
        case .forEachElement(let step): return step.description
        case .forEachString(let step): return step.description
        case .repeatUntil(let step): return step.description
        case .warn(let step): return step.description
        case .fail(let step): return step.description
        case .heist(let plan): return plan.description
        case .invoke(let step): return step.description
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
            elseBody.map { "else=\($0.count)" },
        ].compactMap { $0 })
    }
}

extension ConditionalStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("if", [
            "cases=\(cases.count)",
            elseBody.map { "else=\($0.count)" },
        ].compactMap { $0 })
    }
}

extension PredicateCase: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("case", [
            predicate.description,
            "body=\(body.count)",
        ])
    }
}

extension ForEachElementStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("forEachElement", [
            matching.description,
            "limit=\(limit)",
            "parameter=\(parameter)",
            "body=\(body.count)",
        ])
    }
}

extension ForEachStringStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("forEachString", [
            "values=\(values.count)",
            "parameter=\(parameter)",
            "body=\(body.count)",
        ])
    }
}

extension RepeatUntilStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("repeatUntil", [
            predicate.description,
            "timeout=\(ScoreDescription.decimal(timeout))",
            "body=\(body.count)",
            elseBody.map { "else=\($0.count)" },
        ].compactMap { $0 })
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

extension HeistInvocationStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("invoke", [
            "path=\(path.joined(separator: "."))",
            "argument=\(argument.kind.rawValue)",
        ])
    }
}

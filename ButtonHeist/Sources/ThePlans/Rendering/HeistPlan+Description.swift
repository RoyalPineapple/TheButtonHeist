import Foundation

extension HeistPlan: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("heistPlan", [
            CanonicalValueDescription.valueField("version", version),
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
        CanonicalValueDescription.call("action", [
            "command=\(command.wireType.rawValue)",
            expectationPolicy.expectedStep.map { "expect=\($0)" },
            expectationPolicy.waiver.map { "withoutExpectation=\($0.reason)" },
        ].compactMap { $0 })
    }
}

extension WaitStep: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("wait", [
            predicate.description,
            "timeout=\(CanonicalValueDescription.decimal(timeout.seconds))",
            elseBody.map { "else=\($0.count)" },
        ].compactMap { $0 })
    }
}

extension ConditionalStep: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("if", [
            "cases=\(cases.count)",
            elseBody.map { "else=\($0.count)" },
        ].compactMap { $0 })
    }
}

extension PredicateCase: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("case", [
            predicate.description,
            "body=\(body.count)",
        ])
    }
}

extension ForEachElementStep: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("forEachElement", [
            matching.description,
            "limit=\(limit)",
            "parameter=\(parameter)",
            "body=\(body.count)",
        ])
    }
}

extension ForEachStringStep: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("forEachString", [
            "values=\(values.count)",
            "parameter=\(parameter)",
            "body=\(body.count)",
        ])
    }
}

extension RepeatUntilStep: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("repeatUntil", [
            predicate.description,
            "timeout=\(CanonicalValueDescription.decimal(timeout.seconds))",
            "body=\(body.count)",
            elseBody.map { "else=\($0.count)" },
        ].compactMap { $0 })
    }
}

extension WarnStep: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("warn", [CanonicalValueDescription.quoted(message.rawValue)])
    }
}

extension FailStep: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("fail", [CanonicalValueDescription.quoted(message.rawValue)])
    }
}

extension HeistInvocationStep: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("invoke", [
            "path=\(path.description)",
            "argument=\(argument.kind.rawValue)",
        ])
    }
}

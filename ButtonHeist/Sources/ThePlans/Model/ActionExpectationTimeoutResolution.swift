extension HeistPlan {
    package func resolvingActionExpectationTimeouts(
        using policy: ActionExpectationTimeoutPolicy
    ) throws -> Self {
        try HeistPlan(
            version: version,
            name: name,
            parameter: parameter,
            definitions: definitions.map {
                try $0.resolvingActionExpectationTimeouts(using: policy)
            },
            body: body.map {
                try $0.resolvingActionExpectationTimeouts(using: policy)
            }
        )
    }
}

private extension HeistStep {
    func resolvingActionExpectationTimeouts(
        using policy: ActionExpectationTimeoutPolicy
    ) throws -> Self {
        switch self {
        case .action(let step):
            return .action(ActionStep(
                command: step.command,
                expectationPolicy: step.expectationPolicy.resolvingTimeout(using: policy)
            ))
        case .wait(let step):
            return .wait(WaitStep(
                predicate: step.predicate,
                timeout: step.timeout,
                elseBody: try step.elseBody?.map {
                    try $0.resolvingActionExpectationTimeouts(using: policy)
                }
            ))
        case .conditional(let step):
            return .conditional(try ConditionalStep(
                cases: step.cases.map {
                    PredicateCase(
                        predicate: $0.predicate,
                        body: try $0.body.map {
                            try $0.resolvingActionExpectationTimeouts(using: policy)
                        }
                    )
                },
                elseBody: try step.elseBody?.map {
                    try $0.resolvingActionExpectationTimeouts(using: policy)
                }
            ))
        case .forEachElement(let step):
            return .forEachElement(try ForEachElementStep(
                matching: step.matching,
                limit: step.limit,
                parameter: step.parameter,
                body: step.body.map {
                    try $0.resolvingActionExpectationTimeouts(using: policy)
                }
            ))
        case .forEachString(let step):
            return .forEachString(try ForEachStringStep(
                values: step.values,
                parameter: step.parameter,
                body: step.body.map {
                    try $0.resolvingActionExpectationTimeouts(using: policy)
                }
            ))
        case .repeatUntil(let step):
            return .repeatUntil(try RepeatUntilStep(
                predicate: step.predicate,
                timeout: step.timeout,
                body: step.body.map {
                    try $0.resolvingActionExpectationTimeouts(using: policy)
                }
            ))
        case .warn, .fail:
            return self
        case .heist(let plan):
            return .heist(try plan.resolvingActionExpectationTimeouts(using: policy))
        case .invoke(let step):
            return .invoke(HeistInvocationStep(
                path: step.path,
                argument: step.argument,
                expectation: step.expectation?.resolvingTimeout(using: policy)
            ))
        }
    }
}

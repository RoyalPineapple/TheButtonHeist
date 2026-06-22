import Foundation

// RuntimeSafety owns the bounded executable-plan boundary: finite traversal,
// non-recursive local heist references, scoped refs, safe control flow, and
// payloads that lower to runtime command contracts.
struct HeistPlanRuntimeSafetyValidator: HeistPlanTraversalVisitor {
    let limits: HeistPlanRuntimeSafetyLimits

    var failures: [HeistPlanRuntimeSafetyFailure] = []
    var stepCount = 0
    var definitionCount = 0
    var totalStringBytes = 0
    var reportedStepLimit = false
    var reportedDefinitionLimit = false
    var reportedTotalStringLimit = false

    init(limits: HeistPlanRuntimeSafetyLimits) {
        self.limits = limits
    }

    mutating func validate(_ raw: HeistPlanAdmissionCandidate) throws -> HeistPlan {
        let plan = raw.uncheckedPlanForRuntimeSafetyValidation()
        let failures = failures(in: plan)
        guard failures.isEmpty else { throw HeistPlanRuntimeSafetyError(failures: failures) }
        return plan
    }

    mutating func failures(in plan: HeistPlan) -> [HeistPlanRuntimeSafetyFailure] {
        let traversal = HeistPlanTraversal()
        traversal.walk(plan, visitor: &self)
        return failures
    }

    mutating func visitPlan(_ plan: HeistPlan, context: HeistTraversalContext) {
        validatePlanHeader(plan, path: context.path, requiresName: false)
    }

    mutating func visitDefinitions(_ definitions: [HeistPlan], context: HeistTraversalContext) {
        validateDefinitions(definitions, path: context.path)
    }

    mutating func visitDefinition(_ plan: HeistPlan, context: HeistTraversalContext) {
        validatePlanHeader(plan, path: context.path, requiresName: true)
    }

    mutating func visitStep(
        _ step: HeistStep,
        context: HeistTraversalContext
    ) {
        stepCount += 1
        if stepCount > limits.maxTotalSteps, !reportedStepLimit {
            reportedStepLimit = true
            fail(
                path: context.path,
                contract: "max total heist steps",
                observed: "\(stepCount) steps",
                correction: "Use \(limits.maxTotalSteps) steps or fewer."
            )
        }
        if context.depth > limits.maxNestedStepDepth {
            fail(
                path: context.path,
                contract: "max nested step depth",
                observed: "depth \(context.depth)",
                correction: "Flatten this heist to depth \(limits.maxNestedStepDepth) or less."
            )
        }
    }

    mutating func visitAction(_ action: ActionStep, context: HeistTraversalContext) {
        validateAction(
            action,
            path: context.path,
            scope: context.scope,
            environment: context.environment
        )
    }

    mutating func visitWait(_ wait: WaitStep, context: HeistTraversalContext) {
        validateWait(wait, path: context.path, scope: context.scope, environment: context.environment)
    }

    mutating func visitPredicateCase(_ predicateCase: PredicateCase, context: HeistTraversalContext) {
        validatePredicateCase(
            predicateCase,
            path: context.path,
            scope: context.scope,
            environment: context.environment
        )
    }

    mutating func visitForEachElement(_ step: ForEachElementStep, context: HeistTraversalContext) {
        validateForEachElement(step, path: context.path, allowsCollectionLoops: context.allowsCollectionLoops)
    }

    mutating func visitForEachString(_ step: ForEachStringStep, context: HeistTraversalContext) {
        validateForEachString(
            step,
            path: context.path,
            bodyDepth: context.depth + 1,
            scope: context.scope,
            environment: context.environment,
            definitionScope: context.definitionScope,
            allowsCollectionLoops: context.allowsCollectionLoops
        )
    }

    mutating func visitWarn(_ warn: WarnStep, context: HeistTraversalContext) {
        addString(warn.message, path: "\(context.path).message", role: "warn message")
    }

    mutating func visitFail(_ fail: FailStep, context: HeistTraversalContext) {
        addString(fail.message, path: "\(context.path).message", role: "fail message")
    }

    mutating func visitHeist(_ plan: HeistPlan, context: HeistTraversalContext) {
        validatePlanHeader(plan, path: context.path, requiresName: false)
        if plan.parameter != .none {
            fail(
                path: "\(context.path).parameter",
                contract: "inline heist group must not declare a parameter",
                observed: plan.parameter.kind.rawValue,
                correction: "Use RunHeist with a named capability when a heist needs an argument."
            )
        }
    }

    mutating func visitInvoke(_ step: HeistInvocationStep, context: HeistTraversalContext) {
        validateInvocation(step, context: context)
    }

    mutating func validatePlanHeader(
        _ plan: HeistPlan,
        path: String,
        requiresName: Bool
    ) {
        if requiresName {
            guard let name = plan.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail(
                    path: "\(path).name",
                    contract: "heist definitions must have a non-empty name",
                    observed: "missing name",
                    correction: "Name every heist in a definitions array."
                )
                return
            }
        }
        if let name = plan.name {
            validateParameter(name, path: "\(path).name", role: "heist definition name")
        }
        validateParameterDeclaration(plan.parameter, path: "\(path).parameter")
        if plan.body.isEmpty, plan.definitions.isEmpty {
            fail(
                path: "\(path).body",
                contract: "heist plan must contain a body or nested definitions",
                observed: "empty heist",
                correction: "Add body steps, or use this plan only as a namespace with nested definitions."
            )
        }
    }

    mutating func validateDefinitions(_ definitions: [HeistPlan], path: String) {
        definitionCount += definitions.count
        if definitionCount > limits.maxDefinitions, !reportedDefinitionLimit {
            reportedDefinitionLimit = true
            fail(
                path: path,
                contract: "max total heist definitions",
                observed: "\(definitionCount) definitions",
                correction: "Use \(limits.maxDefinitions) definitions or fewer."
            )
        }

        var seen: Set<String> = []
        for (index, definition) in definitions.enumerated() {
            guard let name = definition.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            if seen.contains(name) {
                fail(
                    path: "\(path)[\(index)].name",
                    contract: "duplicate heist definition names are not allowed in the same scope",
                    observed: "\"\(escaped(name))\"",
                    correction: "Rename one definition or put it in a different namespace."
                )
            }
            seen.insert(name)
        }
    }

    mutating func validateParameterDeclaration(_ parameter: HeistParameter, path: String) {
        guard let name = parameter.name else { return }
        validateParameter(name, path: "\(path).name", role: "\(parameter.kind.rawValue) parameter")
    }

    mutating func validateInvocation(_ step: HeistInvocationStep, context: HeistTraversalContext) {
        guard !step.path.isEmpty else {
            fail(
                path: "\(context.path).path",
                contract: "heist run path must not be empty",
                observed: "empty path",
                correction: "Run a named local capability."
            )
            return
        }
        for (index, component) in step.path.enumerated() {
            validateParameter(component, path: "\(context.path).path[\(index)]", role: "heist run path component")
        }
        validateArgument(step.argument, path: "\(context.path).argument", scope: context.scope)
        guard let resolved = context.definitionScope.resolve(path: step.path) else {
            fail(
                path: "\(context.path).path",
                contract: "heist run path must resolve to a local capability",
                observed: step.path.joined(separator: "."),
                correction: "Define this heist in the current scope or qualify it through an exported namespace."
            )
            return
        }
        let resolvedName = resolved.qualifiedName
        if context.invocationStack.contains(resolvedName) {
            fail(
                path: "\(context.path).path",
                contract: "heist runs must not be recursive",
                observed: (context.invocationStack + [resolvedName]).joined(separator: " -> "),
                correction: "Remove the recursive heist run cycle."
            )
            return
        }
        guard step.argument.kind == resolved.definition.parameter.kind else {
            fail(
                path: "\(context.path).argument",
                contract: "heist run argument type must match the target parameter",
                observed: "\(step.argument.kind.rawValue) for \(resolved.definition.parameter.kind.rawValue)",
                correction: "Pass the argument shape declared by the named capability."
            )
            return
        }
        do {
            _ = try context.environment.binding(argument: step.argument, to: resolved.definition.parameter)
        } catch {
            fail(
                path: "\(context.path).argument",
                contract: "heist run argument must bind to the target parameter",
                observed: summarize(error),
                correction: "Use a finite semantic value matching the named capability parameter."
            )
        }
    }

    mutating func validateArgument(_ argument: HeistArgument, path: String, scope: HeistReferenceScope) {
        switch argument {
        case .none:
            break
        case .string(let value):
            validateString(value, path: "\(path).value", scope: scope)
        case .elementTarget(let target):
            validateTarget(target, path: "\(path).target", scope: scope)
        }
    }

    mutating func validateAction(
        _ action: ActionStep,
        path: String,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validateCommand(action.command, path: "\(path).command", scope: scope, environment: environment)
        if let waiver = action.expectationWaiver {
            addString(waiver, path: "\(path).without_expectation", role: "expectation waiver")
        }
        if let failure = action.expectationValidationFailure {
            fail(
                path: "\(path).expectation",
                contract: "action expectation composition must be supported and unambiguous",
                observed: failure,
                correction: "Use one change predicate plus optional state predicates, or split unrelated waits into explicit WaitFor steps."
            )
        }
    }

    mutating func validateCommand(
        _ command: HeistActionCommand,
        path: String,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validateCommandExpressions(command, path: path, scope: scope)
        // Durability (serialize/render canonically) is an authoring concern, not
        // an execution one. It is enforced where heists are persisted or rendered
        // as canonical Swift DSL, not here, so a transient plan can execute any
        // valid command, including viewport commands.
        do {
            try command.assertResolvedPayloadAdmissible(in: environment)
        } catch {
            fail(
                path: path,
                contract: "resolved command payload must satisfy the heist action payload contract",
                observed: summarize(error),
                correction: "Use values and refs that lower to a valid \(command.wireType.rawValue) command payload."
            )
        }
    }

    mutating func validateWait(
        _ wait: WaitStep,
        path: String,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validatePredicate(wait.predicate, path: "\(path).predicate", depth: 1, scope: scope)
        guard wait.timeout >= 0 else {
            fail(
                path: "\(path).timeout",
                contract: "wait timeout must be non-negative",
                observed: "\(wait.timeout)",
                correction: "Use a timeout of 0 or more seconds."
            )
            return
        }
        do {
            let resolved = try wait.resolve(in: environment)
            try HeistRuntimePayloadContractValidator.validate(WaitTarget(
                predicate: resolved.predicate,
                timeout: resolved.timeout
            ))
        } catch {
            fail(
                path: path,
                contract: "resolved wait predicate must satisfy the heist wait payload contract",
                observed: summarize(error),
                correction: "Use scoped refs and predicate values that lower to a valid wait command."
            )
        }
    }

    mutating func validatePredicateCase(
        _ predicateCase: PredicateCase,
        path: String,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validatePredicate(predicateCase.predicate, path: "\(path).predicate", depth: 1, scope: scope)
        do {
            _ = try predicateCase.predicate.resolve(in: environment)
        } catch {
            fail(
                path: "\(path).predicate",
                contract: "predicate refs must resolve in the current heist scope",
                observed: summarize(error),
                correction: "Use target_ref or string refs only inside the loop body that defines them."
            )
        }
    }

    mutating func validateForEachElement(
        _ step: ForEachElementStep,
        path: String,
        allowsCollectionLoops: Bool
    ) {
        guard allowsCollectionLoops else {
            fail(
                path: path,
                contract: "collection ForEach steps are top-level only",
                observed: "nested for_each_element",
                correction: "Move this collection loop to the top-level heist steps."
            )
            return
        }
        validateElementPredicate(step.matching, path: "\(path).matching")
        validateParameter(step.parameter, path: "\(path).parameter", role: "for_each_element parameter")
        if step.limit > limits.maxForEachElementLimit {
            fail(
                path: "\(path).limit",
                contract: "max for_each_element limit",
                observed: "\(step.limit)",
                correction: "Use a limit of \(limits.maxForEachElementLimit) or less."
            )
        }
    }

    mutating func validateForEachString(
        _ step: ForEachStringStep,
        path: String,
        bodyDepth: Int,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment,
        definitionScope: HeistDefinitionScope,
        allowsCollectionLoops: Bool
    ) {
        guard allowsCollectionLoops else {
            fail(
                path: path,
                contract: "collection ForEach steps are top-level only",
                observed: "nested for_each_string",
                correction: "Move this collection loop to the top-level heist steps."
            )
            return
        }
        validateParameter(step.parameter, path: "\(path).parameter", role: "for_each_string parameter")
        if step.values.count > limits.maxForEachStringValues {
            fail(
                path: "\(path).values",
                contract: "max for_each_string values",
                observed: "\(step.values.count) values",
                correction: "Use \(limits.maxForEachStringValues) values or fewer."
            )
        }
        for (index, value) in step.values.enumerated() {
            addString(value, path: "\(path).values[\(index)]", role: "for_each_string value")
        }

        for (index, value) in step.values.enumerated() {
            validateResolvedStringLoopPayloads(
                step.body,
                path: "\(path).body",
                depth: bodyDepth,
                scope: scope.bindingString(step.parameter),
                environment: environment.binding(string: value, to: step.parameter),
                definitionScope: definitionScope,
                valuePath: "\(path).values[\(index)]"
            )
        }
    }

    mutating func validateResolvedStringLoopPayloads(
        _ steps: [HeistStep],
        path: String,
        depth: Int,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment,
        definitionScope: HeistDefinitionScope,
        valuePath: String
    ) {
        var validator = StringLoopResolvedPayloadValidator(valuePath: valuePath)
        let traversal = HeistPlanTraversal()
        traversal.walk(
            steps: steps,
            path: path,
            depth: depth,
            allowsCollectionLoops: false,
            scope: scope,
            environment: environment,
            definitionScope: definitionScope,
            visitor: &validator
        )
        failures += validator.failures
    }
}

import Foundation

struct ResolvedStringLoopPayloadValidationContext {
    let path: HeistTraversalPath
    let depth: Int
    let scope: HeistReferenceScope
    let environment: HeistExecutionEnvironment
    let definitionScope: HeistDefinitionScope
    let rootDefinitionScope: HeistDefinitionScope
    let callGraph: HeistCallGraph?
    let valuePath: String
}

/// RuntimeSafety owns the bounded executable-plan boundary.
///
/// Totality rests on three bounds: (a) acyclic call graph
/// [HeistCallGraph] - structural; (b) bounded ForEach; (c) timeout-floored
/// RepeatUntil/WaitFor - runtime floors.
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
                path: context.path.description,
                contract: "max total heist steps",
                observed: "\(stepCount) steps",
                correction: "Use \(limits.maxTotalSteps) steps or fewer."
            )
        }
        if context.depth > limits.maxNestedStepDepth {
            fail(
                path: context.path.description,
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
        validateForEachElement(step, path: context.path)
    }

    mutating func visitForEachString(_ step: ForEachStringStep, context: HeistTraversalContext) {
        validateForEachString(
            step,
            path: context.path,
            bodyDepth: context.depth + 1,
            scope: context.scope,
            environment: context.environment,
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            callGraph: context.callGraph
        )
    }

    mutating func visitRepeatUntil(_ step: RepeatUntilStep, context: HeistTraversalContext) {
        validateRepeatUntil(step, path: context.path)
    }

    mutating func visitWarn(_ warn: WarnStep, context: HeistTraversalContext) {
        addString(warn.message, path: context.path.child(.message).description, role: "warn message")
    }

    mutating func visitFail(_ fail: FailStep, context: HeistTraversalContext) {
        addString(fail.message, path: context.path.child(.message).description, role: "fail message")
    }

    mutating func visitHeist(_ plan: HeistPlan, context: HeistTraversalContext) {
        validatePlanHeader(plan, path: context.path, requiresName: false)
        if plan.parameter != .none {
            fail(
                path: context.path.child(.parameter).description,
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
        path: HeistTraversalPath,
        requiresName: Bool
    ) {
        if requiresName {
            guard let name = plan.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail(
                    path: path.child(.name).description,
                    contract: "heist definitions must have a non-empty name",
                    observed: "missing name",
                    correction: "Name every heist in a definitions array."
                )
                return
            }
        }
        if let name = plan.name {
            validateParameter(name, path: path.child(.name).description, role: "heist definition name")
        }
        validateParameterDeclaration(plan.parameter, path: path.child(.parameter))
        if plan.body.isEmpty, plan.definitions.isEmpty {
            fail(
                path: path.child(.body).description,
                contract: "heist plan must contain a body or nested definitions",
                observed: "empty heist",
                correction: "Add body steps, or use this plan only as a namespace with nested definitions."
            )
        }
    }

    mutating func validateDefinitions(_ definitions: [HeistPlan], path: HeistTraversalPath) {
        definitionCount += definitions.count
        if definitionCount > limits.maxDefinitions, !reportedDefinitionLimit {
            reportedDefinitionLimit = true
            fail(
                path: path.description,
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
                    path: path.index(index).child(.name).description,
                    contract: "duplicate heist definition names are not allowed in the same scope",
                    observed: "\"\(escaped(name))\"",
                    correction: "Rename one definition or put it in a different namespace."
                )
            }
            seen.insert(name)
        }
    }

    mutating func validateParameterDeclaration(_ parameter: HeistParameter, path: HeistTraversalPath) {
        guard let name = parameter.name else { return }
        validateParameter(name, path: path.child(.name).description, role: "\(parameter.kind.rawValue) parameter")
    }

    mutating func validateInvocation(_ step: HeistInvocationStep, context: HeistTraversalContext) {
        let invocationPath = step.invocationPath
        for (index, component) in invocationPath.components.enumerated() {
            validateParameter(
                component,
                path: context.path.child(.path).index(index).description,
                role: "heist run path component"
            )
        }
        validateArgument(step.argument, path: context.path.child(.argument), scope: context.scope)
        guard let resolved = context.resolveInvocation(path: invocationPath) else {
            if invocationPath.components.count > 1 {
                fail(
                    path: context.path.child(.path).description,
                    contract: "heist run path must resolve to a declared exported capability",
                    observed: invocationPath.dottedName,
                    correction: "No export named '\(invocationPath.dottedName)' in this plan; declare it in a Namespace block or use a local nested capability."
                )
                return
            }
            fail(
                path: context.path.child(.path).description,
                contract: "heist run path must resolve to a local capability",
                observed: invocationPath.dottedName,
                correction: "Define this heist in the current scope or qualify it through an exported namespace."
            )
            return
        }
        let resolvedName = resolved.qualifiedName
        if let cycle = context.callGraphCycle(closing: resolvedName) {
            fail(
                path: context.path.child(.path).description,
                contract: "heist runs must not be recursive",
                observed: cycle.displayPath,
                correction: "Remove the recursive heist run cycle."
            )
            return
        }
        guard step.argument.kind == resolved.definition.parameter.kind else {
            fail(
                path: context.path.child(.argument).description,
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
                path: context.path.child(.argument).description,
                contract: "heist run argument must bind to the target parameter",
                observed: summarize(error),
                correction: "Use a finite semantic value matching the named capability parameter."
            )
        }
    }

    mutating func validateArgument(_ argument: HeistArgument, path: HeistTraversalPath, scope: HeistReferenceScope) {
        switch argument {
        case .none:
            break
        case .string(let value):
            validateString(value, path: path.child(.value).description, scope: scope)
        case .elementTarget(let target):
            validateTarget(target, path: path.child(.target).description, scope: scope)
        }
    }

    mutating func validateAction(
        _ action: ActionStep,
        path: HeistTraversalPath,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validateCommand(action.command, path: path.child(.command), scope: scope, environment: environment)
        if let waiver = action.expectationWaiver {
            addString(waiver, path: path.child(.withoutExpectation).description, role: "expectation waiver")
        }
        for diagnostic in action.expectationValidationDiagnostics {
            fail(
                path: path.child(.expectation).description,
                contract: "action expectation composition must be supported and unambiguous",
                observed: diagnostic.message,
                correction: diagnostic.hint ?? "Use one change predicate plus optional state predicates, or split unrelated waits into explicit WaitFor steps."
            )
        }
    }

    mutating func validateCommand(
        _ command: HeistActionCommand,
        path: HeistTraversalPath,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validateCommandExpressions(command, path: path.description, scope: scope)
        if let failure = command.durableHeistActionFailure {
            failNonDurableAction(at: path, observed: failure)
        }
        do {
            try command.assertResolvedPayloadAdmissible(in: environment)
        } catch {
            fail(
                path: path.description,
                contract: "resolved command payload must satisfy the heist action payload contract",
                observed: summarize(error),
                correction: "Use values and refs that lower to a valid \(command.wireType.rawValue) command payload."
            )
        }
    }

    mutating func validateWait(
        _ wait: WaitStep,
        path: HeistTraversalPath,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validatePredicate(wait.predicate, path: path.child(.predicate).description, depth: 1, scope: scope)
        guard wait.timeout >= 0 else {
            fail(
                path: path.child(.timeout).description,
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
                path: path.description,
                contract: "resolved wait predicate must satisfy the heist wait payload contract",
                observed: summarize(error),
                correction: "Use scoped refs and predicate values that lower to a valid wait command."
            )
        }
    }

    mutating func validatePredicateCase(
        _ predicateCase: PredicateCase,
        path: HeistTraversalPath,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validatePredicate(predicateCase.predicate, path: path.child(.predicate).description, depth: 1, scope: scope)
        do {
            _ = try predicateCase.predicate.resolve(in: environment)
        } catch {
            fail(
                path: path.child(.predicate).description,
                contract: "predicate refs must resolve in the current heist scope",
                observed: summarize(error),
                correction: "Use target_ref or string refs only inside the loop body that defines them."
            )
        }
    }

    mutating func validateForEachElement(
        _ step: ForEachElementStep,
        path: HeistTraversalPath
    ) {
        validateElementPredicate(step.matching, path: path.child(.matching).description)
        validateParameter(step.parameter, path: path.child(.parameter).description, role: "for_each_element parameter")
        if step.limit > limits.maxForEachElementLimit {
            fail(
                path: path.child(.limit).description,
                contract: "max for_each_element limit",
                observed: "\(step.limit)",
                correction: "Use a limit of \(limits.maxForEachElementLimit) or less."
            )
        }
    }

    mutating func validateForEachString(
        _ step: ForEachStringStep,
        path: HeistTraversalPath,
        bodyDepth: Int,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment,
        definitionScope: HeistDefinitionScope,
        rootDefinitionScope: HeistDefinitionScope,
        callGraph: HeistCallGraph?
    ) {
        validateParameter(step.parameter, path: path.child(.parameter).description, role: "for_each_string parameter")
        if step.values.count > limits.maxForEachStringValues {
            fail(
                path: path.child(.values).description,
                contract: "max for_each_string values",
                observed: "\(step.values.count) values",
                correction: "Use \(limits.maxForEachStringValues) values or fewer."
            )
        }
        for (index, value) in step.values.enumerated() {
            addString(value, path: path.child(.values).index(index).description, role: "for_each_string value")
        }

        for (index, value) in step.values.enumerated() {
            validateResolvedStringLoopPayloads(
                step.body,
                context: ResolvedStringLoopPayloadValidationContext(
                    path: path.child(.body),
                    depth: bodyDepth,
                    scope: scope.bindingString(step.parameter),
                    environment: environment.binding(string: value, to: step.parameter),
                    definitionScope: definitionScope,
                    rootDefinitionScope: rootDefinitionScope,
                    callGraph: callGraph,
                    valuePath: path.child(.values).index(index).description
                )
            )
        }
    }

    mutating func validateRepeatUntil(_ step: RepeatUntilStep, path: HeistTraversalPath) {
        guard step.timeout >= 0 else {
            fail(
                path: path.child(.timeout).description,
                contract: "repeat_until timeout must be non-negative",
                observed: "\(step.timeout)",
                correction: "Use a timeout of 0 or more seconds."
            )
            return
        }
        guard !step.body.isEmpty else {
            fail(
                path: path.child(.body).description,
                contract: "repeat_until body must not be empty",
                observed: "empty body",
                correction: "Add at least one action to repeat, or use WaitFor for passive waiting."
            )
            return
        }
    }

    mutating func validateResolvedStringLoopPayloads(
        _ steps: [HeistStep],
        context: ResolvedStringLoopPayloadValidationContext
    ) {
        var validator = StringLoopResolvedPayloadValidator(valuePath: context.valuePath)
        let traversal = HeistPlanTraversal()
        traversal.walk(
            steps: steps,
            path: context.path,
            depth: context.depth,
            scope: context.scope,
            environment: context.environment,
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            callGraph: context.callGraph,
            visitor: &validator
        )
        failures += validator.failures
    }
}

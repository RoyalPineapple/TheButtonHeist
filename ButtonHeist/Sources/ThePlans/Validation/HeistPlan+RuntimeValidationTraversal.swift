import Foundation

/// RuntimeSafety owns the bounded executable-plan boundary.
///
/// Totality rests on three bounds: (a) acyclic call graph
/// [HeistCallGraph] - structural; (b) bounded ForEach; (c) timeout-floored
/// RepeatUntil/WaitFor - runtime floors.
struct HeistPlanRuntimeSafetyValidator: HeistPlanTraversalVisitor {
    private static let nestedCollectionLoopContract = "collection loops must not be nested"
    private static let nestedCollectionLoopCorrection =
        "Flatten this heist so ForEach bodies contain only non-collection steps."

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

    mutating func inspect(_ plan: HeistPlan) {
        HeistPlanTraversal().walk(plan, visitor: &self)
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

    mutating func visitStep(_ step: HeistStep, context: HeistTraversalContext) {
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
        validateResolvedStringLoopAction(action, context: context)
        validateAction(
            action,
            path: context.path,
            scope: context.scope,
            environment: context.environment
        )
    }

    mutating func visitWait(_ wait: WaitStep, context: HeistTraversalContext) {
        validateResolvedStringLoopWait(wait, context: context)
        validateWait(
            wait,
            path: context.path,
            scope: context.scope,
            environment: context.environment
        )
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
        validateCollectionLoopNesting(kind: "for_each_element", path: context.path)
        validateForEachElement(step, path: context.path, scope: context.scope)
    }

    mutating func visitForEachString(_ step: ForEachStringStep, context: HeistTraversalContext) {
        validateCollectionLoopNesting(kind: "for_each_string", path: context.path)
        validateForEachString(step, path: context.path)
    }

    mutating func visitRepeatUntil(_ step: RepeatUntilStep, context: HeistTraversalContext) {
        validateRepeatUntil(step, path: context.path)
    }

    mutating func visitWarn(_ warn: WarnStep, context: HeistTraversalContext) {
        addString(warn.message.rawValue, path: context.path.child(.message), role: "warn message")
    }

    mutating func visitFail(_ failStep: FailStep, context: HeistTraversalContext) {
        addString(failStep.message.rawValue, path: context.path.child(.message), role: "fail message")
    }

    mutating func visitHeist(_ plan: HeistPlan, context: HeistTraversalContext) {
        validatePlanHeader(plan, path: context.path, requiresName: false)
        if plan.parameter != .none {
            fail(
                path: context.path.child(.parameter),
                contract: "inline heist group must not declare a parameter",
                observed: plan.parameter.kind.rawValue,
                correction: "Use RunHeist with a named capability when a heist needs an argument."
            )
        }
    }

    mutating func visitInvoke(_ invocation: HeistInvocationStep, context: HeistTraversalContext) {
        validateInvocation(invocation, context: context)
    }

    mutating func validatePlanHeader(
        _ plan: HeistPlan,
        path: HeistPlanPath,
        requiresName: Bool
    ) {
        if requiresName {
            guard plan.name != nil else {
                fail(
                    path: path.child(.name),
                    contract: "heist definitions must have a non-empty name",
                    observed: "missing name",
                    correction: "Name every heist in a definitions array."
                )
                return
            }
        }
        if let name = plan.name {
            addParameterString(
                name.description,
                path: path.child(.name),
                role: "heist definition name"
            )
        }
        validateParameterDeclaration(plan.parameter, path: path.child(.parameter))
        if plan.body.isEmpty, plan.definitions.isEmpty {
            fail(
                path: path.child(.body),
                contract: "heist plan must contain a body or nested definitions",
                observed: "empty heist",
                correction: "Add body steps, or use this plan only as a namespace with nested definitions."
            )
        }
    }

    mutating func validateDefinitions(
        _ definitions: [HeistPlan],
        path: HeistPlanPath
    ) {
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

        var seen: Set<HeistPlanName> = []
        for (index, definition) in definitions.enumerated() {
            guard let name = definition.name else {
                continue
            }
            if seen.contains(name) {
                fail(
                    path: path.index(index).child(.name),
                    contract: "duplicate heist definition names are not allowed in the same scope",
                    observed: "\"\(escaped(name.description))\"",
                    correction: "Rename one definition or put it in a different namespace."
                )
            }
            seen.insert(name)
        }
    }

    mutating func validateParameterDeclaration(_ parameter: HeistParameter, path: HeistPlanPath) {
        guard let name = parameter.name else { return }
        addParameterString(name.rawValue, path: path.child(.name), role: "\(parameter.kind.rawValue) parameter")
    }

    private mutating func validateInvocation(
        _ step: HeistInvocationStep,
        context: HeistTraversalContext
    ) {
        let invocationPath = step.path
        for (index, component) in invocationPath.components.enumerated() {
            addParameterString(
                component.description,
                path: context.path.child(.path).index(index),
                role: "heist run path component"
            )
        }
        validateArgument(step.argument, path: context.path.child(.argument), scope: context.scope)
        guard let resolved = context.resolveInvocation(path: invocationPath) else {
            if invocationPath.components.count > 1 {
                fail(
                    path: context.path.child(.path),
                    contract: "heist run path must resolve to a declared exported capability",
                    observed: invocationPath.description,
                    correction: "No export named '\(invocationPath)' in this plan; declare it in a Namespace block or use a local nested capability."
                )
                return
            }
            fail(
                path: context.path.child(.path),
                contract: "heist run path must resolve to a local capability",
                observed: invocationPath.description,
                correction: "Define this heist in the current scope or qualify it through an exported namespace."
            )
            return
        }
        if let cycle = context.callGraphCycle(closing: resolved.callGraphNode) {
            fail(
                path: context.path.child(.path),
                contract: "heist runs must not be recursive",
                observed: cycle.displayPath,
                correction: "Remove the recursive heist run cycle."
            )
            return
        }
        guard step.argument.kind == resolved.definition.parameter.kind else {
            fail(
                path: context.path.child(.argument),
                contract: "heist run argument type must match the target parameter",
                observed: "\(step.argument.kind.rawValue) for \(resolved.definition.parameter.kind.rawValue)",
                correction: "Pass the argument shape declared by the named capability."
            )
            return
        }
        do {
            _ = try context.referenceBindings.binding(argument: step.argument, to: resolved.definition.parameter)
        } catch {
            fail(
                path: context.path.child(.argument),
                contract: "heist run argument must bind to the target parameter",
                observed: summarize(error),
                correction: "Use a finite semantic value matching the named capability parameter."
            )
        }
    }

    mutating func validateArgument(_ argument: HeistArgument, path: HeistPlanPath, scope: HeistReferenceScope) {
        switch argument.core {
        case .none:
            break
        case .string(let value):
            validateString(value, path: path.child(.value), scope: scope)
        case .accessibilityTarget(let target):
            validateTarget(target, path: path.child(.target), scope: scope)
        }
    }

    mutating func validateAction(
        _ action: ActionStep,
        path: HeistPlanPath,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validateCommand(action.command, path: path.child(.command), scope: scope, environment: environment)
        if let waiver = action.expectationPolicy.waiver?.reason {
            addString(waiver, path: path.child(.withoutExpectation), role: "expectation waiver")
        }
        for diagnostic in action.expectationValidationDiagnostics {
            fail(
                path: path.child(.expectation),
                contract: "action expectation composition must be supported and unambiguous",
                observed: diagnostic.message,
                correction: diagnostic.hint ?? "Use one change predicate plus optional state predicates, or split unrelated waits into explicit WaitFor steps."
            )
        }
    }

    mutating func validateCommand(
        _ command: HeistActionCommand,
        path: HeistPlanPath,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validateCommandExpressions(command, path: path, scope: scope)
        if let failure = command.durableHeistActionFailure {
            failNonDurableAction(at: path, observed: failure)
        }
        do {
            _ = try HeistActionPayloadAdmission.resolve(command, in: environment)
        } catch {
            fail(
                path: path,
                contract: "resolved action command must be admissible",
                observed: summarize(error),
                correction: "Use values and refs that resolve to a valid \(command.wireType.rawValue) action."
            )
        }
    }

    mutating func validateWait(
        _ wait: WaitStep,
        path: HeistPlanPath,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validatePredicate(wait.predicate, path: path.child(.predicate), depth: 1, scope: scope)
        do {
            _ = try wait.resolve(in: environment)
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
        path: HeistPlanPath,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validatePredicate(predicateCase.predicate, path: path.child(.predicate), depth: 1, scope: scope)
        do {
            _ = try predicateCase.predicate.resolve(in: environment)
        } catch {
            fail(
                path: path.child(.predicate),
                contract: "predicate refs must resolve in the current heist scope",
                observed: summarize(error),
                correction: "Use target refs or string refs only inside the loop body that defines them."
            )
        }
    }

    mutating func validateCollectionLoopNesting(
        kind: String,
        path: HeistPlanPath
    ) {
        guard path.isInsideCollectionLoopBody else { return }
        fail(
            path: path,
            contract: Self.nestedCollectionLoopContract,
            observed: "\(kind) inside collection loop",
            correction: Self.nestedCollectionLoopCorrection
        )
    }

    mutating func validateForEachElement(
        _ step: ForEachElementStep,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        validateElementPredicate(
            step.matching,
            path: path.child(.matching),
            scope: scope
        )
        addParameterString(step.parameter.rawValue, path: path.child(.parameter), role: "for_each_element parameter")
        if step.limit > limits.maxForEachElementLimit {
            fail(
                path: path.child(.limit),
                contract: "max for_each_element limit",
                observed: "\(step.limit)",
                correction: "Use a limit of \(limits.maxForEachElementLimit) or less."
            )
        }
    }

    private mutating func validateForEachString(
        _ step: ForEachStringStep,
        path: HeistPlanPath
    ) {
        addParameterString(step.parameter.rawValue, path: path.child(.parameter), role: "for_each_string parameter")
        if step.values.count > limits.maxForEachStringValues {
            fail(
                path: path.child(.values),
                contract: "max for_each_string values",
                observed: "\(step.values.count) values",
                correction: "Use \(limits.maxForEachStringValues) values or fewer."
            )
        }
        for (index, value) in step.values.enumerated() {
            addString(value, path: path.child(.values).index(index), role: "for_each_string value")
        }
    }

    mutating func validateRepeatUntil(
        _ step: RepeatUntilStep,
        path: HeistPlanPath
    ) {
        guard !step.body.isEmpty else {
            fail(
                path: path.child(.body),
                contract: "repeat_until body must not be empty",
                observed: "empty body",
                correction: "Add at least one action to repeat, or use WaitFor for passive waiting."
            )
            return
        }
    }

    private mutating func validateResolvedStringLoopAction(
        _ action: ActionStep,
        context: HeistTraversalContext
    ) {
        for check in context.bindingSamples {
            do {
                _ = try HeistActionPayloadAdmission.resolve(action.command, in: check.environment)
            } catch {
                fail(
                    path: context.path,
                    contract: "string loop value must resolve to an admissible action command",
                    observed: "\(check.sourcePath.description) resolved to \(summarize(error))",
                    correction: "Use loop string values that keep every referenced action admissible."
                )
            }
        }
    }

    private mutating func validateResolvedStringLoopWait(
        _ wait: WaitStep,
        context: HeistTraversalContext
    ) {
        for check in context.bindingSamples {
            do {
                _ = try wait.resolve(in: check.environment)
            } catch {
                fail(
                    path: context.path,
                    contract: "string loop value must resolve wait predicates",
                    observed: "\(check.sourcePath.description) resolved to \(summarize(error))",
                    correction: "Use loop string values that keep every referenced wait predicate valid."
                )
            }
        }
    }
}

private extension HeistPlanPath {
    var isInsideCollectionLoopBody: Bool {
        contains(.forEachElement, followedBy: .body) || contains(.forEachString, followedBy: .body)
    }
}

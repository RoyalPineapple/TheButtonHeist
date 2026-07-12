import Foundation

private struct HeistPlanAdmissionTraversalContext {
    let path: HeistTraversalPath
    let depth: Int
    let referenceBindings: HeistReferenceBindingContext
    let definitionScope: HeistPlanAdmissionDefinitionScope
    let rootDefinitionScope: HeistPlanAdmissionDefinitionScope
    let invocationStack: [HeistCallGraph.Node]

    var scope: HeistReferenceScope {
        referenceBindings.scope
    }

    var environment: HeistExecutionEnvironment {
        referenceBindings.environment
    }

    func child(
        path: HeistTraversalPath,
        depth: Int? = nil,
        referenceBindings: HeistReferenceBindingContext? = nil,
        definitionScope: HeistPlanAdmissionDefinitionScope? = nil,
        rootDefinitionScope: HeistPlanAdmissionDefinitionScope? = nil,
        invocationStack: [HeistCallGraph.Node]? = nil
    ) -> Self {
        Self(
            path: path,
            depth: depth ?? self.depth,
            referenceBindings: referenceBindings ?? self.referenceBindings,
            definitionScope: definitionScope ?? self.definitionScope,
            rootDefinitionScope: rootDefinitionScope ?? self.rootDefinitionScope,
            invocationStack: invocationStack ?? self.invocationStack
        )
    }

    func resolveInvocation(path: HeistInvocationPath) -> ResolvedHeistPlanAdmissionDefinition? {
        definitionScope.resolveInvocation(path: path, rootScope: rootDefinitionScope)
    }

    func callGraphCycle(closing node: HeistCallGraph.Node) -> HeistCallGraph.Cycle? {
        HeistCallGraph.nodeCycle(closing: node, in: invocationStack).map(HeistCallGraph.Cycle.init)
    }
}

private struct HeistPlanAdmissionDefinitionScope {
    let definitions: [HeistPlanAdmissionCandidate]
    let pathPrefix: [String]

    init(definitions: [HeistPlanAdmissionCandidate], pathPrefix: [String] = []) {
        self.definitions = definitions
        self.pathPrefix = pathPrefix
    }

    func resolveInvocation(
        path: HeistInvocationPath,
        rootScope: HeistPlanAdmissionDefinitionScope
    ) -> ResolvedHeistPlanAdmissionDefinition? {
        if let local = resolve(components: path.components, namePath: pathPrefix) {
            return local
        }
        guard path.components.count > 1 else { return nil }
        return rootScope.resolve(components: path.components, namePath: rootScope.pathPrefix)
    }

    private func resolve(
        components: [String],
        componentIndex: Int = 0,
        namePath: [String]
    ) -> ResolvedHeistPlanAdmissionDefinition? {
        guard components.indices.contains(componentIndex) else { return nil }
        let component = components[componentIndex]
        guard let definition = definitions.first(where: { $0.name == component }) else { return nil }
        let resolvedNamePath = namePath + [component]
        guard componentIndex + 1 < components.count else {
            return ResolvedHeistPlanAdmissionDefinition(definition: definition, namePath: resolvedNamePath)
        }
        return HeistPlanAdmissionDefinitionScope(
            definitions: definition.definitions,
            pathPrefix: resolvedNamePath
        ).resolve(
            components: components,
            componentIndex: componentIndex + 1,
            namePath: resolvedNamePath
        )
    }
}

private struct ResolvedHeistPlanAdmissionDefinition {
    let definition: HeistPlanAdmissionCandidate
    let namePath: [String]

    var callGraphNode: HeistCallGraph.Node {
        HeistCallGraph.Node(namePath: namePath)
    }
}

/// RuntimeSafety owns the bounded executable-plan boundary.
///
/// Totality rests on three bounds: (a) acyclic call graph
/// [HeistCallGraph] - structural; (b) bounded ForEach; (c) timeout-floored
/// RepeatUntil/WaitFor - runtime floors.
struct HeistPlanRuntimeSafetyValidator {
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

    mutating func inspect(_ candidate: HeistPlanAdmissionCandidate) {
        let rootDefinitionScope = HeistPlanAdmissionDefinitionScope(definitions: candidate.definitions)
        let context = HeistPlanAdmissionTraversalContext(
            path: .root,
            depth: 0,
            referenceBindings: .runtimeSafetyPlaceholder(for: candidate.parameter),
            definitionScope: rootDefinitionScope,
            rootDefinitionScope: rootDefinitionScope,
            invocationStack: []
        )
        validatePlanHeader(candidate, path: context.path, requiresName: false)
        walkDefinitions(
            candidate.definitions,
            path: context.path.child(.definitions),
            depth: 1,
            definitionScope: rootDefinitionScope,
            rootDefinitionScope: rootDefinitionScope
        )
        walk(candidate.body, context: context.child(path: context.path.child(.body), depth: 1))
    }

    private mutating func validateStep(at context: HeistPlanAdmissionTraversalContext) {
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

    private mutating func walk(
        _ steps: [HeistStepAdmissionCandidate],
        context: HeistPlanAdmissionTraversalContext
    ) {
        for (index, step) in steps.enumerated() {
            walk(step, context: context.child(path: context.path.index(index)))
        }
    }

    private mutating func walk(
        _ steps: [HeistStep],
        context: HeistPlanAdmissionTraversalContext
    ) {
        walk(steps.map(HeistStepAdmissionCandidate.init), context: context)
    }

    private mutating func walk(
        _ step: HeistStepAdmissionCandidate,
        context: HeistPlanAdmissionTraversalContext
    ) {
        validateStep(at: context)
        switch step.payload {
        case .action(let action):
            let actionContext = context.child(path: context.path.child(.action))
            validateAction(action, path: actionContext.path, scope: context.scope, environment: context.environment)
            if let expectation = action.expectationPolicy.expectedStep {
                validateWait(
                    expectation,
                    path: actionContext.path.child(.expectation),
                    scope: context.scope,
                    environment: context.environment
                )
            }
        case .wait(let wait):
            walk(wait, context: context)
        case .conditional(let conditional):
            walk(conditional, context: context)
        case .forEachElement(let forEach):
            walk(forEach, context: context)
        case .forEachString(let forEach):
            walk(forEach, context: context)
        case .repeatUntil(let repeatUntil):
            walk(repeatUntil, context: context)
        case .warn(let warn):
            addString(warn.message, path: context.path.child(.warn).child(.message).description, role: "warn message")
        case .fail(let fail):
            addString(fail.message, path: context.path.child(.fail).child(.message).description, role: "fail message")
        case .heist(let candidate):
            walkInlineHeist(candidate, context: context)
        case .invoke(let invocation):
            walkInvocation(invocation, context: context)
        }
    }

    private mutating func walk(
        _ wait: WaitStep,
        context: HeistPlanAdmissionTraversalContext
    ) {
        let waitContext = context.child(path: context.path.child(.wait))
        validateWait(wait, path: waitContext.path, scope: context.scope, environment: context.environment)
        guard let elseBody = wait.elseBody else { return }
        walk(elseBody, context: context.child(path: waitContext.path.child(.elseBody), depth: context.depth + 1))
    }

    private mutating func walk(
        _ conditional: ConditionalStep,
        context: HeistPlanAdmissionTraversalContext
    ) {
        let conditionalContext = context.child(path: context.path.child(.conditional))
        for (index, predicateCase) in conditional.cases.enumerated() {
            let caseContext = conditionalContext.child(
                path: conditionalContext.path.child(.cases).index(index),
                depth: conditionalContext.depth + 1
            )
            validatePredicateCase(
                predicateCase,
                path: caseContext.path,
                scope: caseContext.scope,
                environment: caseContext.environment
            )
            walk(
                predicateCase.body,
                context: caseContext.child(path: caseContext.path.child(.body), depth: conditionalContext.depth + 1)
            )
        }
        if let elseBody = conditional.elseBody {
            walk(
                elseBody,
                context: conditionalContext.child(
                    path: conditionalContext.path.child(.elseBody),
                    depth: conditionalContext.depth + 1
                )
            )
        }
    }

    private mutating func walk(
        _ forEach: ForEachElementStep,
        context: HeistPlanAdmissionTraversalContext
    ) {
        let forEachContext = context.child(path: context.path.child(.forEachElement))
        validateCollectionLoopNesting(kind: "for_each_element", path: forEachContext.path)
        validateForEachElement(forEach, path: forEachContext.path)
        walk(
            forEach.body,
            context: forEachContext.child(
                path: forEachContext.path.child(.body),
                depth: context.depth + 1,
                referenceBindings: context.referenceBindings.binding(
                    target: .predicate(ElementPredicateTemplate(forEach.matching)),
                    to: forEach.parameter
                )
            )
        )
    }

    private mutating func walk(
        _ forEach: ForEachStringStep,
        context: HeistPlanAdmissionTraversalContext
    ) {
        let forEachContext = context.child(path: context.path.child(.forEachString))
        validateCollectionLoopNesting(kind: "for_each_string", path: forEachContext.path)
        validateForEachString(forEach, context: forEachContext)
        walk(
            forEach.body,
            context: forEachContext.child(
                path: forEachContext.path.child(.body),
                depth: context.depth + 1,
                referenceBindings: context.referenceBindings.binding(
                    string: forEach.values.first ?? "",
                    to: forEach.parameter
                )
            )
        )
    }

    private mutating func walk(
        _ repeatUntil: RepeatUntilStep,
        context: HeistPlanAdmissionTraversalContext
    ) {
        let repeatContext = context.child(path: context.path.child(.repeatUntil))
        validateRepeatUntil(repeatUntil, path: repeatContext.path)
        validateWait(
            WaitStep(predicate: repeatUntil.predicate, timeout: repeatUntil.timeout),
            path: repeatContext.path.child(.predicate),
            scope: repeatContext.scope,
            environment: repeatContext.environment
        )
        walk(
            repeatUntil.body,
            context: repeatContext.child(path: repeatContext.path.child(.body), depth: context.depth + 1)
        )
        if let elseBody = repeatUntil.elseBody {
            walk(
                elseBody,
                context: repeatContext.child(path: repeatContext.path.child(.elseBody), depth: context.depth + 1)
            )
        }
    }

    private mutating func walkInlineHeist(
        _ candidate: HeistPlanAdmissionCandidate,
        context: HeistPlanAdmissionTraversalContext
    ) {
        let inlineDefinitionScope = HeistPlanAdmissionDefinitionScope(definitions: candidate.definitions)
        let heistContext = context.child(
            path: context.path.child(.heist),
            definitionScope: inlineDefinitionScope,
            rootDefinitionScope: inlineDefinitionScope
        )
        validatePlanHeader(candidate, path: heistContext.path, requiresName: false)
        if candidate.parameter != .none {
            fail(
                path: heistContext.path.child(.parameter).description,
                contract: "inline heist group must not declare a parameter",
                observed: candidate.parameter.kind.rawValue,
                correction: "Use RunHeist with a named capability when a heist needs an argument."
            )
        }
        walkDefinitions(
            candidate.definitions,
            path: heistContext.path.child(.definitions),
            depth: context.depth + 1,
            definitionScope: inlineDefinitionScope,
            rootDefinitionScope: inlineDefinitionScope
        )
        walk(
            candidate.body,
            context: heistContext.child(path: heistContext.path.child(.body), depth: context.depth + 1)
        )
    }

    private mutating func walkInvocation(
        _ invocation: HeistInvocationStep,
        context: HeistPlanAdmissionTraversalContext
    ) {
        let invocationContext = context.child(path: context.path.child(.invoke))
        validateInvocation(invocation, context: invocationContext)
        if let expectation = invocation.expectation {
            validateWait(
                expectation,
                path: invocationContext.path.child(.expectation),
                scope: invocationContext.scope,
                environment: invocationContext.environment
            )
        }
        guard let resolved = context.resolveInvocation(path: invocation.invocationPath) else { return }
        let resolvedNode = resolved.callGraphNode
        guard context.callGraphCycle(closing: resolvedNode) == nil,
              let referenceBindings = try? context.referenceBindings.binding(
                argument: invocation.argument,
                to: resolved.definition.parameter
              )
        else { return }
        walk(
            resolved.definition.body,
            context: invocationContext.child(
                path: invocationContext.path.child(.body),
                depth: context.depth + 1,
                referenceBindings: referenceBindings,
                definitionScope: HeistPlanAdmissionDefinitionScope(
                    definitions: resolved.definition.definitions,
                    pathPrefix: resolved.namePath
                ),
                invocationStack: context.invocationStack + [resolvedNode]
            )
        )
    }

    mutating func validatePlanHeader(
        _ plan: HeistPlanAdmissionCandidate,
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

    private mutating func walkDefinitions(
        _ definitions: [HeistPlanAdmissionCandidate],
        path: HeistTraversalPath,
        depth: Int,
        definitionScope: HeistPlanAdmissionDefinitionScope,
        rootDefinitionScope: HeistPlanAdmissionDefinitionScope
    ) {
        validateDefinitions(definitions, path: path)
        for (index, definition) in definitions.enumerated() {
            let definitionPath = definitionScope.pathPrefix + [definition.name ?? ""]
            let nestedDefinitionScope = HeistPlanAdmissionDefinitionScope(
                definitions: definition.definitions,
                pathPrefix: definitionPath
            )
            let context = HeistPlanAdmissionTraversalContext(
                path: path.index(index),
                depth: depth,
                referenceBindings: .runtimeSafetyPlaceholder(for: definition.parameter),
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope,
                invocationStack: []
            )
            validatePlanHeader(definition, path: context.path, requiresName: true)
            walkDefinitions(
                definition.definitions,
                path: context.path.child(.definitions),
                depth: depth + 1,
                definitionScope: nestedDefinitionScope,
                rootDefinitionScope: rootDefinitionScope
            )
            walk(
                definition.body,
                context: context.child(
                    path: context.path.child(.body),
                    depth: depth + 1,
                    definitionScope: nestedDefinitionScope,
                    invocationStack: [HeistCallGraph.Node(namePath: definitionPath)]
                )
            )
        }
    }

    mutating func validateDefinitions(
        _ definitions: [HeistPlanAdmissionCandidate],
        path: HeistTraversalPath
    ) {
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

    private mutating func validateInvocation(
        _ step: HeistInvocationStep,
        context: HeistPlanAdmissionTraversalContext
    ) {
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
        if let cycle = context.callGraphCycle(closing: resolved.callGraphNode) {
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
            _ = try context.referenceBindings.binding(argument: step.argument, to: resolved.definition.parameter)
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
        case .accessibilityTarget(let target):
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
        if let waiver = action.expectationPolicy.waiver?.reason {
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
                correction: "Use target refs or string refs only inside the loop body that defines them."
            )
        }
    }

    mutating func validateCollectionLoopNesting(
        kind: String,
        path: HeistTraversalPath
    ) {
        guard path.isInsideCollectionLoopBody else { return }
        fail(
            path: path.description,
            contract: Self.nestedCollectionLoopContract,
            observed: "\(kind) inside collection loop",
            correction: Self.nestedCollectionLoopCorrection
        )
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

    private mutating func validateForEachString(
        _ step: ForEachStringStep,
        context: HeistPlanAdmissionTraversalContext
    ) {
        let path = context.path
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
                context: context.child(
                    path: path.child(.body),
                    depth: context.depth + 1,
                    referenceBindings: context.referenceBindings.binding(string: value, to: step.parameter)
                ),
                valuePath: path.child(.values).index(index).description
            )
        }
    }

    mutating func validateRepeatUntil(_ step: RepeatUntilStep, path: HeistTraversalPath) {
        guard step.timeout.isFinite else {
            fail(
                path: path.child(.timeout).description,
                contract: "repeat_until timeout must be finite",
                observed: ScoreDescription.decimal(step.timeout),
                correction: "Use a finite timeout from 0 through \(ScoreDescription.decimal(limits.maxRepeatUntilTimeout)) seconds."
            )
            return
        }
        guard step.timeout >= 0 else {
            fail(
                path: path.child(.timeout).description,
                contract: "repeat_until timeout must be non-negative",
                observed: "\(step.timeout)",
                correction: "Use a timeout of 0 or more seconds."
            )
            return
        }
        if step.timeout > limits.maxRepeatUntilTimeout {
            fail(
                path: path.child(.timeout).description,
                contract: "max repeat_until timeout",
                observed: "\(ScoreDescription.decimal(step.timeout)) seconds",
                correction: "Use a timeout of \(ScoreDescription.decimal(limits.maxRepeatUntilTimeout)) seconds or less."
            )
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

    private mutating func validateResolvedStringLoopPayloads(
        _ steps: [HeistStep],
        context: HeistPlanAdmissionTraversalContext,
        valuePath: String
    ) {
        validateResolvedStringLoopPayloads(
            steps.map(HeistStepAdmissionCandidate.init),
            context: context,
            valuePath: valuePath
        )
    }

    private mutating func validateResolvedStringLoopPayloads(
        _ steps: [HeistStepAdmissionCandidate],
        context: HeistPlanAdmissionTraversalContext,
        valuePath: String
    ) {
        for (index, step) in steps.enumerated() {
            validateResolvedStringLoopPayload(
                step,
                context: context.child(path: context.path.index(index)),
                valuePath: valuePath
            )
        }
    }

    private mutating func validateResolvedStringLoopPayload(
        _ step: HeistStepAdmissionCandidate,
        context: HeistPlanAdmissionTraversalContext,
        valuePath: String
    ) {
        switch step.payload {
        case .action(let action):
            let actionContext = context.child(path: context.path.child(.action))
            validateResolvedStringLoopAction(action, context: actionContext, valuePath: valuePath)
            if let expectation = action.expectationPolicy.expectedStep {
                validateResolvedStringLoopWait(
                    expectation,
                    context: actionContext.child(path: actionContext.path.child(.expectation)),
                    valuePath: valuePath
                )
            }
        case .wait(let wait):
            let waitContext = context.child(path: context.path.child(.wait))
            validateResolvedStringLoopWait(wait, context: waitContext, valuePath: valuePath)
            if let elseBody = wait.elseBody {
                validateResolvedStringLoopPayloads(
                    elseBody,
                    context: waitContext.child(path: waitContext.path.child(.elseBody), depth: context.depth + 1),
                    valuePath: valuePath
                )
            }
        case .conditional(let conditional):
            let conditionalContext = context.child(path: context.path.child(.conditional))
            for (index, predicateCase) in conditional.cases.enumerated() {
                let casePath = conditionalContext.path.child(.cases).index(index)
                validateResolvedStringLoopPayloads(
                    predicateCase.body,
                    context: conditionalContext.child(path: casePath.child(.body), depth: context.depth + 1),
                    valuePath: valuePath
                )
            }
            if let elseBody = conditional.elseBody {
                validateResolvedStringLoopPayloads(
                    elseBody,
                    context: conditionalContext.child(
                        path: conditionalContext.path.child(.elseBody),
                        depth: context.depth + 1
                    ),
                    valuePath: valuePath
                )
            }
        case .forEachElement(let forEach):
            let forEachContext = context.child(path: context.path.child(.forEachElement))
            validateResolvedStringLoopPayloads(
                forEach.body,
                context: forEachContext.child(
                    path: forEachContext.path.child(.body),
                    depth: context.depth + 1,
                    referenceBindings: context.referenceBindings.binding(
                        target: .predicate(ElementPredicateTemplate(forEach.matching)),
                        to: forEach.parameter
                    )
                ),
                valuePath: valuePath
            )
        case .forEachString(let forEach):
            let forEachContext = context.child(path: context.path.child(.forEachString))
            validateResolvedStringLoopPayloads(
                forEach.body,
                context: forEachContext.child(
                    path: forEachContext.path.child(.body),
                    depth: context.depth + 1,
                    referenceBindings: context.referenceBindings.binding(
                        string: forEach.values.first ?? "",
                        to: forEach.parameter
                    )
                ),
                valuePath: valuePath
            )
        case .repeatUntil(let repeatUntil):
            let repeatContext = context.child(path: context.path.child(.repeatUntil))
            validateResolvedStringLoopWait(
                WaitStep(predicate: repeatUntil.predicate, timeout: repeatUntil.timeout),
                context: repeatContext.child(path: repeatContext.path.child(.predicate)),
                valuePath: valuePath
            )
            validateResolvedStringLoopPayloads(
                repeatUntil.body,
                context: repeatContext.child(path: repeatContext.path.child(.body), depth: context.depth + 1),
                valuePath: valuePath
            )
            if let elseBody = repeatUntil.elseBody {
                validateResolvedStringLoopPayloads(
                    elseBody,
                    context: repeatContext.child(path: repeatContext.path.child(.elseBody), depth: context.depth + 1),
                    valuePath: valuePath
                )
            }
        case .warn, .fail:
            break
        case .heist(let candidate):
            validateResolvedStringLoopInlineHeist(candidate, context: context, valuePath: valuePath)
        case .invoke(let invocation):
            validateResolvedStringLoopInvocation(invocation, context: context, valuePath: valuePath)
        }
    }

    private mutating func validateResolvedStringLoopInlineHeist(
        _ candidate: HeistPlanAdmissionCandidate,
        context: HeistPlanAdmissionTraversalContext,
        valuePath: String
    ) {
        let scope = HeistPlanAdmissionDefinitionScope(definitions: candidate.definitions)
        let heistContext = context.child(
            path: context.path.child(.heist),
            definitionScope: scope,
            rootDefinitionScope: scope
        )
        validateResolvedStringLoopDefinitions(
            candidate.definitions,
            path: heistContext.path.child(.definitions),
            depth: context.depth + 1,
            definitionScope: scope,
            rootDefinitionScope: scope,
            valuePath: valuePath
        )
        validateResolvedStringLoopPayloads(
            candidate.body,
            context: heistContext.child(path: heistContext.path.child(.body), depth: context.depth + 1),
            valuePath: valuePath
        )
    }

    private mutating func validateResolvedStringLoopDefinitions(
        _ definitions: [HeistPlanAdmissionCandidate],
        path: HeistTraversalPath,
        depth: Int,
        definitionScope: HeistPlanAdmissionDefinitionScope,
        rootDefinitionScope: HeistPlanAdmissionDefinitionScope,
        valuePath: String
    ) {
        for (index, definition) in definitions.enumerated() {
            let definitionPath = definitionScope.pathPrefix + [definition.name ?? ""]
            let nestedScope = HeistPlanAdmissionDefinitionScope(
                definitions: definition.definitions,
                pathPrefix: definitionPath
            )
            validateResolvedStringLoopDefinitions(
                definition.definitions,
                path: path.index(index).child(.definitions),
                depth: depth + 1,
                definitionScope: nestedScope,
                rootDefinitionScope: rootDefinitionScope,
                valuePath: valuePath
            )
            validateResolvedStringLoopPayloads(
                definition.body,
                context: HeistPlanAdmissionTraversalContext(
                    path: path.index(index).child(.body),
                    depth: depth + 1,
                    referenceBindings: .runtimeSafetyPlaceholder(for: definition.parameter),
                    definitionScope: nestedScope,
                    rootDefinitionScope: rootDefinitionScope,
                    invocationStack: [HeistCallGraph.Node(namePath: definitionPath)]
                ),
                valuePath: valuePath
            )
        }
    }

    private mutating func validateResolvedStringLoopInvocation(
        _ invocation: HeistInvocationStep,
        context: HeistPlanAdmissionTraversalContext,
        valuePath: String
    ) {
        let invocationContext = context.child(path: context.path.child(.invoke))
        if let expectation = invocation.expectation {
            validateResolvedStringLoopWait(
                expectation,
                context: invocationContext.child(path: invocationContext.path.child(.expectation)),
                valuePath: valuePath
            )
        }
        guard let resolved = context.resolveInvocation(path: invocation.invocationPath) else { return }
        let node = resolved.callGraphNode
        guard context.callGraphCycle(closing: node) == nil,
              let bindings = try? context.referenceBindings.binding(
                argument: invocation.argument,
                to: resolved.definition.parameter
              )
        else { return }
        validateResolvedStringLoopPayloads(
            resolved.definition.body,
            context: invocationContext.child(
                path: invocationContext.path.child(.body),
                depth: context.depth + 1,
                referenceBindings: bindings,
                definitionScope: HeistPlanAdmissionDefinitionScope(
                    definitions: resolved.definition.definitions,
                    pathPrefix: resolved.namePath
                ),
                invocationStack: context.invocationStack + [node]
            ),
            valuePath: valuePath
        )
    }

    private mutating func validateResolvedStringLoopAction(
        _ action: ActionStep,
        context: HeistPlanAdmissionTraversalContext,
        valuePath: String
    ) {
        do {
            try action.command.assertResolvedPayloadAdmissible(in: context.environment)
        } catch {
            fail(
                path: context.path.description,
                contract: "string loop value must lower through the heist action payload contract",
                observed: "\(valuePath) resolved to \(summarize(error))",
                correction: "Use loop string values that keep every referenced command payload valid."
            )
        }
    }

    private mutating func validateResolvedStringLoopWait(
        _ wait: WaitStep,
        context: HeistPlanAdmissionTraversalContext,
        valuePath: String
    ) {
        do {
            let resolved = try wait.resolve(in: context.environment)
            try HeistRuntimePayloadContractValidator.validate(WaitTarget(
                predicate: resolved.predicate,
                timeout: resolved.timeout
            ))
        } catch {
            fail(
                path: context.path.description,
                contract: "string loop value must resolve wait predicates",
                observed: "\(valuePath) resolved to \(summarize(error))",
                correction: "Use loop string values that keep every referenced wait predicate valid."
            )
        }
    }
}

private extension HeistTraversalPath {
    var isInsideCollectionLoopBody: Bool {
        description.contains(".\(HeistTraversalPathField.forEachElement.rawValue).body") ||
            description.contains(".\(HeistTraversalPathField.forEachString.rawValue).body")
    }
}

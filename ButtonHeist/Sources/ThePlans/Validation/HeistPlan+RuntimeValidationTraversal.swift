import Foundation

private struct ResolvedStringLoopPayloadCheck {
    let referenceBindings: HeistReferenceBindingContext
    let valuePath: String

    var environment: HeistExecutionEnvironment {
        referenceBindings.environment
    }

    func binding(string: String, to parameter: HeistReferenceName) -> Self {
        Self(
            referenceBindings: referenceBindings.binding(string: string, to: parameter),
            valuePath: valuePath
        )
    }

    func binding(target: AccessibilityTarget, to parameter: HeistReferenceName) -> Self {
        Self(
            referenceBindings: referenceBindings.binding(target: target, to: parameter),
            valuePath: valuePath
        )
    }
}

private struct HeistPlanAdmissionTraversalContext {
    let path: HeistTraversalPath
    let depth: Int
    let referenceBindings: HeistReferenceBindingContext
    let definitionScope: HeistPlanAdmissionDefinitionScope
    let rootDefinitionScope: HeistPlanAdmissionDefinitionScope
    let invocationStack: [HeistCallGraph.Node]
    let stringLoopPayloadChecks: [ResolvedStringLoopPayloadCheck]

    var scope: HeistReferenceScope {
        referenceBindings.scope
    }

    var environment: HeistExecutionEnvironment {
        referenceBindings.environment
    }

    func child(path: HeistTraversalPath, depth: Int) -> Self {
        Self(
            path: path,
            depth: depth,
            referenceBindings: referenceBindings,
            definitionScope: definitionScope,
            rootDefinitionScope: rootDefinitionScope,
            invocationStack: invocationStack,
            stringLoopPayloadChecks: stringLoopPayloadChecks
        )
    }

    func child(path: HeistTraversalPath) -> Self {
        child(path: path, depth: depth)
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
            invocationStack: [],
            stringLoopPayloadChecks: []
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
            validateResolvedStringLoopAction(action, context: actionContext)
            validateAction(action, path: actionContext.path, scope: context.scope, environment: context.environment)
            if let expectation = action.expectationPolicy.expectedStep {
                validateResolvedStringLoopWait(
                    expectation,
                    context: actionContext.child(path: actionContext.path.child(.expectation))
                )
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
        _ wait: HeistWaitAdmissionCandidate,
        context: HeistPlanAdmissionTraversalContext
    ) {
        let waitContext = context.child(path: context.path.child(.wait))
        let waitStep = WaitStep(predicate: wait.predicate, timeout: wait.timeout)
        validateResolvedStringLoopWait(waitStep, context: waitContext)
        validateWait(waitStep, path: waitContext.path, scope: context.scope, environment: context.environment)
        guard let elseBody = wait.elseBody else { return }
        walk(elseBody, context: context.child(path: waitContext.path.child(.elseBody), depth: context.depth + 1))
    }

    private mutating func walk(
        _ conditional: HeistConditionalAdmissionCandidate,
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
        _ forEach: HeistForEachElementAdmissionCandidate,
        context: HeistPlanAdmissionTraversalContext
    ) {
        let forEachContext = context.child(path: context.path.child(.forEachElement))
        validateCollectionLoopNesting(kind: "for_each_element", path: forEachContext.path)
        validateForEachElement(forEach, path: forEachContext.path)
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(forEach.matching))
        walk(
            forEach.body,
            context: HeistPlanAdmissionTraversalContext(
                path: forEachContext.path.child(.body),
                depth: context.depth + 1,
                referenceBindings: context.referenceBindings.binding(target: target, to: forEach.parameter),
                definitionScope: context.definitionScope,
                rootDefinitionScope: context.rootDefinitionScope,
                invocationStack: context.invocationStack,
                stringLoopPayloadChecks: context.stringLoopPayloadChecks.map {
                    $0.binding(target: target, to: forEach.parameter)
                }
            )
        )
    }

    private mutating func walk(
        _ forEach: HeistForEachStringAdmissionCandidate,
        context: HeistPlanAdmissionTraversalContext
    ) {
        let forEachContext = context.child(path: context.path.child(.forEachString))
        validateCollectionLoopNesting(kind: "for_each_string", path: forEachContext.path)
        validateForEachString(forEach, path: forEachContext.path)
        let firstValue = forEach.values.first ?? ""
        let inheritedChecks = context.stringLoopPayloadChecks.map {
            $0.binding(string: firstValue, to: forEach.parameter)
        }
        let valueChecks = forEach.values.enumerated().map { index, value in
            ResolvedStringLoopPayloadCheck(
                referenceBindings: context.referenceBindings.binding(string: value, to: forEach.parameter),
                valuePath: forEachContext.path.child(.values).index(index).description
            )
        }
        walk(
            forEach.body,
            context: HeistPlanAdmissionTraversalContext(
                path: forEachContext.path.child(.body),
                depth: context.depth + 1,
                referenceBindings: context.referenceBindings.binding(string: firstValue, to: forEach.parameter),
                definitionScope: context.definitionScope,
                rootDefinitionScope: context.rootDefinitionScope,
                invocationStack: context.invocationStack,
                stringLoopPayloadChecks: inheritedChecks + valueChecks
            )
        )
    }

    private mutating func walk(
        _ repeatUntil: HeistRepeatUntilAdmissionCandidate,
        context: HeistPlanAdmissionTraversalContext
    ) {
        let repeatContext = context.child(path: context.path.child(.repeatUntil))
        validateRepeatUntil(repeatUntil, path: repeatContext.path)
        let predicateWait = WaitStep(predicate: repeatUntil.predicate, timeout: repeatUntil.timeout)
        validateResolvedStringLoopWait(
            predicateWait,
            context: repeatContext.child(path: repeatContext.path.child(.predicate))
        )
        validateWait(
            predicateWait,
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
        let heistContext = HeistPlanAdmissionTraversalContext(
            path: context.path.child(.heist),
            depth: context.depth,
            referenceBindings: context.referenceBindings,
            definitionScope: inlineDefinitionScope,
            rootDefinitionScope: inlineDefinitionScope,
            invocationStack: context.invocationStack,
            stringLoopPayloadChecks: context.stringLoopPayloadChecks
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
            validateResolvedStringLoopWait(
                expectation,
                context: invocationContext.child(path: invocationContext.path.child(.expectation))
            )
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
        let payloadChecks = context.stringLoopPayloadChecks.compactMap { check in
            try? ResolvedStringLoopPayloadCheck(
                referenceBindings: check.referenceBindings.binding(
                    argument: invocation.argument,
                    to: resolved.definition.parameter
                ),
                valuePath: check.valuePath
            )
        }
        walk(
            resolved.definition.body,
            context: HeistPlanAdmissionTraversalContext(
                path: invocationContext.path.child(.body),
                depth: context.depth + 1,
                referenceBindings: referenceBindings,
                definitionScope: HeistPlanAdmissionDefinitionScope(
                    definitions: resolved.definition.definitions,
                    pathPrefix: resolved.namePath
                ),
                rootDefinitionScope: context.rootDefinitionScope,
                invocationStack: context.invocationStack + [resolvedNode],
                stringLoopPayloadChecks: payloadChecks
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
                invocationStack: [],
                stringLoopPayloadChecks: []
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
                context: HeistPlanAdmissionTraversalContext(
                    path: context.path.child(.body),
                    depth: depth + 1,
                    referenceBindings: context.referenceBindings,
                    definitionScope: nestedDefinitionScope,
                    rootDefinitionScope: rootDefinitionScope,
                    invocationStack: [HeistCallGraph.Node(namePath: definitionPath)],
                    stringLoopPayloadChecks: []
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
        _ predicateCase: HeistPredicateCaseAdmissionCandidate,
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
        _ step: HeistForEachElementAdmissionCandidate,
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
        _ step: HeistForEachStringAdmissionCandidate,
        path: HeistTraversalPath
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
    }

    mutating func validateRepeatUntil(
        _ step: HeistRepeatUntilAdmissionCandidate,
        path: HeistTraversalPath
    ) {
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

    private mutating func validateResolvedStringLoopAction(
        _ action: ActionStep,
        context: HeistPlanAdmissionTraversalContext
    ) {
        for check in context.stringLoopPayloadChecks {
            do {
                try action.command.assertResolvedPayloadAdmissible(in: check.environment)
            } catch {
                fail(
                    path: context.path.description,
                    contract: "string loop value must lower through the heist action payload contract",
                    observed: "\(check.valuePath) resolved to \(summarize(error))",
                    correction: "Use loop string values that keep every referenced command payload valid."
                )
            }
        }
    }

    private mutating func validateResolvedStringLoopWait(
        _ wait: WaitStep,
        context: HeistPlanAdmissionTraversalContext
    ) {
        for check in context.stringLoopPayloadChecks {
            do {
                let resolved = try wait.resolve(in: check.environment)
                try HeistRuntimePayloadContractValidator.validate(WaitTarget(
                    predicate: resolved.predicate,
                    timeout: resolved.timeout
                ))
            } catch {
                fail(
                    path: context.path.description,
                    contract: "string loop value must resolve wait predicates",
                    observed: "\(check.valuePath) resolved to \(summarize(error))",
                    correction: "Use loop string values that keep every referenced wait predicate valid."
                )
            }
        }
    }
}

private extension HeistTraversalPath {
    var isInsideCollectionLoopBody: Bool {
        description.contains(".\(HeistTraversalPathField.forEachElement.rawValue).body") ||
            description.contains(".\(HeistTraversalPathField.forEachString.rawValue).body")
    }
}

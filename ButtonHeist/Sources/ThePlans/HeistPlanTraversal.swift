import Foundation

struct HeistTraversalContext {
    let path: String
    let depth: Int
    let stepIndex: Int?
    let nextStep: HeistStep?
    let allowsCollectionLoops: Bool
    let scope: HeistReferenceScope
    let environment: HeistExecutionEnvironment
    let definitionScope: HeistDefinitionScope
    let invocationStack: [String]
}

protocol HeistPlanTraversalVisitor {
    mutating func visitPlan(_ plan: HeistPlan, context: HeistTraversalContext)
    mutating func visitDefinitions(_ definitions: [HeistPlan], context: HeistTraversalContext)
    mutating func visitDefinition(_ plan: HeistPlan, context: HeistTraversalContext)
    mutating func visitStep(_ step: HeistStep, context: HeistTraversalContext)
    mutating func visitAction(_ action: ActionStep, context: HeistTraversalContext)
    mutating func visitWait(_ wait: WaitStep, context: HeistTraversalContext)
    mutating func visitConditional(_ conditional: ConditionalStep, context: HeistTraversalContext)
    mutating func visitWaitForCases(_ waitForCases: WaitForCasesStep, context: HeistTraversalContext)
    mutating func visitPredicateCase(_ predicateCase: PredicateCase, context: HeistTraversalContext)
    mutating func visitElseBody(_ body: [HeistStep], context: HeistTraversalContext)
    mutating func visitForEachElement(_ step: ForEachElementStep, context: HeistTraversalContext)
    mutating func visitForEachString(_ step: ForEachStringStep, context: HeistTraversalContext)
    mutating func visitWarn(_ warn: WarnStep, context: HeistTraversalContext)
    mutating func visitFail(_ fail: FailStep, context: HeistTraversalContext)
    mutating func visitHeist(_ plan: HeistPlan, context: HeistTraversalContext)
    mutating func visitInvoke(_ step: HeistInvocationStep, context: HeistTraversalContext)
}

extension HeistPlanTraversalVisitor {
    mutating func visitPlan(_ plan: HeistPlan, context: HeistTraversalContext) {}
    mutating func visitDefinitions(_ definitions: [HeistPlan], context: HeistTraversalContext) {}
    mutating func visitDefinition(_ plan: HeistPlan, context: HeistTraversalContext) {}
    mutating func visitStep(_ step: HeistStep, context: HeistTraversalContext) {}
    mutating func visitAction(_ action: ActionStep, context: HeistTraversalContext) {}
    mutating func visitWait(_ wait: WaitStep, context: HeistTraversalContext) {}
    mutating func visitConditional(_ conditional: ConditionalStep, context: HeistTraversalContext) {}
    mutating func visitWaitForCases(_ waitForCases: WaitForCasesStep, context: HeistTraversalContext) {}
    mutating func visitPredicateCase(_ predicateCase: PredicateCase, context: HeistTraversalContext) {}
    mutating func visitElseBody(_ body: [HeistStep], context: HeistTraversalContext) {}
    mutating func visitForEachElement(_ step: ForEachElementStep, context: HeistTraversalContext) {}
    mutating func visitForEachString(_ step: ForEachStringStep, context: HeistTraversalContext) {}
    mutating func visitWarn(_ warn: WarnStep, context: HeistTraversalContext) {}
    mutating func visitFail(_ fail: FailStep, context: HeistTraversalContext) {}
    mutating func visitHeist(_ plan: HeistPlan, context: HeistTraversalContext) {}
    mutating func visitInvoke(_ step: HeistInvocationStep, context: HeistTraversalContext) {}
}

struct HeistPlanTraversal {
    func walk<V: HeistPlanTraversalVisitor>(
        _ plan: HeistPlan,
        visitor: inout V
    ) {
        let context = HeistTraversalContext(
            path: "$",
            depth: 0,
            stepIndex: nil,
            nextStep: nil,
            allowsCollectionLoops: true,
            scope: .empty,
            environment: .empty,
            definitionScope: HeistDefinitionScope(definitions: plan.definitions),
            invocationStack: []
        )
        visitor.visitPlan(plan, context: context)
        walkDefinitions(
            plan.definitions,
            path: "$.definitions",
            depth: 1,
            definitionScope: context.definitionScope,
            parentContext: context,
            visitor: &visitor
        )
        walk(
            steps: plan.body,
            path: "$.body",
            depth: 1,
            allowsCollectionLoops: true,
            scope: .empty,
            environment: .empty,
            definitionScope: context.definitionScope,
            invocationStack: [],
            visitor: &visitor
        )
    }

    func walk<V: HeistPlanTraversalVisitor>(
        steps: [HeistStep],
        path: String,
        depth: Int,
        allowsCollectionLoops: Bool,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment,
        definitionScope: HeistDefinitionScope,
        invocationStack: [String] = [],
        visitor: inout V
    ) {
        for (index, step) in steps.enumerated() {
            let context = HeistTraversalContext(
                path: "\(path)[\(index)]",
                depth: depth,
                stepIndex: index,
                nextStep: steps.dropFirst(index + 1).first,
                allowsCollectionLoops: allowsCollectionLoops,
                scope: scope,
                environment: environment,
                definitionScope: definitionScope,
                invocationStack: invocationStack
            )
            walk(step: step, context: context, visitor: &visitor)
        }
    }

    private func walk<V: HeistPlanTraversalVisitor>(
        step: HeistStep,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        visitor.visitStep(step, context: context)
        switch step {
        case .action(let action):
            let actionContext = context.child(path: "\(context.path).action")
            visitor.visitAction(action, context: actionContext)
            if let expectation = action.expectation {
                visitor.visitWait(
                    expectation,
                    context: actionContext.child(path: "\(actionContext.path).expectation")
                )
            }
        case .wait(let wait):
            visitor.visitWait(wait, context: context.child(path: "\(context.path).wait"))
        case .conditional(let conditional):
            walk(conditional, context: context, visitor: &visitor)
        case .waitForCases(let waitForCases):
            walk(waitForCases, context: context, visitor: &visitor)
        case .forEachElement(let forEach):
            walk(forEach, context: context, visitor: &visitor)
        case .forEachString(let forEach):
            walk(forEach, context: context, visitor: &visitor)
        case .warn(let warn):
            visitor.visitWarn(warn, context: context.child(path: "\(context.path).warn"))
        case .fail(let fail):
            visitor.visitFail(fail, context: context.child(path: "\(context.path).fail"))
        case .heist(let plan):
            walkInlineHeist(plan, context: context, visitor: &visitor)
        case .invoke(let invoke):
            walkInvocation(invoke, context: context, visitor: &visitor)
        }
    }

    private func walk<V: HeistPlanTraversalVisitor>(
        _ conditional: ConditionalStep,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        let conditionalContext = context.child(path: "\(context.path).conditional")
        visitor.visitConditional(conditional, context: conditionalContext)
        walk(cases: conditional.cases, elseBody: conditional.elseBody, branchContext: conditionalContext, visitor: &visitor)
    }

    private func walk<V: HeistPlanTraversalVisitor>(
        _ waitForCases: WaitForCasesStep,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        let waitForContext = context.child(path: "\(context.path).wait_for_cases")
        visitor.visitWaitForCases(waitForCases, context: waitForContext)
        walk(cases: waitForCases.cases, elseBody: waitForCases.elseBody, branchContext: waitForContext, visitor: &visitor)
    }

    private func walk<V: HeistPlanTraversalVisitor>(
        _ forEach: ForEachElementStep,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        let forEachContext = context.child(path: "\(context.path).for_each_element")
        visitor.visitForEachElement(forEach, context: forEachContext)
        walk(
            steps: forEach.body,
            path: "\(forEachContext.path).body",
            depth: context.depth + 1,
            allowsCollectionLoops: false,
            scope: context.scope.bindingTarget(forEach.parameter),
            environment: context.environment.binding(target: .predicate(forEach.matching), to: forEach.parameter),
            definitionScope: context.definitionScope,
            invocationStack: context.invocationStack,
            visitor: &visitor
        )
    }

    private func walk<V: HeistPlanTraversalVisitor>(
        _ forEach: ForEachStringStep,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        let forEachContext = context.child(path: "\(context.path).for_each_string")
        visitor.visitForEachString(forEach, context: forEachContext)
        walk(
            steps: forEach.body,
            path: "\(forEachContext.path).body",
            depth: context.depth + 1,
            allowsCollectionLoops: false,
            scope: context.scope.bindingString(forEach.parameter),
            environment: context.environment.binding(string: forEach.values.first ?? "", to: forEach.parameter),
            definitionScope: context.definitionScope,
            invocationStack: context.invocationStack,
            visitor: &visitor
        )
    }

    private func walkInlineHeist<V: HeistPlanTraversalVisitor>(
        _ plan: HeistPlan,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        let heistContext = context.child(
            path: "\(context.path).heist",
            definitionScope: HeistDefinitionScope(definitions: plan.definitions)
        )
        visitor.visitHeist(plan, context: heistContext)
        walkDefinitions(
            plan.definitions,
            path: "\(heistContext.path).definitions",
            depth: context.depth + 1,
            definitionScope: heistContext.definitionScope,
            parentContext: heistContext,
            visitor: &visitor
        )
        walk(
            steps: plan.body,
            path: "\(heistContext.path).body",
            depth: context.depth + 1,
            allowsCollectionLoops: context.allowsCollectionLoops,
            scope: context.scope,
            environment: context.environment,
            definitionScope: heistContext.definitionScope,
            invocationStack: context.invocationStack,
            visitor: &visitor
        )
    }

    private func walkInvocation<V: HeistPlanTraversalVisitor>(
        _ invoke: HeistInvocationStep,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        let invokeContext = context.child(path: "\(context.path).invoke")
        visitor.visitInvoke(invoke, context: invokeContext)
        guard let resolved = context.definitionScope.resolve(path: invoke.path) else { return }
        let resolvedName = resolved.qualifiedName
        guard !context.invocationStack.contains(resolvedName),
              let environment = try? context.environment.binding(argument: invoke.argument, to: resolved.definition.parameter)
        else { return }
        walk(
            steps: resolved.definition.body,
            path: "\(invokeContext.path).body",
            depth: context.depth + 1,
            allowsCollectionLoops: context.allowsCollectionLoops,
            scope: context.scope.binding(parameter: resolved.definition.parameter),
            environment: environment,
            definitionScope: HeistDefinitionScope(definitions: resolved.definition.definitions, pathPrefix: resolved.namePath),
            invocationStack: context.invocationStack + [resolvedName],
            visitor: &visitor
        )
    }

    private func walk<V: HeistPlanTraversalVisitor>(
        cases: [PredicateCase],
        elseBody: [HeistStep]?,
        branchContext: HeistTraversalContext,
        visitor: inout V
    ) {
        for (index, predicateCase) in cases.enumerated() {
            let caseContext = branchContext.nestedBranch(path: "\(branchContext.path).cases[\(index)]", stepIndex: index)
            visitor.visitPredicateCase(predicateCase, context: caseContext)
            walk(
                steps: predicateCase.body,
                path: "\(caseContext.path).body",
                depth: branchContext.depth + 1,
                allowsCollectionLoops: false,
                scope: branchContext.scope,
                environment: branchContext.environment,
                definitionScope: branchContext.definitionScope,
                invocationStack: branchContext.invocationStack,
                visitor: &visitor
            )
        }
        if let elseBody {
            let elseContext = branchContext.nestedBranch(path: "\(branchContext.path).else_body", stepIndex: nil)
            visitor.visitElseBody(elseBody, context: elseContext)
            walk(
                steps: elseBody,
                path: elseContext.path,
                depth: branchContext.depth + 1,
                allowsCollectionLoops: false,
                scope: branchContext.scope,
                environment: branchContext.environment,
                definitionScope: branchContext.definitionScope,
                invocationStack: branchContext.invocationStack,
                visitor: &visitor
            )
        }
    }

    private func walkDefinitions<V: HeistPlanTraversalVisitor>(
        _ definitions: [HeistPlan],
        path: String,
        depth: Int,
        definitionScope: HeistDefinitionScope,
        parentContext: HeistTraversalContext,
        visitor: inout V
    ) {
        visitor.visitDefinitions(definitions, context: parentContext.child(path: path, depth: depth))
        for (index, definition) in definitions.enumerated() {
            let currentDefinitionPath = definitionScope.pathPrefix + [definition.name ?? ""]
            let currentDefinitionName = currentDefinitionPath.joined(separator: ".")
            var scope = HeistReferenceScope.empty
            var environment = HeistExecutionEnvironment.empty
            if let parameterName = definition.parameter.name {
                scope = scope.binding(parameter: definition.parameter)
                switch definition.parameter {
                case .none:
                    break
                case .strings:
                    environment = environment.binding(string: "__heist_parameter__", to: parameterName)
                case .elementTarget:
                    environment = environment.binding(target: .predicate(.identifier("__heist_parameter__")), to: parameterName)
                }
            }
            let definitionContext = HeistTraversalContext(
                path: "\(path)[\(index)]",
                depth: depth,
                stepIndex: nil,
                nextStep: nil,
                allowsCollectionLoops: true,
                scope: scope,
                environment: environment,
                definitionScope: definitionScope,
                invocationStack: []
            )
            visitor.visitDefinition(definition, context: definitionContext)
            walkDefinitions(
                definition.definitions,
                path: "\(definitionContext.path).definitions",
                depth: depth + 1,
                definitionScope: HeistDefinitionScope(definitions: definition.definitions, pathPrefix: currentDefinitionPath),
                parentContext: definitionContext,
                visitor: &visitor
            )
            walk(
                steps: definition.body,
                path: "\(definitionContext.path).body",
                depth: depth + 1,
                allowsCollectionLoops: true,
                scope: scope,
                environment: environment,
                definitionScope: HeistDefinitionScope(definitions: definition.definitions, pathPrefix: currentDefinitionPath),
                invocationStack: [currentDefinitionName],
                visitor: &visitor
            )
        }
    }
}

extension HeistTraversalContext {
    func child(
        path: String,
        depth: Int? = nil,
        definitionScope: HeistDefinitionScope? = nil
    ) -> HeistTraversalContext {
        HeistTraversalContext(
            path: path,
            depth: depth ?? self.depth,
            stepIndex: stepIndex,
            nextStep: nextStep,
            allowsCollectionLoops: allowsCollectionLoops,
            scope: scope,
            environment: environment,
            definitionScope: definitionScope ?? self.definitionScope,
            invocationStack: invocationStack
        )
    }

    func nestedBranch(path: String, stepIndex: Int?) -> HeistTraversalContext {
        HeistTraversalContext(
            path: path,
            depth: depth + 1,
            stepIndex: stepIndex,
            nextStep: nil,
            allowsCollectionLoops: false,
            scope: scope,
            environment: environment,
            definitionScope: definitionScope,
            invocationStack: invocationStack
        )
    }
}

struct HeistReferenceScope {
    static let empty = HeistReferenceScope()

    var targetRefs: Set<HeistReferenceName> = []
    var stringRefs: Set<HeistReferenceName> = []

    func bindingTarget(_ reference: HeistReferenceName) -> HeistReferenceScope {
        var copy = self
        copy.targetRefs.insert(reference)
        return copy
    }

    func bindingString(_ reference: HeistReferenceName) -> HeistReferenceScope {
        var copy = self
        copy.stringRefs.insert(reference)
        return copy
    }

    func binding(parameter: HeistParameter) -> HeistReferenceScope {
        guard let reference = parameter.name else { return self }
        switch parameter {
        case .none:
            return self
        case .strings:
            return bindingString(reference)
        case .elementTarget:
            return bindingTarget(reference)
        }
    }
}

struct HeistDefinitionScope {
    let definitions: [HeistPlan]
    let pathPrefix: [String]

    init(definitions: [HeistPlan], pathPrefix: [String] = []) {
        self.definitions = definitions
        self.pathPrefix = pathPrefix
    }

    func resolve(path: [String]) -> ResolvedHeistDefinition? {
        guard let first = path.first else { return nil }
        guard let direct = definitions.first(where: { $0.name == first }) else { return nil }
        return resolve(
            remaining: Array(path.dropFirst()),
            definition: direct,
            namePath: pathPrefix + [first]
        )
    }

    private func resolve(
        remaining: [String],
        definition: HeistPlan,
        namePath: [String]
    ) -> ResolvedHeistDefinition? {
        guard let next = remaining.first else {
            return ResolvedHeistDefinition(definition: definition, qualifiedName: namePath.joined(separator: "."), namePath: namePath)
        }
        guard let child = definition.definitions.first(where: { $0.name == next }) else { return nil }
        return resolve(
            remaining: Array(remaining.dropFirst()),
            definition: child,
            namePath: namePath + [next]
        )
    }
}

struct ResolvedHeistDefinition {
    let definition: HeistPlan
    let qualifiedName: String
    let namePath: [String]
}

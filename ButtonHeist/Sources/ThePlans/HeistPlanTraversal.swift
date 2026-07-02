import Foundation

enum HeistTraversalPathField: String, Sendable {
    case action
    case argument
    case body
    case cases
    case command
    case conditional
    case definitions
    case elseBody = "else_body"
    case expectation
    case fail
    case forEachElement = "for_each_element"
    case forEachString = "for_each_string"
    case heist
    case invoke
    case limit
    case matching
    case message
    case name
    case parameter
    case path
    case predicate
    case repeatUntil = "repeat_until"
    case target
    case timeout
    case value
    case values
    case wait
    case warn
    case withoutExpectation = "without_expectation"
}

struct HeistTraversalPath: Sendable, Equatable, Hashable, CustomStringConvertible {
    static let root = HeistTraversalPath(description: "$")

    let description: String

    private init(description: String) {
        self.description = description
    }

    func child(_ field: HeistTraversalPathField) -> HeistTraversalPath {
        HeistTraversalPath(description: "\(description).\(field.rawValue)")
    }

    func index(_ index: Int) -> HeistTraversalPath {
        HeistTraversalPath(description: "\(description)[\(index)]")
    }
}

struct HeistTraversalContext {
    let path: HeistTraversalPath
    let depth: Int
    let stepIndex: Int?
    let nextStep: HeistStep?
    let referenceBindings: HeistReferenceBindingContext
    let definitionScope: HeistDefinitionScope
    let rootDefinitionScope: HeistDefinitionScope
    let invocationStack: [HeistCallGraph.Node]
    let callGraph: HeistCallGraph?

    var scope: HeistReferenceScope {
        referenceBindings.scope
    }

    var environment: HeistExecutionEnvironment {
        referenceBindings.environment
    }
}

protocol HeistPlanTraversalVisitor {
    mutating func visitPlan(_ plan: HeistPlan, context: HeistTraversalContext)
    mutating func visitDefinitions(_ definitions: [HeistPlan], context: HeistTraversalContext)
    mutating func visitDefinition(_ plan: HeistPlan, context: HeistTraversalContext)
    mutating func visitStep(_ step: HeistStep, context: HeistTraversalContext)
    mutating func visitAction(_ action: ActionStep, context: HeistTraversalContext)
    mutating func visitWait(_ wait: WaitStep, context: HeistTraversalContext)
    mutating func visitConditional(_ conditional: ConditionalStep, context: HeistTraversalContext)
    mutating func visitPredicateCase(_ predicateCase: PredicateCase, context: HeistTraversalContext)
    mutating func visitElseBody(_ body: [HeistStep], context: HeistTraversalContext)
    mutating func visitForEachElement(_ step: ForEachElementStep, context: HeistTraversalContext)
    mutating func visitForEachString(_ step: ForEachStringStep, context: HeistTraversalContext)
    mutating func visitRepeatUntil(_ step: RepeatUntilStep, context: HeistTraversalContext)
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
    mutating func visitPredicateCase(_ predicateCase: PredicateCase, context: HeistTraversalContext) {}
    mutating func visitElseBody(_ body: [HeistStep], context: HeistTraversalContext) {}
    mutating func visitForEachElement(_ step: ForEachElementStep, context: HeistTraversalContext) {}
    mutating func visitForEachString(_ step: ForEachStringStep, context: HeistTraversalContext) {}
    mutating func visitRepeatUntil(_ step: RepeatUntilStep, context: HeistTraversalContext) {}
    mutating func visitWarn(_ warn: WarnStep, context: HeistTraversalContext) {}
    mutating func visitFail(_ fail: FailStep, context: HeistTraversalContext) {}
    mutating func visitHeist(_ plan: HeistPlan, context: HeistTraversalContext) {}
    mutating func visitInvoke(_ step: HeistInvocationStep, context: HeistTraversalContext) {}
}

struct HeistPlanTraversal {
    let callGraph: HeistCallGraph?

    init(callGraph: HeistCallGraph? = nil) {
        self.callGraph = callGraph
    }

    func walk<V: HeistPlanTraversalVisitor>(
        _ plan: HeistPlan,
        visitor: inout V
    ) {
        let callGraph = callGraph ?? HeistCallGraph(plan: plan)
        let rootBindings = plan.parameterReferenceBindings
        let rootDefinitionScope = HeistDefinitionScope(definitions: plan.definitions)
        let context = HeistTraversalContext(
            path: .root,
            depth: 0,
            stepIndex: nil,
            nextStep: nil,
            referenceBindings: rootBindings,
            definitionScope: rootDefinitionScope,
            rootDefinitionScope: rootDefinitionScope,
            invocationStack: [],
            callGraph: callGraph
        )
        visitor.visitPlan(plan, context: context)
        walkDefinitions(
            plan.definitions,
            path: .root.child(.definitions),
            depth: 1,
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            parentContext: context,
            visitor: &visitor
        )
        walk(
            steps: plan.body,
            path: .root.child(.body),
            depth: 1,
            referenceBindings: rootBindings,
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: [],
            callGraph: callGraph,
            visitor: &visitor
        )
    }

    func walk<V: HeistPlanTraversalVisitor>(
        steps: [HeistStep],
        path: HeistTraversalPath,
        depth: Int,
        referenceBindings: HeistReferenceBindingContext,
        definitionScope: HeistDefinitionScope,
        rootDefinitionScope: HeistDefinitionScope,
        invocationStack: [HeistCallGraph.Node] = [],
        callGraph: HeistCallGraph? = nil,
        visitor: inout V
    ) {
        for (index, step) in steps.enumerated() {
            let context = HeistTraversalContext(
                path: path.index(index),
                depth: depth,
                stepIndex: index,
                nextStep: steps.dropFirst(index + 1).first,
                referenceBindings: referenceBindings,
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope,
                invocationStack: invocationStack,
                callGraph: callGraph
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
            let actionContext = context.child(path: context.path.child(.action))
            visitor.visitAction(action, context: actionContext)
            if let expectation = action.expectationPolicy.expectedStep {
                visitor.visitWait(
                    expectation,
                    context: actionContext.child(path: actionContext.path.child(.expectation))
                )
            }
        case .wait(let wait):
            walk(wait, context: context, visitor: &visitor)
        case .conditional(let conditional):
            walk(conditional, context: context, visitor: &visitor)
        case .forEachElement(let forEach):
            walk(forEach, context: context, visitor: &visitor)
        case .forEachString(let forEach):
            walk(forEach, context: context, visitor: &visitor)
        case .repeatUntil(let repeatUntil):
            walk(repeatUntil, context: context, visitor: &visitor)
        case .warn(let warn):
            visitor.visitWarn(warn, context: context.child(path: context.path.child(.warn)))
        case .fail(let fail):
            visitor.visitFail(fail, context: context.child(path: context.path.child(.fail)))
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
        let conditionalContext = context.child(path: context.path.child(.conditional))
        visitor.visitConditional(conditional, context: conditionalContext)
        walk(cases: conditional.cases, elseBody: conditional.elseBody, branchContext: conditionalContext, visitor: &visitor)
    }

    private func walk<V: HeistPlanTraversalVisitor>(
        _ wait: WaitStep,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        let waitContext = context.child(path: context.path.child(.wait))
        visitor.visitWait(wait, context: waitContext)
        guard let elseBody = wait.elseBody else { return }
        let elseContext = waitContext.child(path: waitContext.path.child(.elseBody))
        visitor.visitElseBody(elseBody, context: elseContext)
        walk(
            steps: elseBody,
            path: elseContext.path,
            depth: context.depth + 1,
            referenceBindings: context.referenceBindings,
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: context.invocationStack,
            callGraph: context.callGraph,
            visitor: &visitor
        )
    }

    private func walk<V: HeistPlanTraversalVisitor>(
        _ forEach: ForEachElementStep,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        let forEachContext = context.child(path: context.path.child(.forEachElement))
        visitor.visitForEachElement(forEach, context: forEachContext)
        walk(
            steps: forEach.body,
            path: forEachContext.path.child(.body),
            depth: context.depth + 1,
            referenceBindings: context.referenceBindings.binding(
                target: .predicate(forEach.matching),
                to: forEach.parameter
            ),
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: context.invocationStack,
            callGraph: context.callGraph,
            visitor: &visitor
        )
    }

    private func walk<V: HeistPlanTraversalVisitor>(
        _ forEach: ForEachStringStep,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        let forEachContext = context.child(path: context.path.child(.forEachString))
        visitor.visitForEachString(forEach, context: forEachContext)
        walk(
            steps: forEach.body,
            path: forEachContext.path.child(.body),
            depth: context.depth + 1,
            referenceBindings: context.referenceBindings.binding(
                string: forEach.values.first ?? "",
                to: forEach.parameter
            ),
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: context.invocationStack,
            callGraph: context.callGraph,
            visitor: &visitor
        )
    }

    private func walk<V: HeistPlanTraversalVisitor>(
        _ repeatUntil: RepeatUntilStep,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        let repeatContext = context.child(path: context.path.child(.repeatUntil))
        visitor.visitRepeatUntil(repeatUntil, context: repeatContext)
        visitor.visitWait(
            WaitStep(predicate: repeatUntil.predicate, timeout: repeatUntil.timeout),
            context: repeatContext.child(path: repeatContext.path.child(.predicate))
        )
        walk(
            steps: repeatUntil.body,
            path: repeatContext.path.child(.body),
            depth: context.depth + 1,
            referenceBindings: context.referenceBindings,
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: context.invocationStack,
            callGraph: context.callGraph,
            visitor: &visitor
        )
        guard let elseBody = repeatUntil.elseBody else { return }
        let elseContext = repeatContext.child(path: repeatContext.path.child(.elseBody))
        visitor.visitElseBody(elseBody, context: elseContext)
        walk(
            steps: elseBody,
            path: elseContext.path,
            depth: context.depth + 1,
            referenceBindings: context.referenceBindings,
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: context.invocationStack,
            callGraph: context.callGraph,
            visitor: &visitor
        )
    }

    private func walkInlineHeist<V: HeistPlanTraversalVisitor>(
        _ plan: HeistPlan,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        let inlineDefinitionScope = HeistDefinitionScope(definitions: plan.definitions)
        let heistContext = context.child(
            path: context.path.child(.heist),
            definitionScope: inlineDefinitionScope,
            rootDefinitionScope: inlineDefinitionScope
        )
        visitor.visitHeist(plan, context: heistContext)
        walkDefinitions(
            plan.definitions,
            path: heistContext.path.child(.definitions),
            depth: context.depth + 1,
            definitionScope: heistContext.definitionScope,
            rootDefinitionScope: heistContext.rootDefinitionScope,
            parentContext: heistContext,
            visitor: &visitor
        )
        walk(
            steps: plan.body,
            path: heistContext.path.child(.body),
            depth: context.depth + 1,
            referenceBindings: context.referenceBindings,
            definitionScope: heistContext.definitionScope,
            rootDefinitionScope: heistContext.rootDefinitionScope,
            invocationStack: context.invocationStack,
            callGraph: context.callGraph,
            visitor: &visitor
        )
    }

    private func walkInvocation<V: HeistPlanTraversalVisitor>(
        _ invoke: HeistInvocationStep,
        context: HeistTraversalContext,
        visitor: inout V
    ) {
        let invokeContext = context.child(path: context.path.child(.invoke))
        visitor.visitInvoke(invoke, context: invokeContext)
        if let expectation = invoke.expectation {
            visitor.visitWait(
                expectation,
                context: invokeContext.child(path: invokeContext.path.child(.expectation))
            )
        }
        guard let resolved = context.resolveInvocation(path: invoke.invocationPath) else { return }
        let resolvedNode = resolved.callGraphNode
        guard context.callGraphCycle(closing: resolvedNode) == nil,
              let referenceBindings = try? context.referenceBindings.binding(
                argument: invoke.argument,
                to: resolved.definition.parameter
              )
        else { return }
        walk(
            steps: resolved.definition.body,
            path: invokeContext.path.child(.body),
            depth: context.depth + 1,
            referenceBindings: referenceBindings,
            definitionScope: HeistDefinitionScope(definitions: resolved.definition.definitions, pathPrefix: resolved.namePath),
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: context.invocationStack + [resolvedNode],
            callGraph: context.callGraph,
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
            let caseContext = branchContext.nestedBranch(
                path: branchContext.path.child(.cases).index(index),
                stepIndex: index
            )
            visitor.visitPredicateCase(predicateCase, context: caseContext)
            walk(
                steps: predicateCase.body,
                path: caseContext.path.child(.body),
                depth: branchContext.depth + 1,
                referenceBindings: branchContext.referenceBindings,
                definitionScope: branchContext.definitionScope,
                rootDefinitionScope: branchContext.rootDefinitionScope,
                invocationStack: branchContext.invocationStack,
                callGraph: branchContext.callGraph,
                visitor: &visitor
            )
        }
        if let elseBody {
            let elseContext = branchContext.nestedBranch(path: branchContext.path.child(.elseBody), stepIndex: nil)
            visitor.visitElseBody(elseBody, context: elseContext)
            walk(
                steps: elseBody,
                path: elseContext.path,
                depth: branchContext.depth + 1,
                referenceBindings: branchContext.referenceBindings,
                definitionScope: branchContext.definitionScope,
                rootDefinitionScope: branchContext.rootDefinitionScope,
                invocationStack: branchContext.invocationStack,
                callGraph: branchContext.callGraph,
                visitor: &visitor
            )
        }
    }

    private func walkDefinitions<V: HeistPlanTraversalVisitor>(
        _ definitions: [HeistPlan],
        path: HeistTraversalPath,
        depth: Int,
        definitionScope: HeistDefinitionScope,
        rootDefinitionScope: HeistDefinitionScope,
        parentContext: HeistTraversalContext,
        visitor: inout V
    ) {
        visitor.visitDefinitions(definitions, context: parentContext.child(path: path, depth: depth))
        for (index, definition) in definitions.enumerated() {
            let currentDefinitionPath = definitionScope.pathPrefix + [definition.name ?? ""]
            let currentDefinitionNode = HeistCallGraph.Node(namePath: currentDefinitionPath)
            let referenceBindings = definition.parameterReferenceBindings
            let definitionContext = HeistTraversalContext(
                path: path.index(index),
                depth: depth,
                stepIndex: nil,
                nextStep: nil,
                referenceBindings: referenceBindings,
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope,
                invocationStack: [],
                callGraph: parentContext.callGraph
            )
            visitor.visitDefinition(definition, context: definitionContext)
            walkDefinitions(
                definition.definitions,
                path: definitionContext.path.child(.definitions),
                depth: depth + 1,
                definitionScope: HeistDefinitionScope(definitions: definition.definitions, pathPrefix: currentDefinitionPath),
                rootDefinitionScope: rootDefinitionScope,
                parentContext: definitionContext,
                visitor: &visitor
            )
            walk(
                steps: definition.body,
                path: definitionContext.path.child(.body),
                depth: depth + 1,
                referenceBindings: referenceBindings,
                definitionScope: HeistDefinitionScope(definitions: definition.definitions, pathPrefix: currentDefinitionPath),
                rootDefinitionScope: rootDefinitionScope,
                invocationStack: [currentDefinitionNode],
                callGraph: parentContext.callGraph,
                visitor: &visitor
            )
        }
    }
}

extension HeistTraversalContext {
    func child(
        path: HeistTraversalPath,
        depth: Int? = nil,
        definitionScope: HeistDefinitionScope? = nil,
        rootDefinitionScope: HeistDefinitionScope? = nil
    ) -> HeistTraversalContext {
        HeistTraversalContext(
            path: path,
            depth: depth ?? self.depth,
            stepIndex: stepIndex,
            nextStep: nextStep,
            referenceBindings: referenceBindings,
            definitionScope: definitionScope ?? self.definitionScope,
            rootDefinitionScope: rootDefinitionScope ?? self.rootDefinitionScope,
            invocationStack: invocationStack,
            callGraph: callGraph
        )
    }

    func nestedBranch(path: HeistTraversalPath, stepIndex: Int?) -> HeistTraversalContext {
        HeistTraversalContext(
            path: path,
            depth: depth + 1,
            stepIndex: stepIndex,
            nextStep: nil,
            referenceBindings: referenceBindings,
            definitionScope: definitionScope,
            rootDefinitionScope: rootDefinitionScope,
            invocationStack: invocationStack,
            callGraph: callGraph
        )
    }

    func resolveInvocation(path: HeistInvocationPath) -> ResolvedHeistDefinition? {
        definitionScope.resolveInvocation(path: path, rootScope: rootDefinitionScope)
    }

    func callGraphCycle(closing resolvedNode: HeistCallGraph.Node) -> HeistCallGraph.Cycle? {
        let cycle = callGraph?.nodeCycle(closing: resolvedNode, in: invocationStack)
            ?? HeistCallGraph.nodeCycle(closing: resolvedNode, in: invocationStack)
        return cycle.map(HeistCallGraph.Cycle.init)
    }
}

struct HeistDefinitionScope {
    let definitions: [HeistPlan]
    let pathPrefix: [String]

    init(definitions: [HeistPlan], pathPrefix: [String] = []) {
        self.definitions = definitions
        self.pathPrefix = pathPrefix
    }

    func resolve(path: HeistInvocationPath) -> ResolvedHeistDefinition? {
        guard let first = path.components.first else { return nil }
        guard let direct = definitions.first(where: { $0.name == first }) else { return nil }
        return resolve(
            remaining: Array(path.components.dropFirst()),
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
            return ResolvedHeistDefinition(
                definition: definition,
                invocationPath: HeistInvocationPath.preconditionValidated(components: namePath)
            )
        }
        guard let child = definition.definitions.first(where: { $0.name == next }) else { return nil }
        return resolve(
            remaining: Array(remaining.dropFirst()),
            definition: child,
            namePath: namePath + [next]
        )
    }

    func resolveInvocation(path: HeistInvocationPath, rootScope: HeistDefinitionScope) -> ResolvedHeistDefinition? {
        if let local = resolve(path: path) {
            return local
        }
        guard path.components.count > 1 else { return nil }
        return rootScope.resolve(path: path)
    }
}

struct ResolvedHeistDefinition {
    let definition: HeistPlan
    let invocationPath: HeistInvocationPath

    var qualifiedName: String {
        invocationPath.dottedName
    }

    var namePath: [String] {
        invocationPath.components
    }

    var callGraphNode: HeistCallGraph.Node {
        HeistCallGraph.Node(namePath: namePath)
    }
}

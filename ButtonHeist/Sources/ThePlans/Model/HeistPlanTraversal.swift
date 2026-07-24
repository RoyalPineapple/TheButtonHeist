import Foundation

public struct HeistPlanPath: Sendable, Equatable, Hashable, CustomStringConvertible {
    enum Field: String, Sendable {
        case action, actions, actionName, after, argument, assertions, before, body, cases, change, changed, checks
        case command, conditional, container, customContent, definitions, element, expectation, fail, heist, hint
        case identifier, include, invoke, label, limit, match, matching, message, name, ordinal, parameter, path
        case payload, predicate, rotor, rotors, semantic, start, target, text, timeout, value, values, wait, warn
        case elseBody = "else_body"
        case exclude
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
        case repeatUntil = "repeat_until"
        case textRef = "text_ref"
        case withoutExpectation = "without_expectation"
    }

    private enum Component: Sendable, Equatable, Hashable {
        case field(Field)
        case index(Int)
    }

    public static let root = Self(components: [])
    private let components: [Component]

    public var description: String {
        components.reduce(into: "$") { result, component in
            switch component {
            case .field(let field): result += ".\(field.rawValue)"
            case .index(let index): result += "[\(index)]"
            }
        }
    }

    func child(_ field: Field) -> Self {
        Self(components: components + [.field(field)])
    }

    func index(_ index: Int) -> Self {
        Self(components: components + [.index(index)])
    }

    func ends(in field: Field) -> Bool {
        components.last == .field(field)
    }

    func contains(_ field: Field, followedBy nextField: Field) -> Bool {
        zip(components, components.dropFirst()).contains {
            $0 == .field(field) && $1 == .field(nextField)
        }
    }
}

struct HeistTraversalContext {
    let path: HeistPlanPath
    let depth: Int
    let stepIndex: Int?
    let nextStep: HeistStep?
    let referenceBindings: HeistReferenceBindingContext
    let bindingSamples: [HeistTraversalBindingSample]
    let definitionScope: HeistDefinitionScope
    let rootDefinitionScope: HeistDefinitionScope
    let invocationStack: [HeistInvocationPath]

    var scope: HeistReferenceScope {
        referenceBindings.scope
    }

    var environment: HeistExecutionEnvironment {
        referenceBindings.environment
    }
}

struct HeistTraversalBindingSample {
    let referenceBindings: HeistReferenceBindingContext
    let sourcePath: HeistPlanPath

    var environment: HeistExecutionEnvironment {
        referenceBindings.environment
    }

    func binding(string: String, to parameter: HeistReferenceName) -> Self {
        Self(
            referenceBindings: referenceBindings.binding(string: string, to: parameter),
            sourcePath: sourcePath
        )
    }

    func binding(target: ResolvedAccessibilityTarget, to parameter: HeistReferenceName) -> Self {
        Self(
            referenceBindings: referenceBindings.binding(target: target, to: parameter),
            sourcePath: sourcePath
        )
    }
}

struct HeistPlanTraversal {
    enum CatalogHeistKind {
        case entry(HeistPlanName?)
        case capability([HeistPlanName])
    }

    struct CatalogHeistProjection {
        let plan: HeistPlan
        let kind: CatalogHeistKind
        let context: HeistTraversalContext

        var definitionComponents: [HeistPlanName] {
            switch kind {
            case .entry:
                return []
            case .capability(let components):
                return components
            }
        }
    }

    enum LintObservation {
        case step(HeistStep, context: HeistTraversalContext)
        case action(ActionStep, context: HeistTraversalContext)
        case predicateCase(PredicateCase, context: HeistTraversalContext)
        case elseBody([HeistStep], context: HeistTraversalContext)
    }

    enum RuntimeValidationObservation {
        case plan(HeistPlan, context: HeistTraversalContext, requiresName: Bool)
        case definitions([HeistPlan], context: HeistTraversalContext)
        case step(HeistStep, context: HeistTraversalContext)
        case action(ActionStep, context: HeistTraversalContext)
        case wait(WaitStep, context: HeistTraversalContext)
        case predicateCase(PredicateCase, context: HeistTraversalContext)
        case forEachElement(ForEachElementStep, context: HeistTraversalContext)
        case forEachString(ForEachStringStep, context: HeistTraversalContext)
        case repeatUntil(RepeatUntilStep, context: HeistTraversalContext)
        case warn(WarnStep, context: HeistTraversalContext)
        case fail(FailStep, context: HeistTraversalContext)
        case heist(HeistPlan, context: HeistTraversalContext)
        case invoke(HeistInvocationStep, context: HeistTraversalContext)
    }

    enum SemanticSurfaceObservation {
        case action(ActionStep)
        case wait(WaitStep, context: HeistTraversalContext)
        case forEachElement(ForEachElementStep)
        case invoke(HeistInvocationStep, context: HeistTraversalContext)
    }

    enum Event {
        case enterPlan(HeistPlan, context: HeistTraversalContext)
        case leavePlan(HeistPlan, context: HeistTraversalContext)
        case enterDefinitions([HeistPlan], context: HeistTraversalContext)
        case leaveDefinitions([HeistPlan], context: HeistTraversalContext)
        case enterDefinition(HeistPlan, context: HeistTraversalContext)
        case leaveDefinition(HeistPlan, context: HeistTraversalContext)
        case enterSteps([HeistStep], context: HeistTraversalContext)
        case leaveSteps([HeistStep], context: HeistTraversalContext)
        case enterStep(HeistStep, context: HeistTraversalContext)
        case leaveStep(HeistStep, context: HeistTraversalContext)
        case action(ActionStep, context: HeistTraversalContext)
        case wait(WaitStep, context: HeistTraversalContext)
        case conditional(ConditionalStep, context: HeistTraversalContext)
        case predicateCase(PredicateCase, context: HeistTraversalContext)
        case elseBody([HeistStep], context: HeistTraversalContext)
        case forEachElement(ForEachElementStep, context: HeistTraversalContext)
        case forEachString(ForEachStringStep, context: HeistTraversalContext)
        case repeatUntil(RepeatUntilStep, context: HeistTraversalContext)
        case warn(WarnStep, context: HeistTraversalContext)
        case fail(FailStep, context: HeistTraversalContext)
        case heist(HeistPlan, context: HeistTraversalContext)
        case invoke(HeistInvocationStep, context: HeistTraversalContext)
    }

    let expandsInvocations: Bool

    init(expandsInvocations: Bool = true) {
        self.expandsInvocations = expandsInvocations
    }

    static func walk(
        _ step: HeistStep,
        observe: (Event) throws -> Void
    ) rethrows {
        let definitionScope = HeistDefinitionScope(definitions: [])
        let context = HeistTraversalContext(
            path: .root,
            depth: 0,
            stepIndex: nil,
            nextStep: nil,
            referenceBindings: .empty,
            bindingSamples: [],
            definitionScope: definitionScope,
            rootDefinitionScope: definitionScope,
            invocationStack: []
        )
        try HeistPlanTraversal(expandsInvocations: false).walk(
            step: step,
            context: context,
            observe: observe
        )
    }

    func walk(
        _ plan: HeistPlan,
        observe: (Event) throws -> Void
    ) rethrows {
        let rootBindings = plan.parameterReferenceBindings
        let rootDefinitionScope = HeistDefinitionScope(definitions: plan.definitions)
        let context = HeistTraversalContext(
            path: .root,
            depth: 0,
            stepIndex: nil,
            nextStep: nil,
            referenceBindings: rootBindings,
            bindingSamples: [],
            definitionScope: rootDefinitionScope,
            rootDefinitionScope: rootDefinitionScope,
            invocationStack: []
        )
        try observe(.enterPlan(plan, context: context))
        try walkDefinitions(
            plan.definitions,
            path: .root.child(.definitions),
            depth: 1,
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            parentContext: context,
            observe: observe
        )
        try walk(
            steps: plan.body,
            path: .root.child(.body),
            depth: 1,
            referenceBindings: rootBindings,
            bindingSamples: [],
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: [],
            observe: observe
        )
        try observe(.leavePlan(plan, context: context))
    }

    func walkCatalogHeists(
        _ plan: HeistPlan,
        observe: (CatalogHeistProjection) throws -> Void
    ) rethrows {
        try HeistPlanTraversal(expandsInvocations: false).walk(plan) { event in
            switch event {
            case .enterPlan(let plan, let context):
                try observe(CatalogHeistProjection(
                    plan: plan,
                    kind: .entry(plan.name),
                    context: context
                ))
            case .enterDefinition(let plan, let context):
                guard let localName = plan.name else {
                    preconditionFailure("admitted heist definitions must have names")
                }
                let nameComponents = context.definitionScope.pathPrefix + [localName]
                try observe(CatalogHeistProjection(
                    plan: plan,
                    kind: .capability(nameComponents),
                    context: context
                ))
            case .leavePlan,
                 .enterDefinitions,
                 .leaveDefinitions,
                 .leaveDefinition,
                 .enterSteps,
                 .leaveSteps,
                 .enterStep,
                 .leaveStep,
                 .action,
                 .wait,
                 .conditional,
                 .predicateCase,
                 .elseBody,
                 .forEachElement,
                 .forEachString,
                 .repeatUntil,
                 .warn,
                 .fail,
                 .heist,
                 .invoke:
                break
            }
        }
    }

    func walkLintObservations(
        _ plan: HeistPlan,
        observe: (LintObservation) throws -> Void
    ) rethrows {
        try walk(plan) { event in
            switch event {
            case .enterStep(let step, let context):
                try observe(.step(step, context: context))
            case .action(let action, let context):
                try observe(.action(action, context: context))
            case .predicateCase(let predicateCase, let context):
                try observe(.predicateCase(predicateCase, context: context))
            case .elseBody(let body, let context):
                try observe(.elseBody(body, context: context))
            case .enterPlan,
                 .leavePlan,
                 .enterDefinitions,
                 .leaveDefinitions,
                 .enterDefinition,
                 .leaveDefinition,
                 .enterSteps,
                 .leaveSteps,
                 .leaveStep,
                 .wait,
                 .conditional,
                 .forEachElement,
                 .forEachString,
                 .repeatUntil,
                 .warn,
                 .fail,
                 .heist,
                 .invoke:
                break
            }
        }
    }

    func walkRuntimeValidationObservations(
        _ plan: HeistPlan,
        observe: (RuntimeValidationObservation) throws -> Void
    ) rethrows {
        try walk(plan) { event in
            switch event {
            case .enterPlan(let plan, let context):
                try observe(.plan(plan, context: context, requiresName: false))
            case .enterDefinitions(let definitions, let context):
                try observe(.definitions(definitions, context: context))
            case .enterDefinition(let plan, let context):
                try observe(.plan(plan, context: context, requiresName: true))
            case .enterStep(let step, let context):
                try observe(.step(step, context: context))
            case .action(let action, let context):
                try observe(.action(action, context: context))
            case .wait(let wait, let context):
                try observe(.wait(wait, context: context))
            case .predicateCase(let predicateCase, let context):
                try observe(.predicateCase(predicateCase, context: context))
            case .forEachElement(let step, let context):
                try observe(.forEachElement(step, context: context))
            case .forEachString(let step, let context):
                try observe(.forEachString(step, context: context))
            case .repeatUntil(let step, let context):
                try observe(.repeatUntil(step, context: context))
            case .warn(let warn, let context):
                try observe(.warn(warn, context: context))
            case .fail(let failStep, let context):
                try observe(.fail(failStep, context: context))
            case .heist(let plan, let context):
                try observe(.heist(plan, context: context))
            case .invoke(let invocation, let context):
                try observe(.invoke(invocation, context: context))
            case .leavePlan,
                 .leaveDefinitions,
                 .leaveDefinition,
                 .enterSteps,
                 .leaveSteps,
                 .leaveStep,
                 .conditional,
                 .elseBody:
                break
            }
        }
    }

    func walkSemanticSurfaceObservations(
        steps: [HeistStep],
        path: HeistPlanPath,
        depth: Int,
        referenceBindings: HeistReferenceBindingContext,
        definitionScope: HeistDefinitionScope,
        rootDefinitionScope: HeistDefinitionScope,
        invocationStack: [HeistInvocationPath],
        observe: (SemanticSurfaceObservation) throws -> Void
    ) rethrows {
        try walk(
            steps: steps,
            path: path,
            depth: depth,
            referenceBindings: referenceBindings,
            definitionScope: definitionScope,
            rootDefinitionScope: rootDefinitionScope,
            invocationStack: invocationStack
        ) { event in
            switch event {
            case .action(let action, _):
                try observe(.action(action))
            case .wait(let wait, let context):
                try observe(.wait(wait, context: context))
            case .forEachElement(let step, _):
                try observe(.forEachElement(step))
            case .invoke(let invocation, let context):
                try observe(.invoke(invocation, context: context))
            case .enterPlan,
                 .leavePlan,
                 .enterDefinitions,
                 .leaveDefinitions,
                 .enterDefinition,
                 .leaveDefinition,
                 .enterSteps,
                 .leaveSteps,
                 .enterStep,
                 .leaveStep,
                 .conditional,
                 .predicateCase,
                 .elseBody,
                 .forEachString,
                 .repeatUntil,
                 .warn,
                 .fail,
                 .heist:
                break
            }
        }
    }

    func walk(
        steps: [HeistStep],
        path: HeistPlanPath,
        depth: Int,
        referenceBindings: HeistReferenceBindingContext,
        bindingSamples: [HeistTraversalBindingSample] = [],
        definitionScope: HeistDefinitionScope,
        rootDefinitionScope: HeistDefinitionScope,
        invocationStack: [HeistInvocationPath] = [],
        observe: (Event) throws -> Void
    ) rethrows {
        let bodyContext = HeistTraversalContext(
            path: path,
            depth: depth,
            stepIndex: nil,
            nextStep: nil,
            referenceBindings: referenceBindings,
            bindingSamples: bindingSamples,
            definitionScope: definitionScope,
            rootDefinitionScope: rootDefinitionScope,
            invocationStack: invocationStack
        )
        try observe(.enterSteps(steps, context: bodyContext))
        for (index, step) in steps.enumerated() {
            let context = HeistTraversalContext(
                path: path.index(index),
                depth: depth,
                stepIndex: index,
                nextStep: index + 1 < steps.count ? steps[index + 1] : nil,
                referenceBindings: referenceBindings,
                bindingSamples: bindingSamples,
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope,
                invocationStack: invocationStack
            )
            try walk(step: step, context: context, observe: observe)
        }
        try observe(.leaveSteps(steps, context: bodyContext))
    }

    private func walk(
        step: HeistStep,
        context: HeistTraversalContext,
        observe: (Event) throws -> Void
    ) rethrows {
        try observe(.enterStep(step, context: context))
        switch step {
        case .action(let action):
            let actionContext = context.child(path: context.path.child(.action))
            try observe(.action(action, context: actionContext))
            if let expectation = action.expectationPolicy.expectedStep {
                try observe(.wait(
                    expectation,
                    context: actionContext.child(path: actionContext.path.child(.expectation))
                ))
            }
        case .wait(let wait):
            try walk(wait, context: context, observe: observe)
        case .conditional(let conditional):
            try walk(conditional, context: context, observe: observe)
        case .forEachElement(let forEach):
            try walk(forEach, context: context, observe: observe)
        case .forEachString(let forEach):
            try walk(forEach, context: context, observe: observe)
        case .repeatUntil(let repeatUntil):
            try walk(repeatUntil, context: context, observe: observe)
        case .warn(let warn):
            try observe(.warn(warn, context: context.child(path: context.path.child(.warn))))
        case .fail(let fail):
            try observe(.fail(fail, context: context.child(path: context.path.child(.fail))))
        case .heist(let plan):
            try walkInlineHeist(plan, context: context, observe: observe)
        case .invoke(let invoke):
            try walkInvocation(invoke, context: context, observe: observe)
        }
        try observe(.leaveStep(step, context: context))
    }

    private func walk(
        _ conditional: ConditionalStep,
        context: HeistTraversalContext,
        observe: (Event) throws -> Void
    ) rethrows {
        let conditionalContext = context.child(path: context.path.child(.conditional))
        try observe(.conditional(conditional, context: conditionalContext))
        try walk(
            cases: conditional.cases,
            elseBody: conditional.elseBody,
            branchContext: conditionalContext,
            observe: observe
        )
    }

    private func walk(
        _ wait: WaitStep,
        context: HeistTraversalContext,
        observe: (Event) throws -> Void
    ) rethrows {
        let waitContext = context.child(path: context.path.child(.wait))
        try observe(.wait(wait, context: waitContext))
        guard let elseBody = wait.elseBody else { return }
        let elseContext = waitContext.child(path: waitContext.path.child(.elseBody))
        try observe(.elseBody(elseBody, context: elseContext))
        try walk(
            steps: elseBody,
            path: elseContext.path,
            depth: context.depth + 1,
            referenceBindings: context.referenceBindings,
            bindingSamples: context.bindingSamples,
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: context.invocationStack,
            observe: observe
        )
    }

    private func walk(
        _ forEach: ForEachElementStep,
        context: HeistTraversalContext,
        observe: (Event) throws -> Void
    ) rethrows {
        let forEachContext = context.child(path: context.path.child(.forEachElement))
        try observe(.forEachElement(forEach, context: forEachContext))
        try walk(
            steps: forEach.body,
            path: forEachContext.path.child(.body),
            depth: context.depth + 1,
            referenceBindings: context.referenceBindings.binding(
                target: HeistReferenceBinding.runtimeSafetyAccessibilityTargetPlaceholder,
                to: forEach.parameter
            ),
            bindingSamples: context.bindingSamples.map {
                $0.binding(
                    target: HeistReferenceBinding.runtimeSafetyAccessibilityTargetPlaceholder,
                    to: forEach.parameter
                )
            },
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: context.invocationStack,
            observe: observe
        )
    }

    private func walk(
        _ forEach: ForEachStringStep,
        context: HeistTraversalContext,
        observe: (Event) throws -> Void
    ) rethrows {
        let forEachContext = context.child(path: context.path.child(.forEachString))
        try observe(.forEachString(forEach, context: forEachContext))
        let firstValue = forEach.values.first ?? ""
        let inheritedSamples = context.bindingSamples.map {
            $0.binding(string: firstValue, to: forEach.parameter)
        }
        let valueSamples = forEach.values.enumerated().map { index, value in
            HeistTraversalBindingSample(
                referenceBindings: context.referenceBindings.binding(string: value, to: forEach.parameter),
                sourcePath: forEachContext.path.child(.values).index(index)
            )
        }
        try walk(
            steps: forEach.body,
            path: forEachContext.path.child(.body),
            depth: context.depth + 1,
            referenceBindings: context.referenceBindings.binding(
                string: firstValue,
                to: forEach.parameter
            ),
            bindingSamples: inheritedSamples + valueSamples,
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: context.invocationStack,
            observe: observe
        )
    }

    private func walk(
        _ repeatUntil: RepeatUntilStep,
        context: HeistTraversalContext,
        observe: (Event) throws -> Void
    ) rethrows {
        let repeatContext = context.child(path: context.path.child(.repeatUntil))
        try observe(.repeatUntil(repeatUntil, context: repeatContext))
        try observe(.wait(
            WaitStep(predicate: repeatUntil.predicate, timeout: repeatUntil.timeout),
            context: repeatContext.child(path: repeatContext.path.child(.predicate))
        ))
        try walk(
            steps: repeatUntil.body,
            path: repeatContext.path.child(.body),
            depth: context.depth + 1,
            referenceBindings: context.referenceBindings,
            bindingSamples: context.bindingSamples,
            definitionScope: context.definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: context.invocationStack,
            observe: observe
        )
    }

    private func walkInlineHeist(
        _ plan: HeistPlan,
        context: HeistTraversalContext,
        observe: (Event) throws -> Void
    ) rethrows {
        let inlineDefinitionScope = HeistDefinitionScope(definitions: plan.definitions)
        let heistContext = context.child(
            path: context.path.child(.heist),
            definitionScope: inlineDefinitionScope,
            rootDefinitionScope: inlineDefinitionScope
        )
        try observe(.heist(plan, context: heistContext))
        try walkDefinitions(
            plan.definitions,
            path: heistContext.path.child(.definitions),
            depth: context.depth + 1,
            definitionScope: heistContext.definitionScope,
            rootDefinitionScope: heistContext.rootDefinitionScope,
            parentContext: heistContext,
            observe: observe
        )
        try walk(
            steps: plan.body,
            path: heistContext.path.child(.body),
            depth: context.depth + 1,
            referenceBindings: context.referenceBindings,
            bindingSamples: context.bindingSamples,
            definitionScope: heistContext.definitionScope,
            rootDefinitionScope: heistContext.rootDefinitionScope,
            invocationStack: context.invocationStack,
            observe: observe
        )
    }

    private func walkInvocation(
        _ invoke: HeistInvocationStep,
        context: HeistTraversalContext,
        observe: (Event) throws -> Void
    ) rethrows {
        let invokeContext = context.child(path: context.path.child(.invoke))
        try observe(.invoke(invoke, context: invokeContext))
        if let expectation = invoke.expectation {
            try observe(.wait(
                expectation,
                context: invokeContext.child(path: invokeContext.path.child(.expectation))
            ))
        }
        guard expandsInvocations else { return }
        guard let resolved = context.resolveInvocation(path: invoke.path) else { return }
        let resolvedNode = resolved.callGraphNode
        guard context.callGraphCycle(closing: resolvedNode) == nil,
              let referenceBindings = try? context.referenceBindings.binding(
                argument: invoke.argument,
                to: resolved.definition.parameter
              )
        else { return }
        try walk(
            steps: resolved.definition.body,
            path: invokeContext.path.child(.body),
            depth: context.depth + 1,
            referenceBindings: referenceBindings,
            bindingSamples: context.bindingSamples.compactMap { sample in
                try? HeistTraversalBindingSample(
                    referenceBindings: sample.referenceBindings.binding(
                        argument: invoke.argument,
                        to: resolved.definition.parameter
                    ),
                    sourcePath: sample.sourcePath
                )
            },
            definitionScope: HeistDefinitionScope(definitions: resolved.definition.definitions, pathPrefix: resolved.namePath),
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: context.invocationStack + [resolvedNode],
            observe: observe
        )
    }

    private func walk(
        cases: [PredicateCase],
        elseBody: [HeistStep]?,
        branchContext: HeistTraversalContext,
        observe: (Event) throws -> Void
    ) rethrows {
        for (index, predicateCase) in cases.enumerated() {
            let caseContext = branchContext.nestedBranch(
                path: branchContext.path.child(.cases).index(index),
                stepIndex: index
            )
            try observe(.predicateCase(predicateCase, context: caseContext))
            try walk(
                steps: predicateCase.body,
                path: caseContext.path.child(.body),
                depth: branchContext.depth + 1,
                referenceBindings: branchContext.referenceBindings,
                bindingSamples: branchContext.bindingSamples,
                definitionScope: branchContext.definitionScope,
                rootDefinitionScope: branchContext.rootDefinitionScope,
                invocationStack: branchContext.invocationStack,
                observe: observe
            )
        }
        if let elseBody {
            let elseContext = branchContext.nestedBranch(path: branchContext.path.child(.elseBody), stepIndex: nil)
            try observe(.elseBody(elseBody, context: elseContext))
            try walk(
                steps: elseBody,
                path: elseContext.path,
                depth: branchContext.depth + 1,
                referenceBindings: branchContext.referenceBindings,
                bindingSamples: branchContext.bindingSamples,
                definitionScope: branchContext.definitionScope,
                rootDefinitionScope: branchContext.rootDefinitionScope,
                invocationStack: branchContext.invocationStack,
                observe: observe
            )
        }
    }

    private func walkDefinitions(
        _ definitions: [HeistPlan],
        path: HeistPlanPath,
        depth: Int,
        definitionScope: HeistDefinitionScope,
        rootDefinitionScope: HeistDefinitionScope,
        parentContext: HeistTraversalContext,
        observe: (Event) throws -> Void
    ) rethrows {
        let definitionsContext = parentContext.child(path: path, depth: depth)
        try observe(.enterDefinitions(definitions, context: definitionsContext))
        for (index, definition) in definitions.enumerated() {
            guard let definitionName = definition.name else {
                preconditionFailure("admitted heist definitions must have names")
            }
            let currentDefinitionPath = definitionScope.pathPrefix + [definitionName]
            let currentDefinitionNode = HeistInvocationPath(namePath: currentDefinitionPath)
            let referenceBindings = definition.parameterReferenceBindings
            let definitionContext = HeistTraversalContext(
                path: path.index(index),
                depth: depth,
                stepIndex: nil,
                nextStep: nil,
                referenceBindings: referenceBindings,
                bindingSamples: [],
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope,
                invocationStack: []
            )
            try observe(.enterDefinition(definition, context: definitionContext))
            try walkDefinitions(
                definition.definitions,
                path: definitionContext.path.child(.definitions),
                depth: depth + 1,
                definitionScope: HeistDefinitionScope(definitions: definition.definitions, pathPrefix: currentDefinitionPath),
                rootDefinitionScope: rootDefinitionScope,
                parentContext: definitionContext,
                observe: observe
            )
            try walk(
                steps: definition.body,
                path: definitionContext.path.child(.body),
                depth: depth + 1,
                referenceBindings: referenceBindings,
                bindingSamples: [],
                definitionScope: HeistDefinitionScope(definitions: definition.definitions, pathPrefix: currentDefinitionPath),
                rootDefinitionScope: rootDefinitionScope,
                invocationStack: [currentDefinitionNode],
                observe: observe
            )
            try observe(.leaveDefinition(definition, context: definitionContext))
        }
        try observe(.leaveDefinitions(definitions, context: definitionsContext))
    }
}

extension HeistTraversalContext {
    func child(
        path: HeistPlanPath,
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
            bindingSamples: bindingSamples,
            definitionScope: definitionScope ?? self.definitionScope,
            rootDefinitionScope: rootDefinitionScope ?? self.rootDefinitionScope,
            invocationStack: invocationStack
        )
    }

    func nestedBranch(path: HeistPlanPath, stepIndex: Int?) -> HeistTraversalContext {
        HeistTraversalContext(
            path: path,
            depth: depth + 1,
            stepIndex: stepIndex,
            nextStep: nil,
            referenceBindings: referenceBindings,
            bindingSamples: bindingSamples,
            definitionScope: definitionScope,
            rootDefinitionScope: rootDefinitionScope,
            invocationStack: invocationStack
        )
    }

    func resolveInvocation(path: HeistInvocationPath) -> ResolvedHeistDefinition? {
        definitionScope.resolveInvocation(path: path, rootScope: rootDefinitionScope)
    }

    func callGraphCycle(closing resolvedNode: HeistInvocationPath) -> HeistCallGraph.Cycle? {
        guard let startIndex = invocationStack.firstIndex(of: resolvedNode) else { return nil }
        return HeistCallGraph.Cycle(path: Array(invocationStack[startIndex...]) + [resolvedNode])
    }
}

struct HeistDefinitionScope {
    let definitions: [HeistPlan]
    let pathPrefix: [HeistPlanName]
    private let definitionIndex: HeistDefinitionIndex

    init(definitions: [HeistPlan], pathPrefix: [HeistPlanName] = []) {
        self.definitions = definitions
        self.pathPrefix = pathPrefix
        self.definitionIndex = HeistDefinitionIndex(definitions: definitions)
    }

    func resolve(path: HeistInvocationPath) -> ResolvedHeistDefinition? {
        definitionIndex.resolve(components: path.components, componentIndex: 0, namePath: pathPrefix)
    }

    func resolveInvocation(path: HeistInvocationPath, rootScope: HeistDefinitionScope) -> ResolvedHeistDefinition? {
        if let local = resolve(path: path) {
            return local
        }
        guard path.components.count > 1 else { return nil }
        return rootScope.resolve(path: path)
    }
}

private struct HeistDefinitionIndex {
    private struct Entry {
        let definition: HeistPlan
        let children: HeistDefinitionIndex
    }

    private let entriesByName: [HeistPlanName: Entry]

    init(definitions: [HeistPlan]) {
        var entriesByName: [HeistPlanName: Entry] = [:]
        for definition in definitions {
            guard let name = definition.name,
                  entriesByName[name] == nil
            else { continue }
            entriesByName[name] = Entry(
                definition: definition,
                children: HeistDefinitionIndex(definitions: definition.definitions)
            )
        }
        self.entriesByName = entriesByName
    }

    func resolve(
        components: [HeistPlanName],
        componentIndex: Int,
        namePath: [HeistPlanName]
    ) -> ResolvedHeistDefinition? {
        guard components.indices.contains(componentIndex) else { return nil }
        let component = components[componentIndex]
        guard let entry = entriesByName[component] else { return nil }

        let resolvedNamePath = namePath + [component]
        guard componentIndex + 1 < components.count else {
            guard let first = resolvedNamePath.first else { return nil }
            return ResolvedHeistDefinition(
                definition: entry.definition,
                invocationPath: HeistInvocationPath(first: first, remaining: Array(resolvedNamePath.dropFirst()))
            )
        }

        return entry.children.resolve(
            components: components,
            componentIndex: componentIndex + 1,
            namePath: resolvedNamePath
        )
    }
}

struct ResolvedHeistDefinition {
    let definition: HeistPlan
    let invocationPath: HeistInvocationPath

    var qualifiedName: String {
        invocationPath.description
    }

    var namePath: [HeistPlanName] {
        invocationPath.components
    }

    var callGraphNode: HeistInvocationPath {
        HeistInvocationPath(namePath: namePath)
    }
}

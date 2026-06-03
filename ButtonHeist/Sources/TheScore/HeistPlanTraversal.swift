import Foundation

struct HeistTraversalContext {
    let path: String
    let depth: Int
    let stepIndex: Int?
    let nextStep: HeistStep?
    let allowsCollectionLoops: Bool
    let scope: AdmissionScope
    let environment: HeistExecutionEnvironment
}

protocol HeistPlanTraversalVisitor {
    mutating func visitPlan(_ plan: HeistPlan, context: HeistTraversalContext)
    mutating func visitStep(_ step: HeistStep, context: HeistTraversalContext)
    mutating func visitAction(_ action: ActionStep, context: HeistTraversalContext)
    mutating func visitWait(_ wait: WaitStep, context: HeistTraversalContext)
    mutating func visitConditional(_ conditional: ConditionalStep, context: HeistTraversalContext)
    mutating func visitWaitForCases(_ waitForCases: WaitForCasesStep, context: HeistTraversalContext)
    mutating func visitPredicateCase(_ predicateCase: PredicateCase, context: HeistTraversalContext)
    mutating func visitElseSteps(_ steps: [HeistStep], context: HeistTraversalContext)
    mutating func visitForEachElement(_ step: ForEachElementStep, context: HeistTraversalContext)
    mutating func visitForEachString(_ step: ForEachStringStep, context: HeistTraversalContext)
    mutating func visitWarn(_ warn: WarnStep, context: HeistTraversalContext)
    mutating func visitFail(_ fail: FailStep, context: HeistTraversalContext)
}

extension HeistPlanTraversalVisitor {
    mutating func visitPlan(_ plan: HeistPlan, context: HeistTraversalContext) {}
    mutating func visitStep(_ step: HeistStep, context: HeistTraversalContext) {}
    mutating func visitAction(_ action: ActionStep, context: HeistTraversalContext) {}
    mutating func visitWait(_ wait: WaitStep, context: HeistTraversalContext) {}
    mutating func visitConditional(_ conditional: ConditionalStep, context: HeistTraversalContext) {}
    mutating func visitWaitForCases(_ waitForCases: WaitForCasesStep, context: HeistTraversalContext) {}
    mutating func visitPredicateCase(_ predicateCase: PredicateCase, context: HeistTraversalContext) {}
    mutating func visitElseSteps(_ steps: [HeistStep], context: HeistTraversalContext) {}
    mutating func visitForEachElement(_ step: ForEachElementStep, context: HeistTraversalContext) {}
    mutating func visitForEachString(_ step: ForEachStringStep, context: HeistTraversalContext) {}
    mutating func visitWarn(_ warn: WarnStep, context: HeistTraversalContext) {}
    mutating func visitFail(_ fail: FailStep, context: HeistTraversalContext) {}
}

struct HeistPlanTraversal {
    mutating func walk<V: HeistPlanTraversalVisitor>(
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
            environment: .empty
        )
        visitor.visitPlan(plan, context: context)
        walk(
            steps: plan.steps,
            path: "$.steps",
            depth: 1,
            allowsCollectionLoops: true,
            scope: .empty,
            environment: .empty,
            visitor: &visitor
        )
    }

    mutating func walk<V: HeistPlanTraversalVisitor>(
        steps: [HeistStep],
        path: String,
        depth: Int,
        allowsCollectionLoops: Bool,
        scope: AdmissionScope,
        environment: HeistExecutionEnvironment,
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
                environment: environment
            )
            walk(step: step, context: context, visitor: &visitor)
        }
    }

    private mutating func walk<V: HeistPlanTraversalVisitor>(
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
            let conditionalContext = context.child(path: "\(context.path).conditional")
            visitor.visitConditional(conditional, context: conditionalContext)
            walk(
                cases: conditional.cases,
                elseSteps: conditional.elseSteps,
                path: conditionalContext.path,
                depth: context.depth + 1,
                scope: context.scope,
                environment: context.environment,
                visitor: &visitor
            )
        case .waitForCases(let waitForCases):
            let waitForContext = context.child(path: "\(context.path).wait_for_cases")
            visitor.visitWaitForCases(waitForCases, context: waitForContext)
            walk(
                cases: waitForCases.cases,
                elseSteps: waitForCases.elseSteps,
                path: waitForContext.path,
                depth: context.depth + 1,
                scope: context.scope,
                environment: context.environment,
                visitor: &visitor
            )
        case .forEachElement(let forEach):
            let forEachContext = context.child(path: "\(context.path).for_each_element")
            visitor.visitForEachElement(forEach, context: forEachContext)
            walk(
                steps: forEach.steps,
                path: "\(forEachContext.path).steps",
                depth: context.depth + 1,
                allowsCollectionLoops: false,
                scope: context.scope.bindingTarget(forEach.parameter),
                environment: context.environment.binding(
                    target: .predicate(forEach.matching),
                    to: forEach.parameter
                ),
                visitor: &visitor
            )
        case .forEachString(let forEach):
            let forEachContext = context.child(path: "\(context.path).for_each_string")
            visitor.visitForEachString(forEach, context: forEachContext)
            walk(
                steps: forEach.steps,
                path: "\(forEachContext.path).steps",
                depth: context.depth + 1,
                allowsCollectionLoops: false,
                scope: context.scope.bindingString(forEach.parameter),
                environment: context.environment.binding(
                    string: forEach.values.first ?? "",
                    to: forEach.parameter
                ),
                visitor: &visitor
            )
        case .warn(let warn):
            visitor.visitWarn(warn, context: context.child(path: "\(context.path).warn"))
        case .fail(let fail):
            visitor.visitFail(fail, context: context.child(path: "\(context.path).fail"))
        }
    }

    private mutating func walk<V: HeistPlanTraversalVisitor>(
        cases: [PredicateCase],
        elseSteps: [HeistStep]?,
        path: String,
        depth: Int,
        scope: AdmissionScope,
        environment: HeistExecutionEnvironment,
        visitor: inout V
    ) {
        for (index, predicateCase) in cases.enumerated() {
            let casePath = "\(path).cases[\(index)]"
            let caseContext = HeistTraversalContext(
                path: casePath,
                depth: depth,
                stepIndex: nil,
                nextStep: nil,
                allowsCollectionLoops: false,
                scope: scope,
                environment: environment
            )
            visitor.visitPredicateCase(predicateCase, context: caseContext)
            walk(
                steps: predicateCase.steps,
                path: "\(casePath).steps",
                depth: depth,
                allowsCollectionLoops: false,
                scope: scope,
                environment: environment,
                visitor: &visitor
            )
        }
        if let elseSteps {
            let elseContext = HeistTraversalContext(
                path: "\(path).else_steps",
                depth: depth,
                stepIndex: nil,
                nextStep: nil,
                allowsCollectionLoops: false,
                scope: scope,
                environment: environment
            )
            visitor.visitElseSteps(elseSteps, context: elseContext)
            walk(
                steps: elseSteps,
                path: elseContext.path,
                depth: depth,
                allowsCollectionLoops: false,
                scope: scope,
                environment: environment,
                visitor: &visitor
            )
        }
    }
}

private extension HeistTraversalContext {
    func child(path: String) -> HeistTraversalContext {
        HeistTraversalContext(
            path: path,
            depth: depth,
            stepIndex: stepIndex,
            nextStep: nextStep,
            allowsCollectionLoops: allowsCollectionLoops,
            scope: scope,
            environment: environment
        )
    }
}

struct AdmissionScope {
    static let empty = AdmissionScope()

    var targetRefs: Set<String> = []
    var stringRefs: Set<String> = []

    func bindingTarget(_ reference: String) -> AdmissionScope {
        var copy = self
        copy.targetRefs.insert(reference)
        return copy
    }

    func bindingString(_ reference: String) -> AdmissionScope {
        var copy = self
        copy.stringRefs.insert(reference)
        return copy
    }
}

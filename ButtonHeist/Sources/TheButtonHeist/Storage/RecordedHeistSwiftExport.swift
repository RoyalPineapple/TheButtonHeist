import Foundation
import os

import TheScore

private let recordedHeistSwiftExportLogger = Logger(
    subsystem: "com.buttonheist.fence",
    category: "recorded-swift-export"
)

struct RecordedHeistSwiftExport: Sendable {
    struct SampleRewrite: Sendable, Equatable {
        let parameterName: String
        let sampleValue: String
    }

    struct Result: Sendable, Equatable {
        let source: String
        let plan: HeistPlan
        let diagnostics: [String]
    }

    enum ExportError: Error, Sendable, Equatable, CustomStringConvertible {
        case missingName
        case invalidName(String)
        case invalidSampleParameter(String)
        case emptySampleValue

        var description: String {
            switch self {
            case .missingName:
                return "recorded Swift export requires a non-empty heist name"
            case .invalidName(let name):
                return """
                invalid recorded heist name "\(name)"; use a Swift-style identifier such as RecordedSearch
                """
            case .invalidSampleParameter(let parameter):
                return """
                invalid sample rewrite parameter "\(parameter)"; use a Swift-style identifier such as query
                """
            case .emptySampleValue:
                return "sample rewrite value must not be empty"
            }
        }
    }

    func render(_ recordedPlan: HeistPlan, sampleRewrite: SampleRewrite? = nil) throws -> Result {
        _ = try validatedName(recordedPlan.name)
        let rewriteResult = try rewrite(recordedPlan, sampleRewrite: sampleRewrite)
        let sourcePlan = rewriteResult.plan
        let rendered = try sourcePlan.canonicalSwiftDSL()
        return Result(
            source: """
            import ThePlans

            let heist = try \(rendered)
            """,
            plan: sourcePlan,
            diagnostics: rewriteResult.diagnostics
        )
    }

    private func validatedName(_ name: String?) throws -> String {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportError.missingName
        }
        guard HeistParameterName.isValid(name) else {
            throw ExportError.invalidName(name)
        }
        return name
    }

    private func rewrite(
        _ plan: HeistPlan,
        sampleRewrite: SampleRewrite?
    ) throws -> (plan: HeistPlan, diagnostics: [String]) {
        guard let sampleRewrite else {
            return (plan, [])
        }
        guard HeistParameterName.isValid(sampleRewrite.parameterName) else {
            throw ExportError.invalidSampleParameter(sampleRewrite.parameterName)
        }
        guard !sampleRewrite.sampleValue.isEmpty else {
            throw ExportError.emptySampleValue
        }
        let occurrences = SampleOccurrenceCounter(sampleValue: sampleRewrite.sampleValue).count(in: plan)
        let labelRewriteAllowed = occurrences.label == 1 && occurrences.typedText == 0 && occurrences.value == 0
        var diagnostics: [String] = []
        if occurrences.label > 1 {
            diagnostics.append(
                """
                sample value "\(sampleRewrite.sampleValue)" appears in multiple labels; label literals were left concrete
                """
            )
        } else if occurrences.label > 0, !labelRewriteAllowed {
            diagnostics.append(
                """
                sample value "\(sampleRewrite.sampleValue)" also appears as typed text or value; label literals were left concrete
                """
            )
        }

        var rewriter = SamplePlanRewriter(
            sampleValue: sampleRewrite.sampleValue,
            parameterName: sampleRewrite.parameterName,
            rewriteLabels: labelRewriteAllowed
        )
        let rewrittenBody = try rewriter.rewrite(steps: plan.body)
        guard rewriter.replacementCount > 0 else {
            return (plan, diagnostics)
        }
        let rewritten = try HeistPlan(
            name: try validatedName(plan.name),
            parameter: .string(name: sampleRewrite.parameterName),
            definitions: plan.definitions,
            body: rewrittenBody
        )
        return (rewritten, diagnostics)
    }
}

private struct SampleOccurrences: Sendable, Equatable {
    var typedText = 0
    var label = 0
    var value = 0
}

private struct SampleOccurrenceCounter {
    let sampleValue: String

    func count(in plan: HeistPlan) -> SampleOccurrences {
        var occurrences = SampleOccurrences()
        count(steps: plan.body, into: &occurrences)
        return occurrences
    }

    private func count(steps: [HeistStep], into occurrences: inout SampleOccurrences) {
        for step in steps {
            count(step: step, into: &occurrences)
        }
    }

    private func count(step: HeistStep, into occurrences: inout SampleOccurrences) {
        switch step {
        case .action(let action):
            count(command: action.command, into: &occurrences)
            if let expectation = action.expectation {
                count(predicate: expectation.predicate, into: &occurrences)
            }
        case .wait(let wait):
            count(predicate: wait.predicate, into: &occurrences)
        case .conditional(let conditional):
            for predicateCase in conditional.cases {
                count(predicate: predicateCase.predicate, into: &occurrences)
                count(steps: predicateCase.body, into: &occurrences)
            }
            if let elseBody = conditional.elseBody {
                count(steps: elseBody, into: &occurrences)
            }
        case .waitForCases(let waitForCases):
            for predicateCase in waitForCases.cases {
                count(predicate: predicateCase.predicate, into: &occurrences)
                count(steps: predicateCase.body, into: &occurrences)
            }
            if let elseBody = waitForCases.elseBody {
                count(steps: elseBody, into: &occurrences)
            }
        case .forEachElement(let forEach):
            count(predicate: forEach.matching, into: &occurrences)
            count(steps: forEach.body, into: &occurrences)
        case .forEachString(let forEach):
            count(steps: forEach.body, into: &occurrences)
        case .heist(let plan):
            count(steps: plan.body, into: &occurrences)
        case .warn, .fail, .invoke:
            break
        }
    }

    private func count(command: HeistActionCommand, into occurrences: inout SampleOccurrences) {
        switch command {
        case .activate(let target), .increment(let target), .decrement(let target),
             .viewportScrollToVisible(let target):
            count(target: target, into: &occurrences)
        case .customAction(_, let target):
            count(target: target, into: &occurrences)
        case .rotor(_, let target, _):
            count(target: target, into: &occurrences)
        case .typeText(let text, let target):
            if case .literal(let literal) = text, literal == sampleValue {
                occurrences.typedText += 1
            }
            if let target {
                count(target: target, into: &occurrences)
            }
        case .mechanicalTap(let target):
            count(selection: target.selection, into: &occurrences)
        case .mechanicalLongPress(let target):
            count(selection: target.selection, into: &occurrences)
        case .mechanicalSwipe(let target):
            count(swipe: target.selection, into: &occurrences)
        case .mechanicalDrag(let target):
            count(drag: target.selection, into: &occurrences)
        case .viewportScroll(let target):
            count(scroll: target.selection, into: &occurrences)
        case .viewportScrollToEdge(let target):
            count(scroll: target.selection, into: &occurrences)
        case .editAction, .setPasteboard, .dismissKeyboard:
            break
        }
    }

    private func count(target: ElementTargetExpr, into occurrences: inout SampleOccurrences) {
        switch target {
        case .target(let target):
            count(target: target, into: &occurrences)
        case .predicate(let predicate, _):
            count(predicate: predicate, into: &occurrences)
        case .ref:
            break
        }
    }

    private func count(target: ElementTarget, into occurrences: inout SampleOccurrences) {
        switch target {
        case .predicate(let predicate, _):
            count(predicate: predicate, into: &occurrences)
        }
    }

    private func count(predicate: AccessibilityPredicateExpr, into occurrences: inout SampleOccurrences) {
        switch predicate {
        case .predicate(let predicate):
            count(predicate: predicate, into: &occurrences)
        case .state(let state):
            count(state: state, into: &occurrences)
        case .changed(let change):
            count(change: change, into: &occurrences)
        }
    }

    private func count(predicate: AccessibilityPredicate, into occurrences: inout SampleOccurrences) {
        switch predicate {
        case .state(let state):
            count(state: state, into: &occurrences)
        case .changed(let change):
            count(change: change, into: &occurrences)
        }
    }

    private func count(state: AccessibilityPredicate.State, into occurrences: inout SampleOccurrences) {
        switch state {
        case .present(let predicate), .absent(let predicate):
            count(predicate: predicate, into: &occurrences)
        case .presentTarget(let target), .absentTarget(let target):
            count(target: target, into: &occurrences)
        case .all(let states):
            for state in states {
                count(state: state, into: &occurrences)
            }
        }
    }

    private func count(state: StatePredicateExpr, into occurrences: inout SampleOccurrences) {
        switch state {
        case .present(let predicate), .absent(let predicate):
            count(predicate: predicate, into: &occurrences)
        case .presentTarget(let target), .absentTarget(let target):
            count(target: target, into: &occurrences)
        case .all(let states):
            for state in states {
                count(state: state, into: &occurrences)
            }
        }
    }

    private func count(change: AccessibilityPredicate.Change, into occurrences: inout SampleOccurrences) {
        switch change {
        case .screen(let state):
            if let state {
                count(state: state, into: &occurrences)
            }
        case .elements:
            break
        case .appeared(let predicate), .disappeared(let predicate):
            count(predicate: predicate, into: &occurrences)
        case .updated(let update):
            if let element = update.element {
                count(predicate: element, into: &occurrences)
            }
            if update.from == sampleValue {
                occurrences.value += 1
            }
            if update.to == sampleValue {
                occurrences.value += 1
            }
        }
    }

    private func count(change: ChangePredicateExpr, into occurrences: inout SampleOccurrences) {
        switch change {
        case .screen(let state):
            if let state {
                count(state: state, into: &occurrences)
            }
        case .elements:
            break
        case .appeared(let predicate), .disappeared(let predicate):
            count(predicate: predicate, into: &occurrences)
        case .updated(let update):
            if let element = update.element {
                count(predicate: element, into: &occurrences)
            }
            countValue(update.from, into: &occurrences)
            countValue(update.to, into: &occurrences)
        }
    }

    private func count(predicate: ElementPredicate, into occurrences: inout SampleOccurrences) {
        if predicate.label == sampleValue {
            occurrences.label += 1
        }
        if predicate.value == sampleValue {
            occurrences.value += 1
        }
    }

    private func count(predicate: ElementPredicateTemplate, into occurrences: inout SampleOccurrences) {
        countLabel(predicate.label, into: &occurrences)
        countValue(predicate.value, into: &occurrences)
    }

    private func countLabel(_ expression: StringExpr?, into occurrences: inout SampleOccurrences) {
        if case .literal(let literal) = expression, literal == sampleValue {
            occurrences.label += 1
        }
    }

    private func countValue(_ expression: StringExpr?, into occurrences: inout SampleOccurrences) {
        if case .literal(let literal) = expression, literal == sampleValue {
            occurrences.value += 1
        }
    }

    private func count(selection: GesturePointSelection, into occurrences: inout SampleOccurrences) {
        if case .element(let target) = selection {
            count(target: target, into: &occurrences)
        }
    }

    private func count(swipe: SwipeGestureSelection, into occurrences: inout SampleOccurrences) {
        switch swipe {
        case .unitElement(let target, _, _), .elementDirection(let target, _):
            count(target: target, into: &occurrences)
        case .point(let selection, _):
            count(selection: selection, into: &occurrences)
        }
    }

    private func count(drag: DragGestureSelection, into occurrences: inout SampleOccurrences) {
        if case .elementToPoint(let target, _) = drag {
            count(target: target, into: &occurrences)
        }
    }

    private func count(scroll: ScrollContainerSelection, into occurrences: inout SampleOccurrences) {
        if case .element(let target) = scroll {
            count(target: target, into: &occurrences)
        }
    }
}

private struct SamplePlanRewriter {
    let sampleValue: String
    let parameterName: String
    let rewriteLabels: Bool
    var replacementCount = 0

    mutating func rewrite(steps: [HeistStep]) throws -> [HeistStep] {
        try steps.map { try rewrite(step: $0) }
    }

    private mutating func rewrite(step: HeistStep) throws -> HeistStep {
        switch step {
        case .action(let action):
            return .action(try ActionStep(
                command: rewrite(command: action.command),
                expectation: action.expectation.map { rewrite(wait: $0) },
                expectationWaiver: action.expectationWaiver
            ))
        case .wait(let wait):
            return .wait(rewrite(wait: wait))
        case .conditional(let conditional):
            return .conditional(try ConditionalStep(
                cases: try conditional.cases.map { try rewrite(predicateCase: $0) },
                elseBody: try conditional.elseBody.map { try rewrite(steps: $0) }
            ))
        case .waitForCases(let waitForCases):
            return .waitForCases(try WaitForCasesStep(
                timeout: waitForCases.timeout,
                cases: try waitForCases.cases.map { try rewrite(predicateCase: $0) },
                elseBody: try waitForCases.elseBody.map { try rewrite(steps: $0) }
            ))
        case .forEachElement(let forEach):
            return .forEachElement(try ForEachElementStep(
                matching: forEach.matching,
                limit: forEach.limit,
                parameter: forEach.parameter,
                body: try rewrite(steps: forEach.body)
            ))
        case .forEachString(let forEach):
            return .forEachString(try ForEachStringStep(
                values: forEach.values,
                parameter: forEach.parameter,
                body: try rewrite(steps: forEach.body)
            ))
        case .heist(let plan):
            return .heist(try HeistPlan(
                name: plan.name,
                parameter: plan.parameter,
                definitions: plan.definitions,
                body: try rewrite(steps: plan.body)
            ))
        case .warn, .fail, .invoke:
            return step
        }
    }

    private mutating func rewrite(predicateCase: PredicateCase) throws -> PredicateCase {
        PredicateCase(
            predicate: rewrite(predicate: predicateCase.predicate),
            body: try rewrite(steps: predicateCase.body)
        )
    }

    private mutating func rewrite(wait: WaitStep) -> WaitStep {
        WaitStep(
            predicate: rewrite(predicate: wait.predicate),
            timeout: wait.timeout
        )
    }

    private mutating func rewrite(command: HeistActionCommand) -> HeistActionCommand {
        switch command {
        case .activate(let target):
            return .activate(rewrite(target: target))
        case .increment(let target):
            return .increment(rewrite(target: target))
        case .decrement(let target):
            return .decrement(rewrite(target: target))
        case .customAction(let name, let target):
            return .customAction(name: name, target: rewrite(target: target))
        case .rotor(let selection, let target, let direction):
            return .rotor(selection: selection, target: rewrite(target: target), direction: direction)
        case .typeText(let text, let target):
            return .typeText(
                text: rewriteTypedText(text),
                target: target.map { rewrite(target: $0) }
            )
        case .mechanicalTap, .mechanicalLongPress, .mechanicalSwipe, .mechanicalDrag,
             .viewportScroll, .viewportScrollToEdge:
            return command
        case .viewportScrollToVisible(let target):
            return .viewportScrollToVisible(rewrite(target: target))
        case .editAction, .setPasteboard, .dismissKeyboard:
            return command
        }
    }

    private mutating func rewriteTypedText(_ expression: StringExpr) -> StringExpr {
        guard case .literal(let literal) = expression, literal == sampleValue else {
            return expression
        }
        replacementCount += 1
        return .ref(parameterName)
    }

    private mutating func rewrite(target: ElementTargetExpr) -> ElementTargetExpr {
        switch target {
        case .target(let target):
            return rewrite(target: target)
        case .predicate(let predicate, let ordinal):
            return .predicate(rewrite(predicate: predicate), ordinal: ordinal)
        case .ref:
            return target
        }
    }

    private mutating func rewrite(target: ElementTarget) -> ElementTargetExpr {
        switch target {
        case .predicate(let predicate, let ordinal):
            let rewritten = rewrite(predicate: ElementPredicateTemplate(predicate))
            guard rewritten != ElementPredicateTemplate(predicate) else {
                return .target(target)
            }
            return .predicate(rewritten, ordinal: ordinal)
        }
    }

    private mutating func rewrite(predicate: AccessibilityPredicateExpr) -> AccessibilityPredicateExpr {
        switch predicate {
        case .predicate(let predicate):
            return rewrite(predicate: predicate)
        case .state(let state):
            return .state(rewrite(state: state))
        case .changed(let change):
            return .changed(rewrite(change: change))
        }
    }

    private mutating func rewrite(predicate: AccessibilityPredicate) -> AccessibilityPredicateExpr {
        switch predicate {
        case .state(let state):
            let rewritten = rewrite(state: state)
            do {
                if try rewritten.resolve(in: .empty) == state {
                    return .predicate(predicate)
                }
            } catch {
                let errorDescription = String(describing: error)
                recordedHeistSwiftExportLogger.warning(
                    "Failed to resolve rewritten state predicate during sample rewrite: \(errorDescription, privacy: .public)"
                )
            }
            return .state(rewritten)
        case .changed(let change):
            let rewritten = rewrite(change: change)
            do {
                if try rewritten.resolve(in: .empty) == change {
                    return .predicate(predicate)
                }
            } catch {
                let errorDescription = String(describing: error)
                recordedHeistSwiftExportLogger.warning(
                    "Failed to resolve rewritten change predicate during sample rewrite: \(errorDescription, privacy: .public)"
                )
            }
            return .changed(rewritten)
        }
    }

    private mutating func rewrite(state: AccessibilityPredicate.State) -> StatePredicateExpr {
        switch state {
        case .present(let predicate):
            return .present(rewrite(predicate: ElementPredicateTemplate(predicate)))
        case .absent(let predicate):
            return .absent(rewrite(predicate: ElementPredicateTemplate(predicate)))
        case .presentTarget(let target):
            return .presentTarget(rewrite(target: target))
        case .absentTarget(let target):
            return .absentTarget(rewrite(target: target))
        case .all(let states):
            return .all(states.map { rewrite(state: $0) })
        }
    }

    private mutating func rewrite(state: StatePredicateExpr) -> StatePredicateExpr {
        switch state {
        case .present(let predicate):
            return .present(rewrite(predicate: predicate))
        case .absent(let predicate):
            return .absent(rewrite(predicate: predicate))
        case .presentTarget(let target):
            return .presentTarget(rewrite(target: target))
        case .absentTarget(let target):
            return .absentTarget(rewrite(target: target))
        case .all(let states):
            return .all(states.map { rewrite(state: $0) })
        }
    }

    private mutating func rewrite(change: AccessibilityPredicate.Change) -> ChangePredicateExpr {
        switch change {
        case .screen(let state):
            return .screen(where: state.map { rewrite(state: $0) })
        case .elements:
            return .elements
        case .appeared(let predicate):
            return .appeared(rewrite(predicate: ElementPredicateTemplate(predicate)))
        case .disappeared(let predicate):
            return .disappeared(rewrite(predicate: ElementPredicateTemplate(predicate)))
        case .updated(let update):
            return .updated(rewrite(update: ElementUpdatePredicateExpr(update)))
        }
    }

    private mutating func rewrite(change: ChangePredicateExpr) -> ChangePredicateExpr {
        switch change {
        case .screen(let state):
            return .screen(where: state.map { rewrite(state: $0) })
        case .elements:
            return .elements
        case .appeared(let predicate):
            return .appeared(rewrite(predicate: predicate))
        case .disappeared(let predicate):
            return .disappeared(rewrite(predicate: predicate))
        case .updated(let update):
            return .updated(rewrite(update: update))
        }
    }

    private mutating func rewrite(update: ElementUpdatePredicateExpr) -> ElementUpdatePredicateExpr {
        ElementUpdatePredicateExpr(
            element: update.element.map { rewrite(predicate: $0) },
            property: update.property,
            from: rewriteValue(update.from),
            to: rewriteValue(update.to)
        )
    }

    private mutating func rewrite(predicate: ElementPredicateTemplate) -> ElementPredicateTemplate {
        ElementPredicateTemplate(
            label: rewriteLabel(predicate.label),
            identifier: predicate.identifier,
            value: rewriteValue(predicate.value),
            traits: predicate.traits,
            excludeTraits: predicate.excludeTraits
        )
    }

    private mutating func rewriteLabel(_ expression: StringExpr?) -> StringExpr? {
        guard rewriteLabels,
              case .literal(let literal) = expression,
              literal == sampleValue
        else {
            return expression
        }
        replacementCount += 1
        return .ref(parameterName)
    }

    private mutating func rewriteValue(_ expression: StringExpr?) -> StringExpr? {
        guard case .literal(let literal) = expression,
              literal == sampleValue
        else {
            return expression
        }
        replacementCount += 1
        return .ref(parameterName)
    }
}

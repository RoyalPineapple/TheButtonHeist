import TheScore

struct ProjectedHeistStepOutcome {
    let step: HeistStep
    let outcome: HeistExecutionStepResult

    var commandName: String {
        step.commandName
    }

    var fenceCommand: TheFence.Command? {
        step.fenceCommand
    }

    var target: ElementTarget? {
        step.reportTarget
    }

    var response: FenceResponse? {
        if let skipped = outcome.skipped {
            return .error(skipped.reason)
        }
        if case .fail(let fail) = step {
            return .error(fail.message)
        }
        if let actionResponse = outcome.actionResponse(
            command: fenceCommand ?? .runHeist,
            step: step
        ) {
            return actionResponse
        }
        if let failureMessage {
            return .error(failureMessage)
        }
        return nil
    }

    var failureMessage: String? {
        if let skipped = outcome.skipped {
            return skipped.reason
        }
        if case .fail(let fail) = step {
            return fail.message
        }
        if let result = outcome.finalActionResult(), !result.success {
            return result.message ?? "action failed"
        }
        if outcome.expectation?.met == false {
            return outcome.expectation?.actual ?? "expectation not met"
        }
        if step.requiresActionResult, outcome.finalActionResult() == nil {
            return "typed heist step produced no action result"
        }
        if outcome.kind == .waitForCases,
           outcome.caseSelection?.timedOut == true,
           outcome.caseSelection?.elseRan != true {
            return outcome.message ?? "wait_for_cases timed out"
        }
        if outcome.kind == .forEach, let reason = outcome.forEachResult?.failureReason {
            return reason
        }
        if outcome.stopsHeist, outcome.childResults?.contains(where: \.isFailure) != true {
            return outcome.message ?? "heist step failed"
        }
        return nil
    }
}

extension HeistExecutionResult {
    var flattenedOutcomes: [HeistExecutionStepResult] {
        steps.flatMap(\.flattenedOutcomes)
    }

    func projectedOutcomes(for plan: HeistPlan) -> [ProjectedHeistStepOutcome] {
        Self.projectedOutcomes(steps: plan.steps, outcomes: steps)
    }

    func projectedExpectationsChecked(for plan: HeistPlan) -> Int {
        projectedOutcomes(for: plan).count { projection in
            projection.outcome.expectationCounted(for: projection.step)
        }
    }

    func projectedExpectationsMet(for plan: HeistPlan) -> Int {
        projectedOutcomes(for: plan).count { projection in
            projection.outcome.expectationMet(for: projection.step) == true
        }
    }

    private static func projectedOutcomes(
        steps: [HeistStep],
        outcomes: [HeistExecutionStepResult]
    ) -> [ProjectedHeistStepOutcome] {
        var projections: [ProjectedHeistStepOutcome] = []
        for (siblingIndex, step) in steps.enumerated() {
            guard let outcome = outcomes.first(where: { $0.index == siblingIndex }) else { continue }
            projections.append(ProjectedHeistStepOutcome(step: step, outcome: outcome))
            guard let childSteps = step.projectedChildSteps(for: outcome),
                  let childOutcomes = outcome.childResults
            else { continue }
            projections.append(contentsOf: projectedOutcomes(steps: childSteps, outcomes: childOutcomes))
        }
        return projections
    }
}

private extension HeistExecutionStepResult {
    var flattenedOutcomes: [HeistExecutionStepResult] {
        [self] + (childResults ?? []).flatMap(\.flattenedOutcomes)
    }
}

private extension HeistStep {
    var requiresActionResult: Bool {
        switch self {
        case .action, .wait:
            return true
        case .conditional, .waitForCases, .forEach, .warn, .fail:
            return false
        }
    }

    func projectedChildSteps(for outcome: HeistExecutionStepResult) -> [HeistStep]? {
        switch self {
        case .conditional(let conditional):
            if let selectedCaseIndex = outcome.caseSelection?.selectedCaseIndex {
                return conditional.cases[safe: selectedCaseIndex]?.steps
            }
            if outcome.caseSelection?.elseRan == true {
                return conditional.elseSteps
            }
            return nil
        case .waitForCases(let waitForCases):
            if let selectedCaseIndex = outcome.caseSelection?.selectedCaseIndex {
                return waitForCases.cases[safe: selectedCaseIndex]?.steps
            }
            if outcome.caseSelection?.elseRan == true {
                return waitForCases.elseSteps
            }
            return nil
        case .forEach(let forEach):
            guard let iterationCount = outcome.forEachResult?.iterationCount, iterationCount > 0 else {
                return nil
            }
            return (0..<iterationCount).flatMap { _ in forEach.steps }
        case .action, .wait, .warn, .fail:
            return nil
        }
    }

    var commandName: String {
        switch self {
        case .action(let action): return action.command.wireType.commandName
        case .wait: return "wait"
        case .conditional: return "if"
        case .waitForCases: return "wait_for_cases"
        case .forEach: return "for_each"
        case .warn: return "warn"
        case .fail: return "fail"
        }
    }

    var fenceCommand: TheFence.Command? {
        guard case .action(let action) = self else { return nil }
        return TheFence.Command(clientWireType: action.command.wireType)
    }

    var reportTarget: ElementTarget? {
        guard case .action(let action) = self else { return nil }
        return action.command.reportTarget
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension TheFence.Command {
    init?(clientWireType: ClientWireMessageType) {
        self.init(rawValue: clientWireType.commandName)
    }
}

extension ClientWireMessageType {
    var commandName: String {
        switch self {
        case .performCustomAction: return TheFence.Command.activate.rawValue
        case .oneFingerTap: return TheFence.Command.oneFingerTap.rawValue
        case .longPress: return TheFence.Command.longPress.rawValue
        case .typeText: return TheFence.Command.typeText.rawValue
        case .setPasteboard: return TheFence.Command.setPasteboard.rawValue
        case .scrollToVisible: return TheFence.Command.scrollToVisible.rawValue
        case .elementSearch: return TheFence.Command.elementSearch.rawValue
        case .scrollToEdge: return TheFence.Command.scrollToEdge.rawValue
        case .resignFirstResponder: return TheFence.Command.dismissKeyboard.rawValue
        default: return rawValue
        }
    }
}

extension ClientMessage {
    var reportTarget: ElementTarget? {
        switch self {
        case .activate(let target), .increment(let target), .decrement(let target):
            return target
        case .performCustomAction(let target):
            return target.elementTarget
        case .rotor(let target):
            return target.elementTarget
        case .oneFingerTap(let target):
            if case .element(let target) = target.selection { return target }
            return nil
        case .longPress(let target):
            if case .element(let target) = target.selection { return target }
            return nil
        case .swipe(let target):
            switch target.selection {
            case .unitElement(let target, _, _), .elementDirection(let target, _):
                return target
            case .point(let start, _):
                if case .element(let target) = start { return target }
                return nil
            }
        case .drag(let target):
            if case .element(let target) = target.start { return target }
            return nil
        case .typeText(let target):
            return target.elementTarget
        case .editAction, .setPasteboard:
            return nil
        case .scroll(let target):
            if case .element(let target) = target.selection { return target }
            return nil
        case .scrollToVisible(let target):
            return target.elementTarget
        case .elementSearch(let target):
            return target.elementTarget
        case .scrollToEdge(let target):
            if case .element(let target) = target.selection { return target }
            return nil
        case .clientHello, .authenticate, .requestInterface, .ping, .status, .requestScreen,
             .getPasteboard, .wait, .heistPlan, .resignFirstResponder:
            return nil
        }
    }
}

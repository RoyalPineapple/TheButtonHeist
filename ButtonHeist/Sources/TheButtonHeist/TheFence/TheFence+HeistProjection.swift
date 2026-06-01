import TheScore

struct ProjectedHeistStepOutcome {
    let step: HeistStep
    let outcome: HeistExecutionStepResult
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
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

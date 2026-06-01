import TheScore

extension TheFence {
    struct PlaybackProjection {
        let stepResults: [HeistPlaybackReport.StepResult]
        let failure: PlaybackFailure?
        let failedIndex: Int?
    }

    func playbackProjection(
        contract: HeistPlaybackContract,
        result: HeistExecutionResult
    ) -> PlaybackProjection {
        PlaybackReportProjection(contract: contract, result: result).project()
    }
}

private struct PlaybackReportProjection {
    let contract: TheFence.HeistPlaybackContract
    let result: HeistExecutionResult

    func project() -> TheFence.PlaybackProjection {
        var stepResults: [HeistPlaybackReport.StepResult] = []
        var failures: [PlaybackFailure] = []
        appendStepResults(
            steps: contract.plan.steps,
            outcomes: result.steps,
            into: &stepResults,
            failures: &failures
        )
        return TheFence.PlaybackProjection(
            stepResults: stepResults,
            failure: failures.first,
            failedIndex: stepResults.first { !$0.passed }?.index
        )
    }

    private func appendStepResults(
        steps: [HeistStep],
        outcomes: [HeistExecutionStepResult],
        into stepResults: inout [HeistPlaybackReport.StepResult],
        failures: inout [PlaybackFailure]
    ) {
        for (siblingIndex, step) in steps.enumerated() {
            let outcome = outcomes.first { $0.index == siblingIndex }
            let reportIndex = stepResults.count
            let failure = outcome.flatMap { playbackFailure(step: step, outcome: $0) }
            stepResults.append(stepResult(
                reportIndex: reportIndex,
                step: step,
                outcome: outcome,
                failure: failure
            ))
            if let failure {
                failures.append(failure)
            }
            guard
                let outcome,
                let childResults = outcome.childResults,
                let childSteps = childSteps(for: step, outcome: outcome)
            else { continue }
            appendStepResults(
                steps: childSteps,
                outcomes: childResults,
                into: &stepResults,
                failures: &failures
            )
        }
    }

    private func stepResult(
        reportIndex: Int,
        step: HeistStep,
        outcome: HeistExecutionStepResult?,
        failure: PlaybackFailure?
    ) -> HeistPlaybackReport.StepResult {
        let reportOutcome: HeistPlaybackReport.Outcome
        if let failure {
            reportOutcome = .failed(
                message: failure.errorMessage,
                errorKind: failureErrorKind(failure)
            )
        } else {
            reportOutcome = .passed
        }
        return HeistPlaybackReport.StepResult(
            index: reportIndex,
            command: step.commandName,
            target: step.reportTarget,
            timeSeconds: Double(outcome?.durationMs ?? 0) / 1000,
            outcome: reportOutcome
        )
    }

    private func childSteps(
        for step: HeistStep,
        outcome: HeistExecutionStepResult
    ) -> [HeistStep]? {
        switch step {
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
        case .action, .wait, .warn, .fail:
            return nil
        }
    }

    private func failureErrorKind(_ failure: PlaybackFailure) -> HeistPlaybackReport.PlaybackErrorKind? {
        switch failure {
        case .fenceError:
            return .commandError
        case .actionFailed(_, let result, _, _, _):
            guard let errorKind = result.errorKind else { return nil }
            return .action(errorKind)
        case .thrown:
            return .thrown
        }
    }

    private func playbackFailure(step: HeistStep, outcome: HeistExecutionStepResult) -> PlaybackFailure? {
        let failedStep = PlaybackFailure.FailedStep(command: step.fenceCommand ?? .runHeist, target: step.reportTarget)
        if let skipped = outcome.skipped {
            return .fenceError(
                step: failedStep,
                message: skipped.reason,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        }
        if case .fail(let fail) = step {
            return .fenceError(
                step: failedStep,
                message: fail.message,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        }
        guard outcome.hasOwnPlaybackFailure(for: step) else { return nil }
        if let result = outcome.finalActionResult() {
            return .actionFailed(
                step: failedStep,
                result: result,
                expectation: outcome.expectation,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        }
        return .fenceError(
            step: failedStep,
            message: outcome.message ?? "heist step failed",
            interface: nil,
            diagnosticCaptureFailure: nil
        )
    }
}

private extension HeistExecutionStepResult {
    func hasOwnPlaybackFailure(for step: HeistStep) -> Bool {
        if isSkipped { return true }
        if case .fail = step { return true }
        if actionResult?.success == false { return true }
        if expectationActionResult?.success == false { return true }
        if expectation?.met == false { return true }
        if kind == .action, actionResult == nil { return true }
        if kind == .wait, actionResult?.success != true { return true }
        if kind == .waitForCases,
           caseSelection?.timedOut == true,
           caseSelection?.elseRan != true {
            return true
        }
        if stopsHeist, childResults?.contains(where: \.isFailure) != true {
            return true
        }
        return false
    }
}

private extension HeistStep {
    var commandName: String {
        switch self {
        case .action(let action): return action.command.wireType.rawValue
        case .wait: return "wait"
        case .conditional: return "if"
        case .waitForCases: return "wait_for_cases"
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

private extension ClientMessage {
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
        case .clientHello, .authenticate, .requestInterface, .ping, .status,
             .editAction, .setPasteboard, .getPasteboard, .wait,
             .resignFirstResponder, .requestScreen, .heistPlan:
            return nil
        }
    }
}

private extension TheFence.Command {
    init?(clientWireType: ClientWireMessageType) {
        self.init(rawValue: clientWireType.commandName)
    }
}

private extension ClientWireMessageType {
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

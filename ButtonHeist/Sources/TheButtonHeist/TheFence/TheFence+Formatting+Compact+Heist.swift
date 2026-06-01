import Foundation

import TheScore

extension FenceResponse {

    func compactHeistFormatted(
        plan: HeistPlan,
        result: HeistExecutionResult,
        netDelta: AccessibilityTrace.Delta?
    ) -> String {
        let checked = result.expectationsChecked(steps: plan.steps)
        let met = result.expectationsMet(steps: plan.steps)
        var text = "heist: \(result.completedStepCount) steps in \(result.totalTimingMs)ms"
        let failedIndex = result.stoppedFailedIndex
        if let failedIndex { text += " (failed at \(failedIndex))" }
        if checked > 0 { text += " [expectations: \(met)/\(checked)]" }
        if let netDelta { text += " [net: \(Self.compactDeltaKind(netDelta))]" }
        if let lastScreenId = result.steps.compactMap({ $0.finalActionResult()?.accessibilityTrace?.endpointScreenIdProjection }).last {
            text = "\(lastScreenId) | \(text)"
        }
        for step in result.steps {
            let commandName = plan.steps[safe: step.index]?.commandName ?? "step \(step.index)"
            var line = "  [\(step.index)] \(commandName)"
            if let skipped = step.skipped {
                line += " -> error: \(skipped.reason)"
            } else if let actionResult = step.finalActionResult() {
                if !actionResult.success, let error = actionResult.message {
                    line += " -> error: \(error)"
                } else if let delta = actionResult.accessibilityTrace?.endpointDeltaProjection {
                    let kind = Self.compactDeltaKind(delta)
                    line += " -> \(kind)"
                }
            } else if let plannedStep = plan.steps[safe: step.index],
                      let response = step.actionResponse(
                        command: plannedStep.fenceCommand ?? .runHeist,
                        step: plannedStep
                      ),
                      case .error(let message, let details) = response {
                if let details {
                    line += " -> error[\(details.errorCode) \(details.phase.rawValue)]: \(message)"
                } else {
                    line += " -> error: \(message)"
                }
            }
            if let plannedStep = plan.steps[safe: step.index],
               let met = step.expectationMet(for: plannedStep) {
                line += met ? " ✓" : " ✗"
            }
            text += "\n\(line)"
        }
        return text
    }

}

private extension HeistStep {
    var commandName: String {
        switch self {
        case .action(let action): return action.command.wireType.rawValue
        case .wait: return "wait"
        case .warn: return "warn"
        case .fail: return "fail"
        }
    }

    var fenceCommand: TheFence.Command? {
        guard case .action(let action) = self else { return nil }
        return TheFence.Command(clientWireType: action.command.wireType)
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

import Foundation

import TheScore

extension FenceResponse {

    func compactHeistFormatted(
        plan: HeistPlan,
        result: HeistExecutionResult,
        netDelta: AccessibilityTrace.Delta?
    ) -> String {
        let checked = result.projectedExpectationsChecked(for: plan)
        let met = result.projectedExpectationsMet(for: plan)
        var text = "heist: \(result.completedStepCount) steps in \(result.totalTimingMs)ms"
        let failedIndex = result.stoppedFailedIndex
        if let failedIndex { text += " (failed at \(failedIndex))" }
        if checked > 0 { text += " [expectations: \(met)/\(checked)]" }
        if let netDelta { text += " [net: \(Self.compactDeltaKind(netDelta))]" }
        if let lastScreenId = result.flattenedOutcomes.compactMap({
            $0.finalActionResult()?.accessibilityTrace?.endpointScreenIdProjection
        }).last {
            text = "\(lastScreenId) | \(text)"
        }
        for (projectedIndex, projection) in result.projectedOutcomes(for: plan).enumerated() {
            let commandName = projection.step.commandName
            var line = "  [\(projectedIndex)] \(commandName)"
            if let skipped = projection.outcome.skipped {
                line += " -> error: \(skipped.reason)"
            } else if let actionResult = projection.outcome.finalActionResult() {
                if !actionResult.success, let error = actionResult.message {
                    line += " -> error: \(error)"
                } else if let delta = actionResult.accessibilityTrace?.endpointDeltaProjection {
                    let kind = Self.compactDeltaKind(delta)
                    line += " -> \(kind)"
                }
            } else if let response = projection.outcome.actionResponse(
                command: projection.step.fenceCommand ?? .runHeist,
                step: projection.step
            ),
                      case .error(let message, let details) = response {
                if let details {
                    line += " -> error[\(details.errorCode) \(details.phase.rawValue)]: \(message)"
                } else {
                    line += " -> error: \(message)"
                }
            }
            if let met = projection.outcome.expectationMet(for: projection.step) {
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

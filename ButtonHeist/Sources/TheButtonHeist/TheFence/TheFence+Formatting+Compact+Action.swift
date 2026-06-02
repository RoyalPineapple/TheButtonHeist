import Foundation

import TheScore

extension FenceResponse {

    func compactActionResult(command: TheFence.Command, _ result: ActionResult, expectation: ExpectationResult?) -> String {
        let commandName = command.rawValue
        guard result.success else {
            return Self.compactActionFailure(result, commandName: commandName)
        }

        var text: String
        switch result.payload {
        case .rotor(let search):
            text = Self.compactRotor(search)
        case .heistExecution(let heist):
            text = "\(TheFence.Command.runHeist.rawValue): \(heist.steps.count) step(s)"
        case .value, .none:
            if let delta = result.accessibilityTrace?.endpointDeltaProjection {
                text = Self.compactDelta(delta, method: commandName)
            } else {
                text = "\(commandName): ok"
            }
        }
        if let screenId = result.accessibilityTrace?.endpointScreenIdProjection {
            text = "\(screenId) | \(text)"
        }
        if case .value(let value) = result.payload {
            text += "\nvalue: \"\(value)\""
        }
        if let expectation, !expectation.met {
            text += "\n[expectation FAILED: got \(expectation.actual ?? "nil")]"
            if let hint = Self.compactExpectationFailureHint(expectation) {
                text += "\nhint: \(hint)"
            }
        }
        return text
    }

    private static func compactRotor(_ search: RotorResult) -> String {
        var text = "rotor \(search.direction.rawValue): \(search.rotor)"
        if let foundElement = search.foundElement {
            text += "\n  found=\(foundElement.label ?? foundElement.description)"
        }
        if let range = search.textRange {
            text += "\n  textRange=\(range.rangeDescription)"
            if let rangeText = range.text {
                text += " \"\(rangeText)\""
            }
        }
        return text
    }

    private static func compactExpectationFailureHint(_ expectation: ExpectationResult) -> String? {
        guard expectation.predicate == .changed(.screen()), expectation.actual == "elementsChanged" else {
            return nil
        }
        return "screen_changed requires a screen-level transition; " +
            "use elements_changed for same-screen element updates " +
            "or wait when the UI may settle asynchronously"
    }

    private static func compactActionFailure(_ result: ActionResult, commandName: String) -> String {
        let message = result.message ?? commandName
        let errorCode = Self.actionFailureDetails(result)?.errorCode ?? compactActionErrorKind(result).rawValue
        var text = "\(commandName): error[\(errorCode)]: \(message)"
        if let screenId = result.accessibilityTrace?.endpointScreenIdProjection {
            text = "\(screenId) | \(text)"
        }
        return text
    }

    private static func compactActionErrorKind(_ result: ActionResult) -> ErrorKind {
        if let errorKind = result.errorKind {
            return errorKind
        }
        return .actionFailed
    }

}

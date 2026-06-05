import Foundation

import TheScore

extension FenceResponse {

    func compactActionResult(command: TheFence.Command, _ result: ActionResult, expectation: ExpectationResult?) -> String {
        let commandName = command.rawValue
        let screenId = result.accessibilityTrace?.endpointScreenId
        guard result.success else {
            return Self.compactActionFailure(commandName: commandName, result: result, screenId: screenId)
        }

        var text: String
        switch result.payload {
        case .rotor(let rotor):
            text = Self.compactRotor(rotor)
        case .heistExecution(let heist):
            text = "\(TheFence.Command.runHeist.rawValue): \(heist.steps.count) step(s)"
        case .value, .none:
            if let delta = result.accessibilityTrace?.endpointDelta {
                text = Self.compactDelta(delta, method: commandName)
            } else {
                text = "\(commandName): ok"
            }
        }
        if let screenId {
            text = "\(screenId) | \(text)"
        }
        if case .value(let value) = result.payload {
            text += "\nvalue: \"\(value)\""
        }
        if let expectation, !expectation.met {
            text += "\n[expectation FAILED: got \(expectation.actual ?? "nil")]"
            if let hint = Self.expectationFailureHint(expectation) {
                text += "\nhint: \(hint)"
            }
        }
        return text
    }

    /// Recovery hint for a failed expectation. Currently surfaces the
    /// screen-vs-element confusion behind `screen_changed`.
    static func expectationFailureHint(_ expectation: ExpectationResult) -> String? {
        guard expectation.predicate == .changed(.screen()), expectation.actual == "elementsChanged" else {
            return nil
        }
        return "screen_changed requires a screen-level transition; " +
            "use elements_changed for same-screen element updates " +
            "or wait when the UI may settle asynchronously"
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

    private static func compactActionFailure(commandName: String, result: ActionResult, screenId: String?) -> String {
        let message = result.message ?? commandName
        let errorCode = result.publicFailureDetails?.errorCode
            ?? result.publicErrorClass
            ?? ErrorKind.actionFailed.rawValue
        var text = "\(commandName): error[\(errorCode)]: \(message)"
        if let screenId {
            text = "\(screenId) | \(text)"
        }
        return text
    }

}

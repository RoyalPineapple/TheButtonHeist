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
            if let hint = Self.expectationFailureHint(expectation, command: command, result: result) {
                text += "\nhint: \(hint)"
            }
        }
        return text
    }

    /// Recovery hint for failed expectations whose actual observation is easy
    /// to misread without the command semantics.
    static func expectationFailureHint(
        _ expectation: ExpectationResult,
        command: TheFence.Command? = nil,
        result: ActionResult? = nil
    ) -> String? {
        if expectation.predicate == .changed(.screen()), expectation.actual == "elementsChanged" {
            return "screen_changed requires a screen-level transition; " +
                "use elements_changed for same-screen element updates " +
                "or wait when the UI may settle asynchronously"
        }

        guard isActivateNoChangeExpectation(expectation, command: command, result: result) else {
            return nil
        }
        return "activate uses accessibilityActivate() and trusts a true return; " +
            "it does not fall back to a physical tap after semantic activation succeeds. " +
            "If Mechanical.Tap changes the UI, the touch path works but the accessibility activation path is inert or mismatched."
    }

    private static func isActivateNoChangeExpectation(
        _ expectation: ExpectationResult,
        command: TheFence.Command?,
        result: ActionResult?
    ) -> Bool {
        guard expectation.actual == AccessibilityTrace.DeltaKind.noChange.rawValue,
              let predicate = expectation.predicate,
              case .changed = predicate
        else { return false }

        if command == .activate {
            return true
        }
        return result?.method == .activate
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

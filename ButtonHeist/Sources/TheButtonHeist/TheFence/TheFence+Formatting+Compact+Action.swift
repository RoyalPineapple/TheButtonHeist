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
        case .screenshot(let payload):
            text = "screenshot: \(Int(payload.width))x\(Int(payload.height))"
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
        if let activationTrace = result.activationTrace {
            text += "\nactivate: \(Self.compactActivationTrace(activationTrace))"
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
        if expectation.predicate == .change(.screen()), expectation.actual == "elementsChanged" {
            return ".change(.screen()) requires a screen-level transition; " +
                "use .change(.elements()) for same-screen element updates " +
                "or wait when the UI may settle asynchronously"
        }

        guard isActivateNoChangeExpectation(expectation, command: command, result: result) else {
            return nil
        }
        return "activate uses accessibilityActivate() and trusts a true return; " +
            "it does not send activation-point tap dispatch after semantic activation succeeds. " +
            "If Mechanical.Tap changes the UI, the touch path works but the accessibility activation path is inert or mismatched."
    }

    private static func isActivateNoChangeExpectation(
        _ expectation: ExpectationResult,
        command: TheFence.Command?,
        result: ActionResult?
    ) -> Bool {
        guard expectation.actual == AccessibilityTrace.DeltaKind.noChange.rawValue,
              let predicate = expectation.predicate,
              case .changePredicate = predicate
        else { return false }

        if command == .activate {
            return true
        }
        return result?.method == .activate
    }

    static func compactActivationTrace(_ trace: ActivationTrace) -> String {
        var parts = ["ax=\(formatBool(trace.axActivateReturned))"]
        if let retry = trace.retryAxActivateReturned {
            parts.append("retryAx=\(retry)")
        }
        parts.append("tapActivationDispatched=\(trace.tapActivationDispatched)")
        if let point = trace.tapActivationPoint {
            parts.append("tapActivationPoint=\(point.description)")
        }
        if let succeeded = trace.tapActivationSucceeded {
            parts.append("tapActivationSucceeded=\(succeeded)")
        }
        return parts.joined(separator: " ")
    }

    private static func formatBool(_ value: Bool?) -> String {
        value.map(String.init(describing:)) ?? "nil"
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
        guard let failure = result.publicFailureProjection(fallbackMessage: commandName) else {
            return "\(commandName): ok"
        }
        var text = "\(commandName): error[\(failure.compactCode)]: \(failure.message)"
        if let screenId {
            text = "\(screenId) | \(text)"
        }
        return text
    }

}

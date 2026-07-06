import Foundation

import TheScore

extension FenceResponse {

    func compactActionResult(
        command: TheFence.Command,
        _ result: ActionResult,
        expectation: ExpectationResult?,
        profile: ProjectionProfile = .summary
    ) -> String {
        let projection = ActionProjection(
            actionMethod: .fence(command),
            result: result,
            expectation: expectation,
            expectationHint: expectation.flatMap {
                Self.expectationFailureHint($0, command: command, result: result)
            },
            profile: profile
        )
        return Self.compactActionResult(projection)
    }

    static func compactActionResult(_ projection: ActionProjection) -> String {
        guard projection.failure == nil else {
            return compactActionFailure(projection)
        }

        var text: String
        switch projection.payload {
        case .rotor(let rotor):
            text = Self.compactRotor(rotor)
        case .heistExecutionStepCount(let stepCount):
            text = "\(TheFence.Command.runHeist.rawValue): \(stepCount) step(s)"
        case .screenshot(let width, let height):
            text = "screenshot: \(Int(width))x\(Int(height))"
        case .value, .none:
            if let delta = projection.delta {
                text = Self.compactDelta(delta, actionMethod: projection.actionMethod)
            } else {
                text = "\(projection.actionMethod): ok"
            }
        }
        if let screenId = projection.screenId {
            text = "\(screenId) | \(text)"
        }
        if case .value(let value) = projection.payload {
            text += "\nvalue: \"\(value)\""
        }
        if let activationTrace = projection.activationTrace {
            text += "\nactivate: \(Self.compactActivationTrace(activationTrace))"
        }
        if let message = projection.message, message.hasPrefix("Handler: ") {
            text += "\n\(message)"
        }
        if let expectation = projection.expectation, !expectation.met {
            text += "\n[expectation FAILED: got \(expectation.actual ?? "nil")]"
            if let hint = expectation.hint {
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
        if expectation.predicate == .change(.screen()),
           expectation.actual == AccessibilityTrace.DeltaKind.elementsChanged.rawValue {
            return ".screenChanged requires a screen-level transition; " +
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

    private static func compactActionFailure(_ projection: ActionProjection) -> String {
        guard let failure = projection.failure else {
            return "\(projection.actionMethod): ok"
        }
        var text = "\(projection.actionMethod): error[\(failure.compactCode)]: \(failure.message)"
        if let screenId = projection.screenId {
            text = "\(screenId) | \(text)"
        }
        return text
    }

}

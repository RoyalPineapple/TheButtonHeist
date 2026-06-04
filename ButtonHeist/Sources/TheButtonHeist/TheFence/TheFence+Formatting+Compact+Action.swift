import Foundation

import TheScore

extension FenceResponse {

    func compactActionResult(command: TheFence.Command, _ result: ActionResult, expectation: ExpectationResult?) -> String {
        let projection = PublicActionProjection(
            commandName: command.rawValue,
            result: result,
            expectation: expectation
        )
        guard projection.status != .error else {
            return Self.compactActionFailure(projection)
        }

        var text: String
        if let search = projection.rotor {
            text = Self.compactRotor(search)
        } else if let heist = projection.heistExecution {
            text = "\(TheFence.Command.runHeist.rawValue): \(heist.steps.count) step(s)"
        } else {
            if let delta = projection.delta {
                text = Self.compactDelta(delta, method: projection.commandName)
            } else {
                text = "\(projection.commandName): ok"
            }
        }
        if let screenId = projection.screenId {
            text = "\(screenId) | \(text)"
        }
        if let value = projection.value {
            text += "\nvalue: \"\(value)\""
        }
        if let expectation = projection.expectation, expectation.status == .failed {
            text += "\n[expectation FAILED: got \(expectation.actual ?? "nil")]"
            if let hint = expectation.failureHint {
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

    private static func compactActionFailure(_ projection: PublicActionProjection) -> String {
        let message = projection.message ?? projection.commandName
        let errorCode = projection.failure?.compactCode ?? ErrorKind.actionFailed.rawValue
        var text = "\(projection.commandName): error[\(errorCode)]: \(message)"
        if let screenId = projection.screenId {
            text = "\(screenId) | \(text)"
        }
        return text
    }

}

import Foundation
import ThePlans

/// Terminal screenshot evidence captured after heist execution has failed.
package enum HeistFailureCapture: Sendable, Equatable {
    case captured(ScreenPayload)
    case unavailable(kind: ActionFailure.Kind, message: String?)

    package init?(_ result: ActionResult) {
        switch (result.outcome, result.payload) {
        case (.success, .screenshot(let payload?)):
            self = .captured(payload)
        case (.failure(let kind), .screenshot(nil)):
            self = .unavailable(kind: kind, message: result.message)
        default:
            return nil
        }
    }

    package init?(
        executionStep: HeistExecutionStepResult,
        failedPath: HeistExecutionPath
    ) {
        guard executionStep.path == failedPath.failureAction(at: 0),
              executionStep.actionCommand == .takeScreenshot,
              let result = executionStep.actionEvidence?.result
        else { return nil }
        self.init(result)
    }

    package var payload: ScreenPayload? {
        guard case .captured(let payload) = self else { return nil }
        return payload
    }

    package var message: String? {
        guard case .unavailable(_, let message) = self else { return nil }
        return message
    }

    package func executionStep(
        failedPath: HeistExecutionPath
    ) -> HeistExecutionStepResult {
        let result: ActionResult
        switch self {
        case .captured(let payload):
            result = .success(
                payload: .screenshot(payload),
                message: "Captured screenshot \(Int(payload.width))x\(Int(payload.height))"
            )
        case .unavailable(let kind, let message):
            result = .failure(
                payload: .screenshot(nil),
                failureKind: kind,
                message: message
            )
        }

        let command = HeistActionCommand.takeScreenshot
        let evidence = HeistActionEvidence.completed(
            result: result,
            expectation: nil
        )
        let execution: HeistActionExecution
        switch result.outcome {
        case .success:
            execution = .passed(
                command: command,
                evidence: .init(admitted: evidence)
            )
        case .failure:
            execution = .failed(
                command: command,
                evidence: .init(admitted: evidence),
                failure: HeistFailureDetail(
                    category: .action,
                    contract: "failure screenshot action captures visible screen",
                    observed: result.message ?? "screenshot action failed",
                    expected: HeistActionCommandType.takeScreenshot.rawValue
                )
            )
        }
        return .action(
            path: failedPath.failureAction(at: 0),
            execution: execution
        )
    }
}

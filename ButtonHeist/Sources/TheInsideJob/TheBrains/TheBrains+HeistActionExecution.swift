#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    func executeActionStep(
        _ step: ActionStep,
        index: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment
    ) async -> HeistExecutionStepResult {
        await executeStep(
            command: step.command,
            wait: step.expectation,
            index: index,
            path: path,
            start: start,
            runtime: runtime,
            environment: environment
        )
    }

    /// The one execution path behind both an action step and a wait step.
    ///
    /// A step is an optional command followed by an optional predicate wait. An
    /// action step has a command and an optional expectation; a wait step has no
    /// command and the wait is the whole step. The wait is seeded with the
    /// action's own pre-action trace as its change baseline when there was an
    /// action, and with no baseline otherwise — that single difference is what
    /// distinguishes "did my action cause this" from "wait for this to happen".
    func executeStep(
        command: HeistActionCommand?,
        wait: WaitStep?,
        index: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment
    ) async -> HeistExecutionStepResult {
        let kind: HeistExecutionStepKind = command == nil ? .wait : .action

        var actionResult: ActionResult?
        if let command {
            let resolvedCommand: ClientMessage
            do {
                resolvedCommand = try command.resolve(in: environment)
            } catch {
                return HeistExecutionStepResult(
                    index: index,
                    path: path,
                    kind: .action,
                    actionCommand: command,
                    message: "could not resolve heist action command: \(error)",
                    durationMs: elapsedMilliseconds(since: start),
                    stopsHeist: true
                )
            }
            actionResult = await runtime.execute(resolvedCommand)
        }

        // No predicate to wait on, or the command already failed — return the
        // action outcome as-is (a failed action is not re-checked).
        guard let wait, actionResult?.success != false else {
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: kind,
                actionCommand: command,
                actionResult: actionResult,
                durationMs: elapsedMilliseconds(since: start)
            )
        }

        let resolvedWait: ResolvedWaitStep
        do {
            resolvedWait = try wait.resolve(in: environment)
        } catch {
            return waitResolutionFailure(
                command: command,
                actionResult: actionResult,
                index: index,
                path: path,
                start: start,
                error: error
            )
        }

        let receipt = await runtime.wait(resolvedWait, actionResult?.accessibilityTrace)
        return HeistExecutionStepResult(
            index: index,
            path: path,
            kind: kind,
            actionCommand: command,
            actionResult: command == nil ? receipt.actionResult : actionResult,
            expectationActionResult: command == nil ? nil : receipt.actionResult,
            expectation: receipt.expectation,
            durationMs: elapsedMilliseconds(since: start)
        )
    }

    private func waitResolutionFailure(
        command: HeistActionCommand?,
        actionResult: ActionResult?,
        index: Int,
        path: String,
        start: CFAbsoluteTime,
        error: Error
    ) -> HeistExecutionStepResult {
        guard command != nil else {
            // A pure wait whose predicate can't resolve is a hard step failure.
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .wait,
                message: "could not resolve heist wait predicate: \(error)",
                durationMs: elapsedMilliseconds(since: start),
                stopsHeist: true
            )
        }
        // The action already ran; report the unresolvable expectation as a
        // failed expectation on the action step.
        return HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .action,
            actionCommand: command,
            actionResult: actionResult,
            expectationActionResult: ActionResultBuilder(method: .wait).failure(errorKind: .actionFailed),
            expectation: ExpectationResult(
                met: false,
                predicate: nil,
                actual: "could not resolve heist expectation: \(error)"
            ),
            durationMs: elapsedMilliseconds(since: start)
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

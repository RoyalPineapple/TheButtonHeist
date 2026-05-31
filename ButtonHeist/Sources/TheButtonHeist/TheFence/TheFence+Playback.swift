import Foundation
import os.log

import TheScore

private let playbackLogger = Logger(subsystem: "com.buttonheist.fence", category: "playback")

extension TheFence {
    struct ValidatedHeistPlayback {
        let app: String
        let steps: [ValidatedHeistStep]

        var batchRequest: RunBatchRequest {
            RunBatchRequest(
                steps: steps.map(\.preparedStep),
                policy: .stopOnError
            )
        }
    }

    struct ValidatedHeistStep {
        let index: Int
        let target: ElementTarget?
        let preparedStep: RunBatchPreparedStep

        var command: Command { preparedStep.command }
    }

    @ButtonHeistActor
    func readHeistPlayback(contentsOf url: URL) throws -> ValidatedHeistPlayback {
        do {
            let playback = try HeistStore.readHeist(from: url)
            return try validateHeistPlayback(playback)
        } catch StorageError.heistRecording(.heistReadFailed(_, let reason))
            where reason.contains("Unsupported heist file version") {
            throw FenceError.invalidRequest(reason)
        }
    }

    @ButtonHeistActor
    func validateHeistPlayback(_ playback: HeistPlayback) throws -> ValidatedHeistPlayback {
        guard playback.version == HeistPlayback.currentVersion else {
            throw FenceError.invalidRequest(
                "Unsupported heist file version \(playback.version). " +
                    "This Button Heist build supports version \(HeistPlayback.currentVersion). " +
                    "Re-record the heist with the current format."
            )
        }

        let steps = try playback.steps.enumerated().map { index, sourceStep in
            do {
                let parsedRequest = try parseHeistStep(sourceStep, stepIndex: index)
                return ValidatedHeistStep(
                    index: index,
                    target: sourceStep.target,
                    preparedStep: try batchPreparedStep(originalIndex: index, request: parsedRequest)
                )
            } catch let error as SchemaValidationError {
                throw FenceError.invalidRequest("Invalid heist step \(index): \(error.message)")
            } catch let error as MissingElementTarget {
                throw FenceError.invalidRequest(
                    "Invalid heist step \(index): command \"\(error.command)\" requires target object with heistId or matcher fields"
                )
            } catch let error as BatchStepPlanBuildError {
                throw FenceError.invalidRequest("Invalid heist step \(index): \(error.message)")
            }
        }
        return ValidatedHeistPlayback(
            app: playback.app,
            steps: steps
        )
    }
}

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Playback

    func handlePlayHeist(_ request: PlayHeistRequest) async throws -> FenceResponse {
        try playback.begin()
        defer { playback.end() }

        guard let resolvedURL = request.inputPath.validatedOutputURL() else {
            throw FenceError.invalidRequest("Invalid input path: must not be empty or contain '..' components")
        }

        let playbackContract = try readHeistPlayback(contentsOf: resolvedURL)

        if let connectedBundle = handoff.serverInfo?.bundleIdentifier,
           connectedBundle != playbackContract.app {
            playbackLogger.warning(
                "Heist was recorded against \(playbackContract.app) but connected app is \(connectedBundle)"
            )
        }

        let heistName = resolvedURL.deletingPathExtension().lastPathComponent
        let playbackStart = CFAbsoluteTimeGetCurrent()
        let batchResponse = try await handleRunBatch(playbackContract.batchRequest)
        let batchResult = try playbackBatchResult(batchResponse)
        var failure = playbackFailure(contract: playbackContract, batch: batchResult)

        if let currentFailure = failure {
            failure = await currentFailure.withPlaybackDiagnostics(capturingWith: self)
        }

        let totalTimeSeconds = CFAbsoluteTimeGetCurrent() - playbackStart
        let totalTimingMs = Int(totalTimeSeconds * 1000)
        let stepResults = stepResults(contract: playbackContract, batch: batchResult)
        let failedIndex = firstPlaybackFailureIndex(contract: playbackContract, batch: batchResult)
        let completedSteps = stepResults.prefix { $0.passed }.count
        let report = HeistPlaybackReport(
            heistName: heistName,
            app: playbackContract.app,
            totalStepCount: playbackContract.steps.count,
            totalTimeSeconds: totalTimeSeconds,
            steps: stepResults
        )
        return .heistPlayback(
            completedSteps: completedSteps,
            failedIndex: failedIndex,
            totalTimingMs: totalTimingMs,
            failure: failure,
            report: report
        )
    }

    func parseHeistStep(_ sourceStep: HeistStep, stepIndex: Int? = nil) throws -> ParsedRequest {
        let command = try playbackCommand(for: sourceStep, stepIndex: stepIndex)
        try validatePlaybackArguments(sourceStep.arguments, command: command)
        return try parseRequest(
            command: command,
            arguments: try playbackArguments(for: sourceStep)
        )
    }

    private func playbackArguments(for sourceStep: HeistStep) throws -> CommandArgumentEnvelope {
        var values = sourceStep.arguments
        if let expectation = sourceStep.expectation {
            values["expect"] = try heistValue(expectation)
        }
        return CommandArgumentEnvelope(values: values, elementTarget: sourceStep.target)
    }

    private func heistValue(_ expectation: ActionExpectation) throws -> HeistValue {
        let data = try JSONEncoder().encode(expectation)
        return try JSONDecoder().decode(HeistValue.self, from: data)
    }

    private func validatePlaybackArguments(_ arguments: [String: HeistValue], command: Command) throws {
        guard arguments["expect"] == nil else {
            throw SchemaValidationError(
                field: "expect",
                observed: arguments["expect"]?.schemaObservedDescription ?? "missing",
                expected: "top-level heist expectation field"
            )
        }
        let acceptedKeys = Set(
            command.descriptor.parameters
                .map(\.key)
                .filter { !command.descriptor.elementTargetParameterKeys.contains($0) }
                .filter { $0 != "expect" }
        )
        guard let unexpectedKey = arguments.keys.sorted().first(where: { !acceptedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: unexpectedKey,
            observed: arguments[unexpectedKey]?.schemaObservedDescription ?? "missing",
            expected: "valid \(command.rawValue) playback argument"
        )
    }

    private func playbackCommand(for sourceStep: HeistStep, stepIndex: Int?) throws -> Command {
        switch FenceOperationCatalog.normalizePlaybackStep(commandName: sourceStep.command) {
        case .success(let command):
            return command
        case .failure(let error):
            let prefix = stepIndex.map { "Invalid heist step \($0): " } ?? ""
            throw FenceError.invalidRequest(prefix + error.message)
        }
    }

    private struct PlaybackBatchResult {
        let commands: [TheFence.Command]
        let steps: [TheScore.BatchStep]
        let result: BatchExecutionResult
    }

    private func playbackBatchResult(_ response: FenceResponse) throws -> PlaybackBatchResult {
        guard case .batch(let commands, let steps, let result, _) = response else {
            throw FenceError.invalidRequest("Expected batch response while playing heist")
        }
        return PlaybackBatchResult(commands: commands, steps: steps, result: result)
    }

    private func stepResults(
        contract: ValidatedHeistPlayback,
        batch: PlaybackBatchResult
    ) -> [HeistPlaybackReport.StepResult] {
        contract.steps.map { step in
            let outcome = batch.result.steps.first { $0.index == step.index }
            return stepResult(
                step: step,
                timeSeconds: Double(outcome?.durationMs ?? 0) / 1000,
                failure: outcome.flatMap {
                    playbackFailure(
                        step: step,
                        outcome: $0,
                        command: batch.commands[safe: $0.index],
                        typedStep: batch.steps[safe: $0.index]
                    )
                }
            )
        }
    }

    private func stepResult(
        step: ValidatedHeistStep,
        timeSeconds: Double,
        failure: PlaybackFailure?
    ) -> HeistPlaybackReport.StepResult {
        let outcome: HeistPlaybackReport.Outcome
        if let failure {
            outcome = .failed(
                message: failure.errorMessage,
                errorKind: failure.step.command == step.command.rawValue ? failureErrorKind(failure) : nil
            )
        } else {
            outcome = .passed
        }
        return HeistPlaybackReport.StepResult(
            index: step.index,
            command: step.command.rawValue,
            target: step.target,
            timeSeconds: timeSeconds,
            outcome: outcome
        )
    }

    private func failureErrorKind(_ failure: PlaybackFailure) -> HeistPlaybackReport.PlaybackErrorKind? {
        switch failure {
        case .fenceError:
            return .commandError
        case .actionFailed(_, let result, _, _, _):
            guard let errorKind = result.errorKind else { return nil }
            return .action(errorKind)
        case .thrown:
            return .thrown
        }
    }

    private func playbackFailure(contract: ValidatedHeistPlayback, batch: PlaybackBatchResult) -> PlaybackFailure? {
        for step in contract.steps {
            guard let outcome = batch.result.steps.first(where: { $0.index == step.index }),
                  let failure = playbackFailure(
                    step: step,
                    outcome: outcome,
                    command: batch.commands[safe: outcome.index],
                    typedStep: batch.steps[safe: outcome.index]
                  )
            else { continue }
            return failure
        }
        return nil
    }

    private func firstPlaybackFailureIndex(
        contract: ValidatedHeistPlayback,
        batch: PlaybackBatchResult
    ) -> Int? {
        for step in contract.steps {
            guard let outcome = batch.result.steps.first(where: { $0.index == step.index }),
                  playbackFailure(
                    step: step,
                    outcome: outcome,
                    command: batch.commands[safe: outcome.index],
                    typedStep: batch.steps[safe: outcome.index]
                  ) != nil
            else { continue }
            return step.index
        }
        return nil
    }

    private func playbackFailure(
        step: ValidatedHeistStep,
        outcome: BatchExecutionStepResult,
        command: TheFence.Command?,
        typedStep: TheScore.BatchStep?
    ) -> PlaybackFailure? {
        if let skipped = outcome.skipped {
            return .fenceError(
                step: PlaybackFailure.FailedStep(command: step.command.rawValue, target: step.target),
                message: skipped.reason,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        }
        guard let command, let typedStep,
              let response = outcome.actionResponse(command: command, step: typedStep)
        else { return nil }
        return playbackFailure(step: step, response: response)
    }

    private func playbackFailure(step: ValidatedHeistStep, response: FenceResponse) -> PlaybackFailure? {
        let failedStep = PlaybackFailure.FailedStep(command: step.command.rawValue, target: step.target)
        switch response {
        case .error(let message, _):
            return .fenceError(
                step: failedStep,
                message: message,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        case .action(_, let result, let expectation) where !result.success || expectation?.met == false:
            return .actionFailed(
                step: failedStep,
                result: result,
                expectation: expectation,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        default:
            return nil
        }
    }

    fileprivate func captureInterfaceSnapshot() async throws -> Interface {
        let parsed = try parseRequest(
            command: .getInterface,
            arguments: CommandArgumentEnvelope(values: [:])
        )
        let response = try await execute(parsed: parsed)
        guard case .interface(let snapshot, _) = response else {
            throw FenceError.invalidRequest("Expected get_interface response while capturing playback diagnostics")
        }
        return snapshot
    }
}

@ButtonHeistActor
private extension PlaybackFailure {
    func withPlaybackDiagnostics(capturingWith fence: TheFence) async -> PlaybackFailure {
        do {
            let interface = try await fence.captureInterfaceSnapshot()
            return withInterface(interface)
        } catch let fenceError as FenceError {
            if case .invalidRequest = fenceError {
                return withDiagnosticCaptureFailure(fenceError.displayMessage)
            }
            playbackLogger.error(
                "Failed to capture interface for playback diagnostics: \(fenceError.displayMessage)"
            )
            return withDiagnosticCaptureFailure(fenceError.displayMessage)
        } catch {
            playbackLogger.error("Failed to capture interface for playback diagnostics: \(error.displayMessage)")
            return withDiagnosticCaptureFailure(error.displayMessage)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

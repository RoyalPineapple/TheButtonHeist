import Foundation
import os.log

import TheScore

private let playbackLogger = Logger(subsystem: "com.buttonheist.fence", category: "playback")

extension TheFence {
    struct TypedHeistPlayback: Sendable {
        let app: String
        let steps: [PlaybackOperation]

        @ButtonHeistActor
        init(contentsOf url: URL) throws {
            do {
                try self.init(wire: TheBookKeeper.readHeist(from: url))
            } catch BookKeeperError.heistRecording(.scriptReadFailed(_, let reason))
                where reason.contains("Unsupported heist file version") {
                throw FenceError.invalidRequest(reason)
            }
        }

        init(wire playback: HeistPlayback) throws {
            guard playback.version == HeistPlayback.currentVersion else {
                throw FenceError.invalidRequest(
                    "Unsupported heist file version \(playback.version). " +
                        "This Button Heist build supports version \(HeistPlayback.currentVersion). " +
                        "Re-record the heist with the current format."
                )
            }

            app = playback.app
            steps = try playback.steps.enumerated().map { index, evidence in
                try PlaybackOperation(evidence: evidence, index: index)
            }
        }

        var totalStepCount: Int {
            steps.count
        }
    }

    struct PlaybackOperation: Sendable {
        let command: Command
        let target: SemanticActionTarget?
        let payload: PlaybackPayload

        init(evidence: HeistEvidence, index: Int) throws {
            let payload = PlaybackPayload(values: evidence.arguments)
            if payload.values["heistId"] != nil {
                throw FenceError.invalidRequest(
                    "Invalid heist step \(index): top-level heistId is not valid playback identity; use target.matcher and _recorded.heistId metadata"
                )
            }
            let command: Command
            switch FenceOperationCatalog.normalizePlaybackStep(
                commandName: evidence.command,
                arguments: payload.values
            ) {
            case .success(let normalizedCommand):
                command = normalizedCommand
            case .failure(let error):
                throw FenceError.invalidRequest(
                    "Invalid heist step \(index): \(error.message)"
                )
            }

            self.init(
                command: command,
                target: evidence.target,
                payload: payload
            )
        }

        private init(
            command: Command,
            target: SemanticActionTarget?,
            payload: PlaybackPayload
        ) {
            self.command = command
            self.target = target
            self.payload = payload
        }

        var commandName: String {
            command.rawValue
        }

        func normalizedOperation() -> NormalizedOperation {
            NormalizedOperation(
                command: command,
                arguments: requestDecodeInputEnvelope()
            )
        }

        func requestDecodeInputEnvelope() -> CommandArgumentEnvelope {
            var arguments = payload.values.mapValues(CommandArgumentValue.init)

            if let target {
                var matcher: [String: CommandArgumentValue] = [:]
                if let label = target.matcher.label { matcher["label"] = .string(label) }
                if let matchIdentifier = target.matcher.identifier { matcher["identifier"] = .string(matchIdentifier) }
                if let matchValue = target.matcher.value { matcher["value"] = .string(matchValue) }
                if let matchTraits = target.matcher.traits {
                    matcher["traits"] = .array(matchTraits.map { .string($0.rawValue) })
                }
                if let matchExclude = target.matcher.excludeTraits {
                    matcher["excludeTraits"] = .array(matchExclude.map { .string($0.rawValue) })
                }
                var targetArguments: [String: CommandArgumentValue] = ["matcher": .object(matcher)]
                if let ordinal = target.ordinal {
                    targetArguments["ordinal"] = .int(ordinal)
                }
                arguments["target"] = .object(targetArguments)
            }

            return CommandArgumentEnvelope(values: arguments)
        }
    }

    struct PlaybackPayload: Sendable, Equatable {
        let values: [String: HeistValue]

        init(values: [String: HeistValue]) {
            self.values = values
        }

        subscript(key: String) -> HeistValue? {
            values[key]
        }
    }
}

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Playback

    func handlePlayHeist(_ request: PlayHeistRequest) async throws -> FenceResponse {
        try playback.begin()
        defer { playback.end() }

        guard let resolvedURL = bookKeeper.validateOutputPath(request.inputPath) else {
            throw FenceError.invalidRequest("Invalid input path: must not be empty or contain '..' components")
        }

        let typedPlayback = try TypedHeistPlayback(contentsOf: resolvedURL)

        if let connectedBundle = handoff.serverInfo?.bundleIdentifier,
           connectedBundle != typedPlayback.app {
            playbackLogger.warning(
                "Heist was recorded against \(typedPlayback.app) but connected app is \(connectedBundle)"
            )
        }

        let heistName = resolvedURL.deletingPathExtension().lastPathComponent
        let playbackStart = CFAbsoluteTimeGetCurrent()
        var completedSteps = 0
        var failedIndex: Int?
        var failure: PlaybackFailure?
        var stepResults: [HeistPlaybackReport.StepResult] = []

        try await primePlaybackInterface()

        for (index, operation) in typedPlayback.steps.enumerated() {
            let stepStart = CFAbsoluteTimeGetCurrent()
            var stepFailure: PlaybackFailure?

            do {
                let response = try await execute(playback: operation)
                stepFailure = playbackFailure(operation: operation, response: response)
            } catch {
                stepFailure = playbackFailure(operation: operation, error: error)
            }

            let stepTime = CFAbsoluteTimeGetCurrent() - stepStart
            stepResults.append(stepResult(index: index, operation: operation, timeSeconds: stepTime, failure: stepFailure))

            if let stepFailure {
                failedIndex = index
                failure = stepFailure
                break
            }
            completedSteps += 1

            if index < typedPlayback.steps.index(before: typedPlayback.steps.endIndex) {
                try await primePlaybackInterface()
            }
        }

        if let currentFailure = failure {
            failure = await currentFailure.withPlaybackDiagnostics(capturingWith: self)
        }

        let totalTimeSeconds = CFAbsoluteTimeGetCurrent() - playbackStart
        let totalTimingMs = Int(totalTimeSeconds * 1000)
        let report = HeistPlaybackReport(
            heistName: heistName,
            app: typedPlayback.app,
            totalStepCount: typedPlayback.totalStepCount,
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

    private func primePlaybackInterface() async throws {
        _ = try await execute(parsed: defaultGetInterfaceParsedRequest())
    }

    private func stepResult(
        index: Int,
        operation: PlaybackOperation,
        timeSeconds: Double,
        failure: PlaybackFailure?
    ) -> HeistPlaybackReport.StepResult {
        let outcome: HeistPlaybackReport.Outcome
        if let failure {
            outcome = .failed(
                message: failure.errorMessage,
                errorKind: failure.step.command == operation.commandName ? failureErrorKind(failure) : nil
            )
        } else {
            outcome = .passed
        }
        return HeistPlaybackReport.StepResult(
            index: index,
            command: operation.commandName,
            target: operation.target,
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

    private func playbackFailure(operation: PlaybackOperation, response: FenceResponse) -> PlaybackFailure? {
        let failedStep = PlaybackFailure.FailedStep(command: operation.commandName, target: operation.target)
        switch response {
        case .error(let message, _):
            return .fenceError(
                step: failedStep,
                message: message,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        case .action(let result, let expectation) where !result.success || expectation?.met == false:
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

    private func playbackFailure(operation: PlaybackOperation, error: Error) -> PlaybackFailure {
        let failedStep = PlaybackFailure.FailedStep(command: operation.commandName, target: operation.target)
        if let fenceError = error as? FenceError {
            return .fenceError(
                step: failedStep,
                message: fenceError.displayMessage,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        }
        return .thrown(
            step: failedStep,
            error: error.displayMessage,
            interface: nil,
            diagnosticCaptureFailure: nil
        )
    }

    fileprivate func captureInterfaceSnapshot() async throws -> Interface {
        let response = try await execute(parsed: defaultGetInterfaceParsedRequest())
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

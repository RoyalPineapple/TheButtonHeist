import Foundation
import os.log

import TheScore

private let playbackLogger = Logger(subsystem: "com.buttonheist.fence", category: "playback")

extension TheFence {
    struct TypedHeistPlayback: Sendable {
        let app: String
        let steps: [HeistEvidence]

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
                switch FenceOperationCatalog.normalizePlaybackStep(commandName: evidence.command) {
                case .success:
                    return evidence
                case .failure(let error):
                    throw FenceError.invalidRequest(
                        "Invalid heist step \(index): \(error.message)"
                    )
                }
            }
        }

        var totalStepCount: Int {
            steps.count
        }
    }
}

extension HeistEvidence {
    func normalizedPlaybackOperation() throws -> NormalizedOperation {
        let playbackArguments = TheFence.CommandArgumentEnvelope(
            values: arguments,
            elementTarget: target?.playbackElementTarget,
            isPlaybackStep: true
        )
        switch FenceOperationCatalog.normalizePlaybackStep(
            commandName: command,
            arguments: playbackArguments
        ) {
        case .success(let operation):
            return operation
        case .failure(let error):
            throw FenceError.invalidRequest(error.message)
        }
    }
}

private extension SemanticActionTarget {
    var playbackElementTarget: ElementTarget {
        .matcher(matcher, ordinal: ordinal)
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

        for (index, evidence) in typedPlayback.steps.enumerated() {
            let stepStart = CFAbsoluteTimeGetCurrent()
            var stepFailure: PlaybackFailure?

            do {
                let response = try await execute(playback: evidence)
                stepFailure = playbackFailure(evidence: evidence, response: response)
            } catch {
                stepFailure = playbackFailure(evidence: evidence, error: error)
            }

            let stepTime = CFAbsoluteTimeGetCurrent() - stepStart
            stepResults.append(stepResult(index: index, evidence: evidence, timeSeconds: stepTime, failure: stepFailure))

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
        evidence: HeistEvidence,
        timeSeconds: Double,
        failure: PlaybackFailure?
    ) -> HeistPlaybackReport.StepResult {
        let outcome: HeistPlaybackReport.Outcome
        if let failure {
            outcome = .failed(
                message: failure.errorMessage,
                errorKind: failure.step.command == evidence.command ? failureErrorKind(failure) : nil
            )
        } else {
            outcome = .passed
        }
        return HeistPlaybackReport.StepResult(
            index: index,
            command: evidence.command,
            target: evidence.target,
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

    private func playbackFailure(evidence: HeistEvidence, response: FenceResponse) -> PlaybackFailure? {
        let failedStep = PlaybackFailure.FailedStep(command: evidence.command, target: evidence.target)
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

    private func playbackFailure(evidence: HeistEvidence, error: Error) -> PlaybackFailure {
        let failedStep = PlaybackFailure.FailedStep(command: evidence.command, target: evidence.target)
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

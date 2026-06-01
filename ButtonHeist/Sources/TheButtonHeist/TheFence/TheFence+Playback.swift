import Foundation

import TheScore

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

        let heistName = resolvedURL.deletingPathExtension().lastPathComponent
        let playbackStart = CFAbsoluteTimeGetCurrent()
        let executionResult = try await sendAndAwaitHeistExecution(
            playbackContract.plan,
            timeout: Timeouts.longActionSeconds
        )
        let projection = playbackProjection(contract: playbackContract, result: executionResult)
        var failure = projection.failure

        if let currentFailure = failure {
            failure = await currentFailure.withPlaybackDiagnostics(capturingWith: self)
        }

        let totalTimeSeconds = CFAbsoluteTimeGetCurrent() - playbackStart
        let report = HeistPlaybackReport(
            heistName: heistName,
            app: handoff.serverInfo?.bundleIdentifier ?? "unknown",
            totalStepCount: playbackContract.plan.steps.count,
            totalTimeSeconds: totalTimeSeconds,
            steps: projection.stepResults
        )
        return .heistPlayback(
            completedSteps: projection.stepResults.prefix { $0.passed }.count,
            failedIndex: projection.failedIndex,
            totalTimingMs: Int(totalTimeSeconds * 1000),
            failure: failure,
            report: report
        )
    }
}

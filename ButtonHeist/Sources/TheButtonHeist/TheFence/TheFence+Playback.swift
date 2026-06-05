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
        let stepRows = playbackStepRows(result: executionResult)
        var failure = playbackFailure(result: executionResult)

        if let currentFailure = failure {
            failure = await currentFailure.withPlaybackDiagnostics(capturingWith: self)
        }

        let totalTimeSeconds = CFAbsoluteTimeGetCurrent() - playbackStart
        let report = HeistPlaybackReport(
            heistName: heistName,
            app: handoff.serverInfo?.bundleIdentifier ?? "unknown",
            totalStepCount: stepRows.count,
            totalTimeSeconds: totalTimeSeconds,
            steps: stepRows
        )
        return .heistPlayback(
            completedSteps: stepRows.prefix { $0.passed }.count,
            failedIndex: stepRows.first { !$0.passed }?.index,
            totalTimingMs: Int(totalTimeSeconds * 1000),
            failure: failure,
            report: report
        )
    }
}

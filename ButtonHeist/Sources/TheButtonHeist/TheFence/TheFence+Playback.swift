import Foundation
import os.log

import TheScore

private let playbackLogger = Logger(subsystem: "com.buttonheist.fence", category: "playback")

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
        let projection = try playbackProjection(contract: playbackContract, batchResponse: batchResponse)
        var failure = projection.failure

        if let currentFailure = failure {
            failure = await currentFailure.withPlaybackDiagnostics(capturingWith: self)
        }

        let totalTimeSeconds = CFAbsoluteTimeGetCurrent() - playbackStart
        let report = HeistPlaybackReport(
            heistName: heistName,
            app: playbackContract.app,
            totalStepCount: playbackContract.steps.count,
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

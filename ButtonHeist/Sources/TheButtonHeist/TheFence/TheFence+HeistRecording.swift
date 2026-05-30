import Foundation

import TheScore

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Heist Recording

    func handleStartHeist(_ request: StartHeistRequest) throws -> FenceResponse {
        if bookKeeper.manifest == nil {
            try bookKeeper.beginSession(identifier: request.identifier)
        }
        try bookKeeper.startHeistRecording(app: request.app)
        return .heistStarted
    }

    func handleStopHeist(_ request: StopHeistRequest) throws -> FenceResponse {
        guard let resolvedURL = request.outputPath.validatedOutputURL() else {
            throw FenceError.invalidRequest("Invalid output path: must not be empty, contain '..' components, or contain control characters")
        }
        let heist = try bookKeeper.stopHeistRecording()
        try TheBookKeeper.writeHeist(heist, to: resolvedURL)
        return .heistStopped(path: resolvedURL.path, stepCount: heist.steps.count)
    }
}

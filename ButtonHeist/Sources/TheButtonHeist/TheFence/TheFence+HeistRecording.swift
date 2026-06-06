import Foundation

import TheScore

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Heist Recording

    func handleStartHeist(_ request: StartHeistRequest) throws -> FenceResponse {
        try heistStore.startRecording(identifier: request.identifier, app: request.app)
        heistRecording.begin()
        return .heistStarted
    }

    func handleStopHeist(_ request: StopHeistRequest) throws -> FenceResponse {
        guard let resolvedURL = request.outputPath.validatedOutputURL() else {
            throw FenceError.invalidRequest("Invalid output path: must not be empty, contain '..' components, or contain control characters")
        }
        let resolvedSwiftURL: URL?
        if let swiftOutputPath = request.swiftOutputPath {
            guard let url = swiftOutputPath.validatedOutputURL() else {
                throw FenceError.invalidRequest(
                    "Invalid Swift output path: must not be empty, contain '..' components, or contain control characters"
                )
            }
            resolvedSwiftURL = url
        } else {
            resolvedSwiftURL = nil
        }
        let heist = try heistRecording.finish(using: heistStore)
        try HeistFileIO.write(heist, to: resolvedURL)
        if let resolvedSwiftURL {
            let swiftExport = try RecordedHeistSwiftExport().render(heist, sampleRewrite: request.sampleRewrite)
            try HeistFileIO.writeSwiftSource(swiftExport.source, to: resolvedSwiftURL)
        }
        return .heistStopped(path: resolvedURL.path, swiftPath: resolvedSwiftURL?.path, stepCount: heist.body.count)
    }
}

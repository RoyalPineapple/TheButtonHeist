import Foundation

import TheScore

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Recording

    func handleStartRecording(_ config: RecordingConfig) async throws -> FenceResponse {
        guard handoff.isConnected else { throw FenceError.notConnected }
        try await startRecordingAndWait(config: config, timeout: Timeouts.actionSeconds)
        return .ok(message: "Recording started — use stop_recording to retrieve the video")
    }

    func handleStopRecording(_ request: ArtifactRequest) async throws -> FenceResponse {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let recording: RecordingPayload = try await stopRecordingAndWait(timeout: Timeouts.longActionSeconds)
        let metadata = RecordingMetadata(
            width: recording.width,
            height: recording.height,
            duration: recording.duration,
            fps: recording.fps,
            frameCount: recording.frameCount
        )
        let responseOptions = RecordingResponseOptions(
            inlineData: request.inlineData,
            includeInteractionLog: request.includeInteractionLog
        )
        if let expandedResponseError = validateExpandedRecordingResponse(
            recording,
            options: responseOptions
        ) {
            return expandedResponseError
        }
        do {
            let url = try bookKeeper.writeRecordingArtifact(
                base64Data: recording.videoData,
                outputPath: request.outputPath,
                requestId: request.requestId,
                command: .stopRecording,
                metadata: metadata
            )
            if request.inlineData || request.includeInteractionLog {
                let response = FenceResponse.recordingExpanded(
                    path: url.path,
                    payload: recording,
                    options: responseOptions
                )
                if let oversizedResponseError = try validateExpandedRecordingResponseSize(response) {
                    return oversizedResponseError
                }
                return response
            }
            return .recording(path: url.path, payload: recording)
        } catch BookKeeperError.unsafePath {
            throw FenceError.invalidRequest(
                "Invalid output path: must not contain '..' components or control characters"
            )
        } catch BookKeeperError.base64DecodingFailed {
            throw FenceError.serverError(
                ServerError(kind: .recording, message: "Failed to decode video data")
            )
        }
    }

    private func validateExpandedRecordingResponse(
        _ recording: RecordingPayload,
        options: RecordingResponseOptions
    ) -> FenceResponse? {
        guard options.inlineData else { return nil }
        let byteCount = recording.videoData.utf8.count
        guard byteCount <= DecodeLimits.maxInlineRecordingBase64Bytes else {
            return .error(
                "Inline recording payload is too large: \(byteCount) bytes exceeds " +
                    "\(DecodeLimits.maxInlineRecordingBase64Bytes) bytes",
                details: FailureDetails(
                    errorCode: "recording.inline_payload_too_large",
                    phase: .client,
                    retryable: false,
                    hint: "Omit inlineData to receive a recording artifact path."
                )
            )
        }
        return nil
    }

    private func validateExpandedRecordingResponseSize(_ response: FenceResponse) throws -> FenceResponse? {
        let data = try response.jsonData(outputFormatting: [.sortedKeys])
        guard data.count <= DecodeLimits.maxExpandedRecordingResponseBytes else {
            return .error(
                "Expanded recording response is too large: \(data.count) bytes exceeds " +
                    "\(DecodeLimits.maxExpandedRecordingResponseBytes) bytes",
                details: FailureDetails(
                    errorCode: "recording.expanded_response_too_large",
                    phase: .client,
                    retryable: false,
                    hint: "Omit inlineData or includeInteractionLog to receive a recording artifact path and metadata."
                )
            )
        }
        return nil
    }

    // MARK: - Handler: Heist Recording

    func handleStartHeist(_ request: StartHeistRequest) throws -> FenceResponse {
        if bookKeeper.manifest == nil {
            try bookKeeper.beginSession(identifier: request.identifier)
        }
        try bookKeeper.startHeistRecording(app: request.app)
        beginRecordingAccessibilityHistoryRetention()
        return .heistStarted
    }

    func handleStopHeist(_ request: StopHeistRequest) throws -> FenceResponse {
        guard let resolvedURL = request.outputPath.validatedOutputURL() else {
            throw FenceError.invalidRequest("Invalid output path: must not be empty, contain '..' components, or contain control characters")
        }
        defer {
            if !bookKeeper.isRecordingHeist {
                endRecordingAccessibilityHistoryRetention()
            }
        }
        let heist = try bookKeeper.stopHeistRecording()
        try TheBookKeeper.writeHeist(heist, to: resolvedURL)
        return .heistStopped(path: resolvedURL.path, stepCount: heist.steps.count)
    }
}

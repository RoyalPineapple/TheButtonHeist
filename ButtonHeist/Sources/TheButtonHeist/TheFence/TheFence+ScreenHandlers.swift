import Foundation

import TheScore

private extension ScreenPayload {
    func responsePayload(includeInterface: Bool) -> ScreenPayload {
        ScreenPayload(
            pngData: pngData,
            width: width,
            height: height,
            timestamp: timestamp,
            interface: includeInterface ? interface : nil
        )
    }
}

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Screen

    func handleGetScreen(_ request: ScreenRequest) async throws -> FenceResponse {
        let screen = try await sendAndAwaitScreen(.requestScreen, timeout: 30)
        let responsePayload = screen.responsePayload(includeInterface: request.includeInterface)
        let options = ScreenshotResponseOptions(includeInterface: request.includeInterface)

        if request.inlineData {
            let byteCount = screen.pngData.utf8.count
            guard byteCount <= DecodeLimits.maxInlineScreenshotBase64Bytes else {
                return .error(
                    "Inline screenshot payload is too large: \(byteCount) bytes exceeds " +
                        "\(DecodeLimits.maxInlineScreenshotBase64Bytes) bytes",
                    details: FailureDetails(
                        errorCode: "screen.inline_payload_too_large",
                        phase: .client,
                        retryable: false,
                        hint: "Omit inlineData or pass output to receive a screenshot artifact path."
                    )
                )
            }
            return .screenshotData(payload: responsePayload, options: options)
        }

        do {
            let url = try screenshotStore.writeScreenshotArtifact(
                base64Data: screen.pngData,
                outputPath: request.outputPath,
                command: .getScreen
            )
            return .screenshot(path: url.path, payload: responsePayload, options: options)
        } catch StorageError.unsafePath {
            throw FenceError.invalidRequest(
                "Invalid output path: must not contain '..' components or control characters"
            )
        } catch StorageError.base64DecodingFailed {
            throw FenceError.serverError(
                ServerError(kind: .general, message: "Failed to decode screenshot data")
            )
        }
    }
}

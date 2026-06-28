import Foundation

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Screen

    func handleGetScreen(_ request: ScreenRequest) async throws -> FenceResponse {
        let screen = try await sendAndAwaitScreen(.requestScreen, timeout: 30)
        let options = ScreenshotResponseOptions()

        if request.inlineData {
            let byteCount = screen.pngData.utf8.count
            guard byteCount <= DecodeLimits.maxInlineScreenshotBase64Bytes else {
                return .error(
                    "Inline screenshot payload is too large: \(byteCount) bytes exceeds " +
                        "\(DecodeLimits.maxInlineScreenshotBase64Bytes) bytes",
                    details: FailureDetails(code: .screenInlinePayloadTooLarge)
                )
            }
            return .screenshotData(payload: screen, options: options)
        }

        do {
            let url = try screenshotArtifacts.writeScreenshot(
                base64Data: screen.pngData,
                outputPath: request.outputPath,
                command: .getScreen
            )
            return .screenshot(path: url.path, payload: screen, options: options)
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

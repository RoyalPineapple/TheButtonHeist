import Foundation

import TheScore

extension FenceResponse {

    // MARK: - JSON Encoding

    public func jsonData(outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]) throws -> Data {
        try FenceResponsePresenter(profile: .summary).jsonData(
            for: self,
            outputFormatting: outputFormatting
        )
    }

    public func jsonData(
        requestId: PublicRequestId?,
        outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]
    ) throws -> Data {
        return try FenceResponsePresenter(profile: .summary).jsonData(
            for: self,
            requestId: requestId,
            outputFormatting: outputFormatting
        )
    }

    static func jsonEncodingFailureResponse() -> PublicErrorResponse {
        PublicErrorResponse(
            message: PublicJSONSerializer.encodingFailureMessage,
            details: FailureDetails(
                errorCode: "formatting.json_encoding_failed",
                phase: .client,
                retryable: false,
                hint: "Report this diagnostic with the command that produced it."
            )
        )
    }
}

import Foundation

import TheScore

extension FenceResponse {

    // MARK: - JSON Encoding

    public func jsonData(outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]) throws -> Data {
        try PublicJSONSerializer.data(
            encoding: PublicResponseModel(response: self),
            outputFormatting: outputFormatting,
            encodingFailureResponse: Self.jsonEncodingFailureResponse()
        )
    }

    public func jsonData(
        requestId: PublicRequestId?,
        outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]
    ) throws -> Data {
        return try PublicJSONSerializer.data(
            encoding: PublicResponseModel(response: self),
            requestId: requestId,
            outputFormatting: outputFormatting,
            encodingFailureResponse: Self.jsonEncodingFailureResponse()
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

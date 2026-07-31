import Foundation

import TheScore

extension FenceResponse {

    // MARK: - JSON Encoding

    public func jsonData(outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]) throws -> Data {
        try jsonData(profile: .summary, outputFormatting: outputFormatting)
    }

    @_spi(ButtonHeistInternals) public func jsonData(
        profile: ProjectionProfile,
        outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]
    ) throws -> Data {
        try PublicJSONSerializer.data(
            encoding: PublicResponseModel(response: self, profile: profile),
            outputFormatting: outputFormatting,
            encodingFailureResponse: Self.jsonEncodingFailureResponse()
        )
    }

    public func jsonData(
        requestId: PublicRequestId?,
        outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]
    ) throws -> Data {
        try PublicJSONSerializer.data(
            encoding: PublicResponseModel(response: self, profile: .summary),
            requestId: requestId,
            outputFormatting: outputFormatting,
            encodingFailureResponse: Self.jsonEncodingFailureResponse()
        )
    }

    static func jsonEncodingFailureResponse() -> PublicErrorResponse {
        PublicErrorResponse(failure: DiagnosticFailure(
            message: PublicJSONSerializer.encodingFailureMessage,
            details: FailureDetails(code: .formattingJSONEncodingFailed)
        ))
    }
}

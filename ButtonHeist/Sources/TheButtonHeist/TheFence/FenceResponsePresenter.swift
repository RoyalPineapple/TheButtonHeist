import Foundation

@_spi(ButtonHeistInternals) public struct FenceResponsePresenter: Sendable {
    let profile: ProjectionProfile

    public init(profile: ProjectionProfile = .summary) {
        self.profile = profile
    }

    public func compactText(for response: FenceResponse) -> String {
        response.compactFormatted(profile: profile)
    }

    public func humanText(for response: FenceResponse) -> String {
        response.humanFormatted()
    }

    public func jsonData(
        for response: FenceResponse,
        outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]
    ) throws -> Data {
        try PublicJSONSerializer.data(
            encoding: PublicResponseModel(response: response, profile: profile),
            outputFormatting: outputFormatting,
            encodingFailureResponse: FenceResponse.jsonEncodingFailureResponse()
        )
    }

    public func jsonData(
        for response: FenceResponse,
        requestId: PublicRequestId?,
        outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]
    ) throws -> Data {
        try PublicJSONSerializer.data(
            encoding: PublicResponseModel(response: response, profile: profile),
            requestId: requestId,
            outputFormatting: outputFormatting,
            encodingFailureResponse: FenceResponse.jsonEncodingFailureResponse()
        )
    }
}

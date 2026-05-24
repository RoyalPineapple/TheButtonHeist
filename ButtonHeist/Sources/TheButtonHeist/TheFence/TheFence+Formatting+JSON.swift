import Foundation

import TheScore

extension FenceResponse {

    // MARK: - JSON Encoding

    public func jsonData(outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]) throws -> Data {
        try PublicJSONSerializer.data(
            encoding: PublicResponseModel(response: self),
            outputFormatting: outputFormatting,
            fallback: Self.jsonEncodingFailureResponse()
        )
    }

    /// Compatibility adapter for older tests and callers that still inspect
    /// public JSON as Foundation objects. New output code should consume
    /// `jsonData()` or the typed `PublicResponseModel` family instead.
    public func jsonDict() -> [String: Any] {
        PublicJSONSerializer.compatibilityDictionary(
            encoding: PublicResponseModel(response: self),
            fallback: Self.jsonEncodingFailureResponse()
        )
    }

    private static func jsonEncodingFailureResponse() -> PublicErrorResponse {
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

enum PublicJSONSerializer {
    static let encodingFailureMessage =
        "Failed to encode JSON response: response contained non-JSON values"

    static func data<T: Encodable>(
        encoding response: T,
        outputFormatting: JSONEncoder.OutputFormatting,
        fallback: PublicErrorResponse
    ) throws -> Data {
        do {
            return try encode(response, outputFormatting: outputFormatting)
        } catch {
            return try encode(fallback, outputFormatting: outputFormatting)
        }
    }

    static func compatibilityDictionary<T: Encodable>(
        encoding response: T,
        fallback: PublicErrorResponse
    ) -> [String: Any] {
        do {
            return try objectDictionary(encoding: response)
        } catch {
            return (try? objectDictionary(encoding: fallback)) ?? encodingFailureDictionary
        }
    }

    private static func encode<T: Encodable>(
        _ response: T,
        outputFormatting: JSONEncoder.OutputFormatting
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(response)
    }

    private static func objectDictionary<T: Encodable>(encoding response: T) throws -> [String: Any] {
        let data = try encode(response, outputFormatting: [])
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EncodingError.invalidValue(
                String(data: data, encoding: .utf8) ?? "<non-utf8>",
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Encoded public JSON response was not an object"
                )
            )
        }
        return dict
    }

    private static var encodingFailureDictionary: [String: Any] {
        [
            "status": "error",
            "message": encodingFailureMessage,
        ]
    }
}

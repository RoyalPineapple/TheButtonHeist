import Foundation

extension FenceResponse {
    /// Compatibility adapter for older tests and callers that still inspect
    /// public JSON as Foundation objects. New output code should consume
    /// `jsonData()` or the typed `PublicResponseModel` family instead.
    public func jsonDict() -> [String: Any] {
        PublicJSONSerializer.compatibilityDictionary(
            encoding: PublicResponseModel(response: self),
            fallback: Self.jsonEncodingFailureResponse()
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

    static func data<T: Encodable>(
        encoding response: T,
        requestId: Any?,
        outputFormatting: JSONEncoder.OutputFormatting,
        fallback: PublicErrorResponse
    ) throws -> Data {
        let data = try data(
            encoding: response,
            outputFormatting: outputFormatting,
            fallback: fallback
        )
        guard let requestId else { return data }
        return try objectData(
            addingRequestId: requestId,
            to: data,
            outputFormatting: outputFormatting
        )
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
            throw objectEncodingError(data)
        }
        return dict
    }

    private static func objectData(
        addingRequestId requestId: Any,
        to data: Data,
        outputFormatting: JSONEncoder.OutputFormatting
    ) throws -> Data {
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw objectEncodingError(data)
        }
        dict["id"] = requestId
        return try JSONSerialization.data(
            withJSONObject: dict,
            options: jsonSerializationOptions(from: outputFormatting)
        )
    }

    private static func objectEncodingError(_ data: Data) -> EncodingError {
        EncodingError.invalidValue(
            String(data: data, encoding: .utf8) ?? "<non-utf8>",
            EncodingError.Context(
                codingPath: [],
                debugDescription: "Encoded public JSON response was not an object"
            )
        )
    }

    private static func jsonSerializationOptions(
        from outputFormatting: JSONEncoder.OutputFormatting
    ) -> JSONSerialization.WritingOptions {
        var options: JSONSerialization.WritingOptions = []
        if outputFormatting.contains(.prettyPrinted) {
            options.insert(.prettyPrinted)
        }
        if outputFormatting.contains(.sortedKeys) {
            options.insert(.sortedKeys)
        }
        if outputFormatting.contains(.withoutEscapingSlashes) {
            options.insert(.withoutEscapingSlashes)
        }
        return options
    }

    private static var encodingFailureDictionary: [String: Any] {
        [
            "status": "error",
            "message": encodingFailureMessage,
        ]
    }
}

import Foundation
import os.log

import TheScore

private let logger = Logger(subsystem: "com.buttonheist.thefence", category: "formatting")

extension FenceResponse {

    // MARK: - JSON Encoding

    public func jsonData(outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys]) throws -> Data {
        do {
            return try Self.encodePublicJSON(PublicResponseModel(response: self), outputFormatting: outputFormatting)
        } catch {
            return try Self.encodePublicJSON(Self.jsonEncodingFailureResponse(), outputFormatting: outputFormatting)
        }
    }

    public func jsonDict() -> [String: Any] {
        guard let data = try? jsonData(outputFormatting: []),
              let dict = try? Self.jsonObjectDictionary(from: data)
        else { return Self.jsonEncodingFailureDict() }
        return dict
    }

    static func expectationResultDict(_ result: ExpectationResult) -> [String: Any] {
        do {
            return try Self.jsonObjectDictionary(from: PublicExpectationResult(result: result))
        } catch {
            logger.warning("Failed to encode expectation result: \(error.localizedDescription)")
            var fallback: [String: Any] = ["met": result.met]
            if let actual = result.actual {
                fallback["actual"] = actual
            }
            return fallback
        }
    }

    private static func encodePublicJSON<T: Encodable>(
        _ response: T,
        outputFormatting: JSONEncoder.OutputFormatting
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(response)
    }

    private static func jsonObjectDictionary(from data: Data) throws -> [String: Any] {
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

    private static func jsonObjectDictionary<T: Encodable>(from response: T) throws -> [String: Any] {
        let data = try Self.encodePublicJSON(response, outputFormatting: [])
        return try Self.jsonObjectDictionary(from: data)
    }

    private static func jsonEncodingFailureDict() -> [String: Any] {
        [
            "status": "error",
            "message": "Failed to encode JSON response: response contained non-JSON values",
            "errorCode": "formatting.json_encoding_failed",
            "phase": FailurePhase.client.rawValue,
            "retryable": false,
            "hint": "Report this diagnostic with the command that produced it.",
        ]
    }

    private static func jsonEncodingFailureResponse() -> PublicErrorResponse {
        PublicErrorResponse(
            message: "Failed to encode JSON response: response contained non-JSON values",
            details: FailureDetails(
                errorCode: "formatting.json_encoding_failed",
                phase: .client,
                retryable: false,
                hint: "Report this diagnostic with the command that produced it."
            )
        )
    }
}

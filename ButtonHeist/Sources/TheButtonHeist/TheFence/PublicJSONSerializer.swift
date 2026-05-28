import Foundation

enum PublicJSONSerializer {
    static let encodingFailureMessage =
        "Failed to encode JSON response: response contained non-JSON values"

    static func data<T: Encodable>(
        encoding response: T,
        outputFormatting: JSONEncoder.OutputFormatting,
        encodingFailureResponse: PublicErrorResponse
    ) throws -> Data {
        do {
            return try encode(response, outputFormatting: outputFormatting)
        } catch {
            return try encode(encodingFailureResponse, outputFormatting: outputFormatting)
        }
    }

    static func data<T: Encodable>(
        encoding response: T,
        requestId: Any?,
        outputFormatting: JSONEncoder.OutputFormatting,
        encodingFailureResponse: PublicErrorResponse
    ) throws -> Data {
        guard let requestId else {
            return try data(
                encoding: response,
                outputFormatting: outputFormatting,
                encodingFailureResponse: encodingFailureResponse
            )
        }
        let publicRequestId = try PublicRequestId(value: requestId)
        let envelope = PublicResponseEnvelope(requestId: publicRequestId, response: response)
        let failureEnvelope = PublicResponseEnvelope(requestId: publicRequestId, response: encodingFailureResponse)
        do {
            return try encode(envelope, outputFormatting: outputFormatting)
        } catch {
            return try encode(failureEnvelope, outputFormatting: outputFormatting)
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
}

private struct PublicResponseEnvelope<Response: Encodable>: Encodable {
    let requestId: PublicRequestId
    let response: Response

    private enum CodingKeys: String, CodingKey {
        case requestId = "id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestId, forKey: .requestId)
        try response.encode(to: encoder)
    }
}

private enum PublicRequestId: Encodable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(value: Any) throws {
        switch value {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if CFNumberIsFloatType(value) {
                self = .double(value.doubleValue)
            } else {
                self = .integer(value.intValue)
            }
        case is NSNull:
            self = .null
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Public JSON request id must be a JSON scalar"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

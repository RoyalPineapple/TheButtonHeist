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
        requestId: PublicRequestId?,
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
        let envelope = PublicResponseEnvelope(requestId: requestId, response: response)
        let failureEnvelope = PublicResponseEnvelope(requestId: requestId, response: encodingFailureResponse)
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

public enum PublicRequestId: Encodable, Equatable, Sendable {
    case string(String)
    case signedInteger(Int64)
    case unsignedInteger(UInt64)
    case double(Double)
    case null

    public init(value: HeistValue) throws {
        switch value {
        case .string(let value):
            self = .string(value)
        case .int(let value):
            self = .signedInteger(Int64(value))
        case .double(let value):
            guard value.isFinite else {
                throw Self.invalidValue(value)
            }
            self = .double(value)
        case .bool, .array, .object:
            throw Self.invalidValue(value)
        }
    }

    init(value: Any) throws {
        switch value {
        case is NSNull:
            self = .null
        case let value as String:
            self = .string(value)
        case is Bool:
            throw Self.invalidValue(value)
        case let value as Int:
            self = .signedInteger(Int64(value))
        case let value as Int64:
            self = .signedInteger(value)
        case let value as UInt:
            self = .unsignedInteger(UInt64(value))
        case let value as UInt64:
            self = .unsignedInteger(value)
        case let value as Double:
            guard value.isFinite else {
                throw Self.invalidValue(value)
            }
            self = .double(value)
        case let value as Float:
            guard value.isFinite else {
                throw Self.invalidValue(value)
            }
            self = .double(Double(value))
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                throw Self.invalidValue(value)
            } else if CFNumberIsFloatType(value) {
                let doubleValue = value.doubleValue
                guard doubleValue.isFinite else {
                    throw Self.invalidValue(value)
                }
                self = .double(doubleValue)
            } else {
                self = Self.integerValue(from: value)
            }
        default:
            throw Self.invalidValue(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .signedInteger(let value):
            try container.encode(value)
        case .unsignedInteger(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    private static func integerValue(from number: NSNumber) -> PublicRequestId {
        switch String(cString: number.objCType) {
        case "C", "S", "I", "L", "Q":
            return .unsignedInteger(number.uint64Value)
        default:
            return .signedInteger(number.int64Value)
        }
    }

    private static func invalidValue(_ value: Any) -> EncodingError {
        EncodingError.invalidValue(
            value,
            EncodingError.Context(
                codingPath: [],
                debugDescription: "Public JSON request id must be a finite JSON scalar"
            )
        )
    }
}

import Foundation
import MCP
@_spi(ButtonHeistInternals) @_spi(ButtonHeistTooling) import ButtonHeist
import TheScore

enum MCPValueBridge {
    static func commandEnvelope(from arguments: MCPRawArgumentObject?) throws -> TheFence.CommandArgumentEnvelope {
        try validateArgumentObject(arguments)
        return TheFence.CommandArgumentEnvelope(
            values: try heistValues(from: arguments ?? [:])
        )
    }

    static func validateArgumentObject(
        _ arguments: MCPRawArgumentObject?,
        context: String = "MCP arguments",
        maxBytes: Int = PublicJSONInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicJSONInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicJSONInputLimits.maxTotalObjectKeys
    ) throws {
        try PublicJSONValuePreflight.validateObject(
            arguments ?? [:],
            policy: PublicJSONInputPolicy(
                maxBytes: maxBytes,
                maxNestingDepth: maxNestingDepth,
                maxTotalObjectKeys: maxTotalObjectKeys,
                nullHandling: .rejected(expected: "non-null command argument")
            ),
            context: context,
            node: jsonValueNode
        )
    }

    static func heistValues(from arguments: MCPRawArgumentObject) throws -> [String: HeistValue] {
        try arguments.mapValues { try heistValue(from: $0) }
    }

    static func value(from heistValue: HeistValue) -> Value {
        switch heistValue {
        case .string(let value):
            return .string(value)
        case .int(let value):
            return .int(value)
        case .double(let value):
            return .double(value)
        case .bool(let value):
            return .bool(value)
        case .array(let values):
            return .array(values.map { self.value(from: $0) })
        case .object(let values):
            return .object(values.mapValues { self.value(from: $0) })
        }
    }

    static func heistValue(from value: Value) throws -> HeistValue {
        switch value {
        case .null:
            throw PublicJSONInputError("MCP arguments contains null")
        case .bool(let bool):
            return .bool(bool)
        case .int(let int):
            return .int(int)
        case .double(let double):
            return .double(double)
        case .string(let string):
            return .string(string)
        case .data:
            throw PublicJSONInputError("MCP arguments contains binary data")
        case .array(let values):
            return .array(try values.map { try heistValue(from: $0) })
        case .object(let object):
            return .object(try object.mapValues { try heistValue(from: $0) })
        }
    }

    static func value<Payload: Encodable>(
        encoding payload: Payload,
        outputFormatting: JSONEncoder.OutputFormatting = []
    ) throws -> Value {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return try value(decodingJSONData: data)
    }

    static func value(decodingJSONData data: Data) throws -> Value {
        try JSONDecoder().decode(Value.self, from: data)
    }

    static func structuredContent(
        for response: FenceResponse,
        presenter: FenceResponsePresenter
    ) throws -> Value {
        let data = try presenter.jsonData(for: response, outputFormatting: [])
        return try value(decodingJSONData: data)
    }

    static func structuredErrorValue(
        _ failure: DiagnosticFailure,
        presenter: FenceResponsePresenter
    ) -> Value {
        do {
            let data = try presenter.jsonData(
                for: .error(failure),
                outputFormatting: []
            )
            return try value(decodingJSONData: data)
        } catch {
            return errorFallbackValue(for: failure)
        }
    }

    static func jsonValueNode(_ value: Value) -> PublicJSONValueNode<Value> {
        switch value {
        case .null:
            return .null
        case .bool(let bool):
            return .bool(bool)
        case .int(let int):
            return .int(int)
        case .double(let double):
            return .double(double)
        case .string(let string):
            return .string(string)
        case let .data(mimeType, data):
            return .data(mimeType: mimeType, byteCount: data.count)
        case .array(let values):
            return .array(values)
        case .object(let object):
            return .object(object)
        }
    }

    private static func errorFallbackValue(for failure: DiagnosticFailure) -> Value {
        if let encodedValue = try? value(encoding: MCPStructuredErrorFallback(failure: failure)) {
            return encodedValue
        }

        return .object([
            "status": .string("error"),
            "message": .string(failure.message),
            "code": .string(failure.code),
            "kind": .string(failure.kind.rawValue),
            "errorCode": .string(failure.code),
            "phase": .string(failure.phase.rawValue),
            "retryable": .bool(failure.retryable),
            "hint": failure.hint.map(Value.string) ?? .null,
            "details": .object([
                "code": .string(failure.code),
                "kind": .string(failure.kind.rawValue),
                "phase": .string(failure.phase.rawValue),
                "retryable": .bool(failure.retryable),
                "hint": failure.hint.map(Value.string) ?? .null,
            ]),
        ])
    }
}

private struct MCPStructuredErrorFallback: Encodable {
    let status = "error"
    let message: String
    let code: String
    let kind: String
    let errorCode: String
    let phase: String
    let retryable: Bool
    let hint: String?
    let details: Details

    init(failure: DiagnosticFailure) {
        message = failure.message
        code = failure.code
        kind = failure.kind.rawValue
        errorCode = failure.code
        phase = failure.phase.rawValue
        retryable = failure.retryable
        hint = failure.hint
        details = Details(failure: failure)
    }

    struct Details: Encodable {
        let code: String
        let kind: String
        let phase: String
        let retryable: Bool
        let hint: String?

        init(failure: DiagnosticFailure) {
            code = failure.code
            kind = failure.kind.rawValue
            phase = failure.phase.rawValue
            retryable = failure.retryable
            hint = failure.hint
        }
    }
}

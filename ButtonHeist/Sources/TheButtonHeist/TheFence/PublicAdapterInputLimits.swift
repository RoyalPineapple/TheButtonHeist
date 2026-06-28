import Foundation
import TheScore

/// Limits for public machine-input adapters before they materialize recursive
/// JSON structures. Public users hit these through `buttonheist json_lines` and
/// MCP tool arguments.
public enum PublicAdapterInputLimits {
    public static let maxRequestBytes = 1_000_000
    public static let maxNestingDepth = 32
    public static let maxTotalObjectKeys = 1_024
    public static let maxTotalArrayValues = Int.max
    public static let maxStringBytes = Int.max
}

public struct PublicAdapterInputError: Error, LocalizedError, CustomStringConvertible, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
    public var description: String { message }
}

/// Shared limits for recursive public JSON-like inputs.
public struct PublicJSONInputPolicy: Sendable, Equatable {

    public enum NullHandling: Sendable, Equatable {
        case allowed
        case rejected(expected: String)
    }

    public let maxBytes: Int
    public let maxNestingDepth: Int
    public let maxTotalObjectKeys: Int
    public let maxTotalArrayValues: Int
    public let maxStringBytes: Int
    public let nullHandling: NullHandling

    public init(
        maxBytes: Int = PublicAdapterInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicAdapterInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicAdapterInputLimits.maxTotalObjectKeys,
        maxTotalArrayValues: Int = PublicAdapterInputLimits.maxTotalArrayValues,
        maxStringBytes: Int = PublicAdapterInputLimits.maxStringBytes,
        nullHandling: NullHandling = .allowed
    ) {
        self.maxBytes = maxBytes
        self.maxNestingDepth = maxNestingDepth
        self.maxTotalObjectKeys = maxTotalObjectKeys
        self.maxTotalArrayValues = maxTotalArrayValues
        self.maxStringBytes = maxStringBytes
        self.nullHandling = nullHandling
    }
}

/// A limit violation before a public input boundary renders it as an error.
public enum PublicJSONInputViolation: Sendable, Equatable {
    case bytes(max: Int, observed: Int)
    case nestingDepth(max: Int, observed: Int)
    case objectKeyCount(max: Int, observed: Int)
    case arrayValueCount(max: Int, observed: Int)
    case stringBytes(max: Int, observed: Int)
    case nullValue(expected: String)
    case nonFiniteNumber(Double)

    public func publicAdapterMessage(context: String) -> String {
        switch self {
        case .bytes(let max, let observed):
            return "\(context) exceeds \(max) bytes (observed \(observed) bytes)"
        case .nestingDepth(let max, let observed):
            return "\(context) nesting depth exceeds \(max) (observed \(observed))"
        case .objectKeyCount(let max, let observed):
            return "\(context) object key count exceeds \(max) (observed \(observed))"
        case .arrayValueCount(let max, let observed):
            return "\(context) array value count exceeds \(max) (observed \(observed))"
        case .stringBytes(let max, let observed):
            return "\(context) string byte count exceeds \(max) (observed \(observed))"
        case .nullValue:
            return "\(context) contains null"
        case .nonFiniteNumber:
            return "\(context) contains a non-finite number"
        }
    }
}

/// A generic JSON-like value node used by public input preflight traversal.
public enum PublicJSONValueNode<Value> {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(mimeType: String?, byteCount: Int)
    case array([Value])
    case object([String: Value])
}

extension PublicJSONValueNode: Sendable where Value: Sendable {}

/// Converts public JSON-like adapter values into `HeistValue` after applying
/// the shared public input limits.
@_spi(ButtonHeistInternals) public enum PublicHeistValueAdapter {
    public typealias NodeProvider<Value> = PublicJSONValuePreflight.NodeProvider<Value>

    public static func convertObject<Value>(
        _ object: [String: Value],
        policy: PublicJSONInputPolicy = PublicJSONInputPolicy(),
        context: String = "Public JSON input",
        node: @escaping NodeProvider<Value>
    ) throws -> [String: HeistValue] {
        try PublicJSONValuePreflight.validateObject(
            object,
            policy: policy,
            context: context,
            node: node
        )
        return try convertObjectUnchecked(object, fieldPrefix: nil, node: node)
    }

    private static func convertObjectUnchecked<Value>(
        _ object: [String: Value],
        fieldPrefix: String?,
        node: NodeProvider<Value>
    ) throws -> [String: HeistValue] {
        var result: [String: HeistValue] = [:]
        for (key, value) in object {
            let field = fieldPrefix.map { "\($0).\(key)" } ?? key
            result[key] = try convertUnchecked(value, field: field, node: node)
        }
        return result
    }

    private static func convertUnchecked<Value>(
        _ value: Value,
        field: String,
        node: NodeProvider<Value>
    ) throws -> HeistValue {
        switch node(value) {
        case .null:
            throw SchemaValidationError(field: field, observed: "null", expected: "JSON scalar, array, or object")
        case .bool(let bool):
            return .bool(bool)
        case .int(let int):
            return .int(int)
        case .double(let double):
            guard double.isFinite else {
                throw SchemaValidationError(field: field, observed: double, expected: "finite number")
            }
            return .double(double)
        case .string(let string):
            return .string(string)
        case .data:
            throw SchemaValidationError(
                field: field,
                observed: "data",
                expected: "JSON boolean, number, string, array, or object"
            )
        case .array(let values):
            return .array(try values.enumerated().map { index, nested in
                try convertUnchecked(nested, field: "\(field)[\(index)]", node: node)
            })
        case .object(let object):
            return .object(try convertObjectUnchecked(object, fieldPrefix: field, node: node))
        }
    }
}

/// Applies a shared recursive input policy to already-materialized JSON-like values.
public enum PublicJSONValuePreflight {
    public typealias ErrorFactory = @Sendable (PublicJSONInputViolation) -> Error
    public typealias NodeProvider<Value> = @Sendable (Value) -> PublicJSONValueNode<Value>

    public static func validateObject<Value>(
        _ object: [String: Value],
        policy: PublicJSONInputPolicy = PublicJSONInputPolicy(),
        context: String = "Public JSON input",
        makeError: ErrorFactory? = nil,
        node: @escaping NodeProvider<Value>
    ) throws {
        let errorFactory = makeError ?? publicAdapterErrorFactory(context: context)
        var traversal = PublicJSONValueTraversal(policy: policy, makeError: errorFactory, node: node)
        let byteCount = try traversal.jsonEncodedSize(of: object, depth: 1)
        try traversal.validateByteCount(byteCount)
    }

    private static func publicAdapterErrorFactory(context: String) -> ErrorFactory {
        { PublicAdapterInputError($0.publicAdapterMessage(context: context)) }
    }
}

/// Expected root shape for public JSON input.
public enum PublicJSONRoot: Sendable {
    case any
    case array
    case object
}

/// Decodes public JSON input after applying adapter size and shape limits.
public enum PublicJSONInputDecoder {
    public static func decode<T: Decodable>(
        _ type: T.Type,
        from input: String,
        root: PublicJSONRoot = .any,
        context: String = "Public JSON input",
        rootMismatchMessage: String? = nil
    ) throws -> T {
        try decode(
            type,
            from: Data(input.utf8),
            root: root,
            context: context,
            rootMismatchMessage: rootMismatchMessage
        )
    }

    public static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        root: PublicJSONRoot = .any,
        context: String = "Public JSON input",
        rootMismatchMessage: String? = nil
    ) throws -> T {
        try PublicJSONInputPreflight.validate(
            data,
            root: root,
            context: context,
            rootMismatchMessage: rootMismatchMessage
        )
        return try JSONDecoder().decode(type, from: data)
    }

    public static func decodeHeistValue(
        from input: String,
        root: PublicJSONRoot = .any,
        context: String = "Public JSON input",
        rootMismatchMessage: String? = nil
    ) throws -> HeistValue {
        try decode(
            HeistValue.self,
            from: input,
            root: root,
            context: context,
            rootMismatchMessage: rootMismatchMessage
        )
    }
}

public enum PublicJSONInputPreflight {
    public static func validateObject(
        _ input: String,
        context: String = "Public JSON request",
        maxBytes: Int = PublicAdapterInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicAdapterInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicAdapterInputLimits.maxTotalObjectKeys,
        rootMismatchMessage: String? = nil
    ) throws {
        try validate(
            Data(input.utf8),
            root: .object,
            context: context,
            maxBytes: maxBytes,
            maxNestingDepth: maxNestingDepth,
            maxTotalObjectKeys: maxTotalObjectKeys,
            rootMismatchMessage: rootMismatchMessage
        )
    }

    public static func validateArray(
        _ data: Data,
        context: String = "Public JSON input",
        maxBytes: Int = PublicAdapterInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicAdapterInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicAdapterInputLimits.maxTotalObjectKeys,
        rootMismatchMessage: String? = nil
    ) throws {
        try validate(
            data,
            root: .array,
            context: context,
            maxBytes: maxBytes,
            maxNestingDepth: maxNestingDepth,
            maxTotalObjectKeys: maxTotalObjectKeys,
            rootMismatchMessage: rootMismatchMessage
        )
    }

    public static func validate(
        _ data: Data,
        root: PublicJSONRoot = .any,
        context: String = "Public JSON input",
        maxBytes: Int = PublicAdapterInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicAdapterInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicAdapterInputLimits.maxTotalObjectKeys,
        rootMismatchMessage: String? = nil
    ) throws {
        try validate(
            data,
            root: root,
            context: context,
            policy: PublicJSONInputPolicy(
                maxBytes: maxBytes,
                maxNestingDepth: maxNestingDepth,
                maxTotalObjectKeys: maxTotalObjectKeys
            ),
            rootMismatchMessage: rootMismatchMessage
        )
    }

    public static func validate(
        _ data: Data,
        root: PublicJSONRoot = .any,
        context: String = "Public JSON input",
        policy: PublicJSONInputPolicy,
        rootMismatchMessage: String? = nil
    ) throws {
        let byteCount = data.count
        try PublicJSONInputTraversalState.validateByteCount(
            byteCount,
            policy: policy,
            makeError: publicAdapterErrorFactory(context: context)
        )

        var scanner = PublicJSONInputScanner(
            bytes: Array(data),
            context: context,
            policy: policy,
            rootMismatchMessage: rootMismatchMessage,
            makeError: publicAdapterErrorFactory(context: context)
        )
        try scanner.parseRoot(root)
    }

    private static func publicAdapterErrorFactory(context: String) -> PublicJSONValuePreflight.ErrorFactory {
        { PublicAdapterInputError($0.publicAdapterMessage(context: context)) }
    }
}

private struct PublicJSONValueTraversal<Value> {
    private let policy: PublicJSONInputPolicy
    private let makeError: PublicJSONValuePreflight.ErrorFactory
    private let node: PublicJSONValuePreflight.NodeProvider<Value>
    private var state = PublicJSONInputTraversalState()

    init(
        policy: PublicJSONInputPolicy,
        makeError: @escaping PublicJSONValuePreflight.ErrorFactory,
        node: @escaping PublicJSONValuePreflight.NodeProvider<Value>
    ) {
        self.policy = policy
        self.makeError = makeError
        self.node = node
    }

    mutating func jsonEncodedSize(of object: [String: Value], depth: Int) throws -> Int {
        try state.validateDepth(depth, policy: policy, makeError: makeError)
        try state.countObjectKeys(object.count, policy: policy, makeError: makeError)

        var size = 2
        for (index, entry) in object.enumerated() {
            if index > 0 { size = try bounded(size + 1) }
            size = try bounded(size + jsonStringEncodedSize(entry.key) + 1)
            let valueSize = try jsonEncodedSize(of: entry.value, depth: depth + 1)
            size = try bounded(size + valueSize)
        }
        return size
    }

    mutating func validateByteCount(_ byteCount: Int) throws {
        try PublicJSONInputTraversalState.validateByteCount(byteCount, policy: policy, makeError: makeError)
    }

    private mutating func jsonEncodedSize(of value: Value, depth: Int) throws -> Int {
        try state.validateDepth(depth, policy: policy, makeError: makeError)

        switch node(value) {
        case .null:
            try state.validateNull(policy: policy, makeError: makeError)
            return 4
        case .bool(let bool):
            return bool ? 4 : 5
        case .int(let int):
            return try bounded(String(int).utf8.count)
        case .double(let double):
            guard double.isFinite else {
                throw makeError(.nonFiniteNumber(double))
            }
            return try bounded(String(double).utf8.count)
        case .string(let string):
            return try bounded(jsonStringEncodedSize(string))
        case let .data(mimeType, byteCount):
            let prefix = "data:\(mimeType ?? "text/plain");base64,"
            let base64ByteCount = ((byteCount + 2) / 3) * 4
            let encodedSize = Self.jsonStringEncodedSize(prefix) + base64ByteCount
            try state.validateStringBytes(encodedSize, policy: policy, makeError: makeError)
            return try bounded(encodedSize)
        case .array(let values):
            try state.countArrayValues(values.count, policy: policy, makeError: makeError)
            var size = 2
            for (index, nested) in values.enumerated() {
                if index > 0 { size = try bounded(size + 1) }
                let valueSize = try jsonEncodedSize(of: nested, depth: depth + 1)
                size = try bounded(size + valueSize)
            }
            return size
        case .object(let object):
            return try jsonEncodedSize(of: object, depth: depth)
        }
    }

    private mutating func jsonStringEncodedSize(_ value: String) throws -> Int {
        let size = Self.jsonStringEncodedSize(value)
        try state.validateStringBytes(size, policy: policy, makeError: makeError)
        return size
    }

    private func bounded(_ size: Int) throws -> Int {
        try PublicJSONInputTraversalState.validateByteCount(size, policy: policy, makeError: makeError)
        return size
    }

    private static func jsonStringEncodedSize(_ value: String) -> Int {
        var size = 2
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22, 0x5C:
                size += 2
            case 0x00...0x1F:
                size += 6
            default:
                size += scalar.utf8.count
            }
        }
        return size
    }
}

private struct PublicJSONInputTraversalState {
    private var totalObjectKeys = 0
    private var totalArrayValues = 0

    static func validateByteCount(
        _ byteCount: Int,
        policy: PublicJSONInputPolicy,
        makeError: PublicJSONValuePreflight.ErrorFactory
    ) throws {
        guard byteCount <= policy.maxBytes else {
            throw makeError(.bytes(max: policy.maxBytes, observed: byteCount))
        }
    }

    mutating func countObjectKeys(
        _ count: Int,
        policy: PublicJSONInputPolicy,
        makeError: PublicJSONValuePreflight.ErrorFactory
    ) throws {
        totalObjectKeys += count
        guard totalObjectKeys <= policy.maxTotalObjectKeys else {
            throw makeError(.objectKeyCount(max: policy.maxTotalObjectKeys, observed: totalObjectKeys))
        }
    }

    mutating func countArrayValues(
        _ count: Int,
        policy: PublicJSONInputPolicy,
        makeError: PublicJSONValuePreflight.ErrorFactory
    ) throws {
        totalArrayValues += count
        guard totalArrayValues <= policy.maxTotalArrayValues else {
            throw makeError(.arrayValueCount(max: policy.maxTotalArrayValues, observed: totalArrayValues))
        }
    }

    func validateDepth(
        _ depth: Int,
        policy: PublicJSONInputPolicy,
        makeError: PublicJSONValuePreflight.ErrorFactory
    ) throws {
        guard depth <= policy.maxNestingDepth else {
            throw makeError(.nestingDepth(max: policy.maxNestingDepth, observed: depth))
        }
    }

    func validateStringBytes(
        _ byteCount: Int,
        policy: PublicJSONInputPolicy,
        makeError: PublicJSONValuePreflight.ErrorFactory
    ) throws {
        guard byteCount <= policy.maxStringBytes else {
            throw makeError(.stringBytes(max: policy.maxStringBytes, observed: byteCount))
        }
    }

    func validateNull(
        policy: PublicJSONInputPolicy,
        makeError: PublicJSONValuePreflight.ErrorFactory
    ) throws {
        guard case .rejected(let expected) = policy.nullHandling else {
            return
        }
        throw makeError(.nullValue(expected: expected))
    }
}

private struct PublicJSONInputScanner {
    private let bytes: [UInt8]
    private let context: String
    private let policy: PublicJSONInputPolicy
    private let rootMismatchMessage: String?
    private let makeError: PublicJSONValuePreflight.ErrorFactory
    private var index = 0
    private var state = PublicJSONInputTraversalState()

    init(
        bytes: [UInt8],
        context: String,
        policy: PublicJSONInputPolicy,
        rootMismatchMessage: String?,
        makeError: @escaping PublicJSONValuePreflight.ErrorFactory
    ) {
        self.bytes = bytes
        self.context = context
        self.policy = policy
        self.rootMismatchMessage = rootMismatchMessage
        self.makeError = makeError
    }

    mutating func parseRoot(_ root: PublicJSONRoot) throws {
        skipWhitespace()
        switch root {
        case .any:
            guard peek != nil else { throw invalidJSON() }
        case .array:
            guard peek == Self.leftBracket else { throw rootMismatch() }
        case .object:
            guard peek == Self.leftBrace else { throw rootMismatch() }
        }
        try parseValue(depth: 1)
        skipWhitespace()
        guard index == bytes.count else {
            throw invalidJSON()
        }
    }

    private mutating func parseValue(depth: Int) throws {
        try validateDepth(depth)
        skipWhitespace()
        guard let byte = peek else {
            throw invalidJSON()
        }

        switch byte {
        case Self.leftBrace:
            try parseObject(depth: depth)
        case Self.leftBracket:
            try parseArray(depth: depth)
        case Self.quote:
            try parseString()
        case Self.t:
            try consumeLiteral("true")
        case Self.f:
            try consumeLiteral("false")
        case Self.n:
            try consumeLiteral("null")
            try state.validateNull(policy: policy, makeError: makeError)
        case Self.minus, Self.zero...Self.nine:
            try parseNumber()
        default:
            throw invalidJSON()
        }
    }

    private mutating func parseObject(depth: Int) throws {
        try validateDepth(depth)
        try consume(Self.leftBrace)
        skipWhitespace()
        if consumeIfPresent(Self.rightBrace) {
            return
        }

        while true {
            skipWhitespace()
            guard peek == Self.quote else {
                throw invalidJSON()
            }
            try parseString()
            try state.countObjectKeys(1, policy: policy, makeError: makeError)
            skipWhitespace()
            try consume(Self.colon)
            try parseValue(depth: depth + 1)
            skipWhitespace()
            if consumeIfPresent(Self.rightBrace) {
                return
            }
            try consume(Self.comma)
        }
    }

    private mutating func parseArray(depth: Int) throws {
        try validateDepth(depth)
        try consume(Self.leftBracket)
        skipWhitespace()
        if consumeIfPresent(Self.rightBracket) {
            return
        }

        while true {
            try state.countArrayValues(1, policy: policy, makeError: makeError)
            try parseValue(depth: depth + 1)
            skipWhitespace()
            if consumeIfPresent(Self.rightBracket) {
                return
            }
            try consume(Self.comma)
        }
    }

    private mutating func parseString() throws {
        var encodedByteCount = 2
        try consume(Self.quote)
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case Self.quote:
                try state.validateStringBytes(encodedByteCount, policy: policy, makeError: makeError)
                return
            case Self.backslash:
                encodedByteCount += try parseStringEscapeByteCount()
            case 0x00...0x1F:
                throw invalidJSON()
            default:
                encodedByteCount += 1
                continue
            }
        }
        throw invalidJSON()
    }

    private mutating func parseStringEscapeByteCount() throws -> Int {
        guard index < bytes.count else {
            throw invalidJSON()
        }
        let escaped = bytes[index]
        index += 1
        switch escaped {
        case Self.quote, Self.backslash, Self.slash, Self.b, Self.f, Self.n, Self.r, Self.t:
            return 2
        case Self.u:
            guard index + 4 <= bytes.count else {
                throw invalidJSON()
            }
            for _ in 0..<4 {
                guard Self.isHexDigit(bytes[index]) else {
                    throw invalidJSON()
                }
                index += 1
            }
            return 6
        default:
            throw invalidJSON()
        }
    }

    private mutating func parseNumber() throws {
        if consumeIfPresent(Self.minus), peek == nil {
            throw invalidJSON()
        }

        if consumeIfPresent(Self.zero) {
            if let byte = peek, Self.isDigit(byte) {
                throw invalidJSON()
            }
        } else {
            try consumeDigit()
            while let byte = peek, Self.isDigit(byte) {
                index += 1
            }
        }

        if consumeIfPresent(Self.period) {
            try consumeDigit()
            while let byte = peek, Self.isDigit(byte) {
                index += 1
            }
        }

        if consumeIfPresent(Self.e) || consumeIfPresent(Self.capitalE) {
            _ = consumeIfPresent(Self.plus) || consumeIfPresent(Self.minus)
            try consumeDigit()
            while let byte = peek, Self.isDigit(byte) {
                index += 1
            }
        }
    }

    private mutating func consumeDigit() throws {
        guard let byte = peek, Self.isDigit(byte) else {
            throw invalidJSON()
        }
        index += 1
    }

    private mutating func consumeLiteral(_ literal: String) throws {
        for byte in literal.utf8 {
            try consume(byte)
        }
    }

    private mutating func consume(_ byte: UInt8) throws {
        guard consumeIfPresent(byte) else {
            throw invalidJSON()
        }
    }

    private mutating func consumeIfPresent(_ byte: UInt8) -> Bool {
        guard peek == byte else {
            return false
        }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while let byte = peek, Self.isWhitespace(byte) {
            index += 1
        }
    }

    private func validateDepth(_ depth: Int) throws {
        try state.validateDepth(depth, policy: policy, makeError: makeError)
    }

    private var peek: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func invalidJSON() -> PublicAdapterInputError {
        PublicAdapterInputError("\(context) is not valid JSON")
    }

    private func rootMismatch() -> PublicAdapterInputError {
        PublicAdapterInputError(rootMismatchMessage ?? "\(context) is not valid JSON")
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        zero...nine ~= byte
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (zero...nine ~= byte) || (capitalA...capitalF ~= byte) || (a...f ~= byte)
    }

    private static let quote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")
    private static let slash = UInt8(ascii: "/")
    private static let leftBrace = UInt8(ascii: "{")
    private static let rightBrace = UInt8(ascii: "}")
    private static let leftBracket = UInt8(ascii: "[")
    private static let rightBracket = UInt8(ascii: "]")
    private static let colon = UInt8(ascii: ":")
    private static let comma = UInt8(ascii: ",")
    private static let minus = UInt8(ascii: "-")
    private static let plus = UInt8(ascii: "+")
    private static let period = UInt8(ascii: ".")
    private static let zero = UInt8(ascii: "0")
    private static let nine = UInt8(ascii: "9")
    private static let a = UInt8(ascii: "a")
    private static let b = UInt8(ascii: "b")
    private static let capitalA = UInt8(ascii: "A")
    private static let capitalE = UInt8(ascii: "E")
    private static let capitalF = UInt8(ascii: "F")
    private static let e = UInt8(ascii: "e")
    private static let f = UInt8(ascii: "f")
    private static let n = UInt8(ascii: "n")
    private static let r = UInt8(ascii: "r")
    private static let t = UInt8(ascii: "t")
    private static let u = UInt8(ascii: "u")
}

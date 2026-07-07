import Foundation
import TheScore

/// Limits for public machine inputs before they materialize recursive
/// JSON structures. Public users hit these through `buttonheist json_lines` and
/// MCP tool arguments.
public enum PublicJSONInputLimits {
    public static let maxRequestBytes = 1_000_000
    public static let maxNestingDepth = 32
    public static let maxTotalObjectKeys = 1_024
    public static let maxTotalArrayValues = Int.max
    public static let maxStringBytes = Int.max
}

public struct PublicJSONInputError: Error, LocalizedError, CustomStringConvertible, Equatable, Sendable {
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
        maxBytes: Int = PublicJSONInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicJSONInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicJSONInputLimits.maxTotalObjectKeys,
        maxTotalArrayValues: Int = PublicJSONInputLimits.maxTotalArrayValues,
        maxStringBytes: Int = PublicJSONInputLimits.maxStringBytes,
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

    public func publicJSONInputMessage(context: String) -> String {
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
        let errorFactory = makeError ?? publicJSONInputErrorFactory(context: context)
        var traversal = PublicJSONValueTraversal(policy: policy, makeError: errorFactory, node: node)
        let byteCount = try traversal.jsonEncodedSize(of: object, depth: 1)
        try traversal.validateByteCount(byteCount)
    }

    private static func publicJSONInputErrorFactory(context: String) -> ErrorFactory {
        { PublicJSONInputError($0.publicJSONInputMessage(context: context)) }
    }
}

/// Expected root shape for public JSON input.
public enum PublicJSONRoot: Sendable {
    case any
    case array
    case object
}

/// Decodes public JSON input after applying size and shape limits.
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
        maxBytes: Int = PublicJSONInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicJSONInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicJSONInputLimits.maxTotalObjectKeys,
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
        maxBytes: Int = PublicJSONInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicJSONInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicJSONInputLimits.maxTotalObjectKeys,
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
        maxBytes: Int = PublicJSONInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicJSONInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicJSONInputLimits.maxTotalObjectKeys,
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
            makeError: publicJSONInputErrorFactory(context: context)
        )

        try validateRootPrefix(data, root: root, context: context, rootMismatchMessage: rootMismatchMessage)

        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw PublicJSONInputError("\(context) is not valid JSON")
        }

        switch root {
        case .any:
            break
        case .array:
            guard value is [Any] else {
                throw PublicJSONInputError(rootMismatchMessage ?? "\(context) is not valid JSON")
            }
        case .object:
            guard value is [String: Any] else {
                throw PublicJSONInputError(rootMismatchMessage ?? "\(context) is not valid JSON")
            }
        }

        var traversal = PublicJSONParsedInputTraversal(
            policy: policy,
            makeError: publicJSONInputErrorFactory(context: context)
        )
        try traversal.validate(value, depth: 1)
    }

    private static func publicJSONInputErrorFactory(context: String) -> PublicJSONValuePreflight.ErrorFactory {
        { PublicJSONInputError($0.publicJSONInputMessage(context: context)) }
    }

    private static func validateRootPrefix(
        _ data: Data,
        root: PublicJSONRoot,
        context: String,
        rootMismatchMessage: String?
    ) throws {
        guard let expected = openingByte(for: root) else {
            return
        }
        guard firstNonWhitespaceByte(in: data) == expected else {
            throw PublicJSONInputError(rootMismatchMessage ?? "\(context) is not valid JSON")
        }
    }

    private static func openingByte(for root: PublicJSONRoot) -> UInt8? {
        switch root {
        case .any:
            return nil
        case .array:
            return UInt8(ascii: "[")
        case .object:
            return UInt8(ascii: "{")
        }
    }

    private static func firstNonWhitespaceByte(in data: Data) -> UInt8? {
        data.first { byte in
            byte != 0x20 && byte != 0x0A && byte != 0x0D && byte != 0x09
        }
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

private struct PublicJSONParsedInputTraversal {
    private let policy: PublicJSONInputPolicy
    private let makeError: PublicJSONValuePreflight.ErrorFactory
    private var state = PublicJSONInputTraversalState()

    init(
        policy: PublicJSONInputPolicy,
        makeError: @escaping PublicJSONValuePreflight.ErrorFactory
    ) {
        self.policy = policy
        self.makeError = makeError
    }

    mutating func validate(_ value: Any, depth: Int) throws {
        try state.validateDepth(depth, policy: policy, makeError: makeError)

        switch value {
        case is NSNull:
            try state.validateNull(policy: policy, makeError: makeError)
        case let string as String:
            try state.validateStringBytes(jsonStringEncodedSize(string), policy: policy, makeError: makeError)
        case let number as NSNumber:
            guard Double(truncating: number).isFinite else {
                throw makeError(.nonFiniteNumber(Double(truncating: number)))
            }
        case let array as [Any]:
            try state.countArrayValues(array.count, policy: policy, makeError: makeError)
            for element in array {
                try validate(element, depth: depth + 1)
            }
        case let object as [String: Any]:
            try state.countObjectKeys(object.count, policy: policy, makeError: makeError)
            for (key, nested) in object {
                try state.validateStringBytes(jsonStringEncodedSize(key), policy: policy, makeError: makeError)
                try validate(nested, depth: depth + 1)
            }
        default:
            break
        }
    }

    private func jsonStringEncodedSize(_ value: String) -> Int {
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

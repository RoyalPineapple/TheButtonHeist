import Foundation
import TheScore

/// Limits for public machine inputs before they materialize recursive
/// JSON structures. Public users hit these through `buttonheist json_lines` and
/// MCP tool arguments.
public enum PublicJSONInputLimits {
    public static let maxRequestBytes = 1_000_000
    public static let maxNestingDepth = 32
    public static let maxTotalObjectKeys = 1_024
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
    public let nullHandling: NullHandling

    public init(
        maxBytes: Int = PublicJSONInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicJSONInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicJSONInputLimits.maxTotalObjectKeys,
        nullHandling: NullHandling = .allowed
    ) {
        self.maxBytes = maxBytes
        self.maxNestingDepth = maxNestingDepth
        self.maxTotalObjectKeys = maxTotalObjectKeys
        self.nullHandling = nullHandling
    }
}

/// A limit violation before a public input boundary renders it as an error.
public enum PublicJSONInputViolation: Sendable, Equatable {
    case bytes(max: Int, observed: Int)
    case nestingDepth(max: Int, observed: Int)
    case objectKeyCount(max: Int, observed: Int)
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
    public typealias NodeProvider<Value> = @Sendable (Value) -> PublicJSONValueNode<Value>

    public static func validateObject<Value>(
        _ object: [String: Value],
        policy: PublicJSONInputPolicy = PublicJSONInputPolicy(),
        context: String = "Public JSON input",
        mapViolation: (@Sendable (PublicJSONInputViolation) -> Error)? = nil,
        node: @escaping NodeProvider<Value>
    ) throws {
        let failure = mapViolation ?? publicJSONInputFailure(context: context)
        var traversal = PublicJSONValueTraversal(policy: policy, mapViolation: failure, node: node)
        let byteCount = try traversal.jsonEncodedSize(of: object, depth: 1)
        try traversal.validateByteCount(byteCount)
    }

    private static func publicJSONInputFailure(context: String) -> @Sendable (PublicJSONInputViolation) -> Error {
        { PublicJSONInputError($0.publicJSONInputMessage(context: context)) }
    }
}

/// Expected root shape for public JSON input.
public enum PublicJSONRoot: Sendable {
    case any
    case array
    case object
}

private enum PublicJSONParsedValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([PublicJSONParsedValue])
    case object([String: PublicJSONParsedValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let array = try? container.decode([PublicJSONParsedValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: PublicJSONParsedValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func matches(root: PublicJSONRoot) -> Bool {
        switch (root, self) {
        case (.any, _),
             (.array, .array),
             (.object, .object):
            return true
        case (.array, _),
             (.object, _):
            return false
        }
    }
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
            mapViolation: publicJSONInputFailure(context: context)
        )

        try validateRootPrefix(data, root: root, context: context, rootMismatchMessage: rootMismatchMessage)

        let value: PublicJSONParsedValue
        do {
            value = try JSONDecoder().decode(PublicJSONParsedValue.self, from: data)
        } catch {
            throw PublicJSONInputError("\(context) is not valid JSON")
        }

        guard value.matches(root: root) else {
            throw PublicJSONInputError(rootMismatchMessage ?? "\(context) is not valid JSON")
        }

        var traversal = PublicJSONParsedInputTraversal(
            policy: policy,
            mapViolation: publicJSONInputFailure(context: context)
        )
        try traversal.validate(value, depth: 1)
    }

    private static func publicJSONInputFailure(context: String) -> @Sendable (PublicJSONInputViolation) -> Error {
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
    private let mapViolation: @Sendable (PublicJSONInputViolation) -> Error
    private let node: PublicJSONValuePreflight.NodeProvider<Value>
    private var state = PublicJSONInputTraversalState()

    init(
        policy: PublicJSONInputPolicy,
        mapViolation: @escaping @Sendable (PublicJSONInputViolation) -> Error,
        node: @escaping PublicJSONValuePreflight.NodeProvider<Value>
    ) {
        self.policy = policy
        self.mapViolation = mapViolation
        self.node = node
    }

    mutating func jsonEncodedSize(of object: [String: Value], depth: Int) throws -> Int {
        try state.validateDepth(depth, policy: policy, mapViolation: mapViolation)
        try state.countObjectKeys(object.count, policy: policy, mapViolation: mapViolation)

        var size = 2
        for (index, entry) in object.enumerated() {
            if index > 0 { size = try bounded(size + 1) }
            size = try bounded(size + Self.jsonStringEncodedSize(entry.key) + 1)
            let valueSize = try jsonEncodedSize(of: entry.value, depth: depth + 1)
            size = try bounded(size + valueSize)
        }
        return size
    }

    mutating func validateByteCount(_ byteCount: Int) throws {
        try PublicJSONInputTraversalState.validateByteCount(byteCount, policy: policy, mapViolation: mapViolation)
    }

    private mutating func jsonEncodedSize(of value: Value, depth: Int) throws -> Int {
        try state.validateDepth(depth, policy: policy, mapViolation: mapViolation)

        switch node(value) {
        case .null:
            try state.validateNull(policy: policy, mapViolation: mapViolation)
            return 4
        case .bool(let bool):
            return bool ? 4 : 5
        case .int(let int):
            return try bounded(String(int).utf8.count)
        case .double(let double):
            guard double.isFinite else {
                throw mapViolation(.nonFiniteNumber(double))
            }
            return try bounded(String(double).utf8.count)
        case .string(let string):
            return try bounded(Self.jsonStringEncodedSize(string))
        case let .data(mimeType, byteCount):
            let prefix = "data:\(mimeType ?? "text/plain");base64,"
            let base64ByteCount = ((byteCount + 2) / 3) * 4
            let encodedSize = Self.jsonStringEncodedSize(prefix) + base64ByteCount
            return try bounded(encodedSize)
        case .array(let values):
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

    private func bounded(_ size: Int) throws -> Int {
        try PublicJSONInputTraversalState.validateByteCount(size, policy: policy, mapViolation: mapViolation)
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

    static func validateByteCount(
        _ byteCount: Int,
        policy: PublicJSONInputPolicy,
        mapViolation: @Sendable (PublicJSONInputViolation) -> Error
    ) throws {
        guard byteCount <= policy.maxBytes else {
            throw mapViolation(.bytes(max: policy.maxBytes, observed: byteCount))
        }
    }

    mutating func countObjectKeys(
        _ count: Int,
        policy: PublicJSONInputPolicy,
        mapViolation: @Sendable (PublicJSONInputViolation) -> Error
    ) throws {
        totalObjectKeys += count
        guard totalObjectKeys <= policy.maxTotalObjectKeys else {
            throw mapViolation(.objectKeyCount(max: policy.maxTotalObjectKeys, observed: totalObjectKeys))
        }
    }

    func validateDepth(
        _ depth: Int,
        policy: PublicJSONInputPolicy,
        mapViolation: @Sendable (PublicJSONInputViolation) -> Error
    ) throws {
        guard depth <= policy.maxNestingDepth else {
            throw mapViolation(.nestingDepth(max: policy.maxNestingDepth, observed: depth))
        }
    }

    func validateNull(
        policy: PublicJSONInputPolicy,
        mapViolation: @Sendable (PublicJSONInputViolation) -> Error
    ) throws {
        guard case .rejected(let expected) = policy.nullHandling else {
            return
        }
        throw mapViolation(.nullValue(expected: expected))
    }
}

private struct PublicJSONParsedInputTraversal {
    private let policy: PublicJSONInputPolicy
    private let mapViolation: @Sendable (PublicJSONInputViolation) -> Error
    private var state = PublicJSONInputTraversalState()

    init(
        policy: PublicJSONInputPolicy,
        mapViolation: @escaping @Sendable (PublicJSONInputViolation) -> Error
    ) {
        self.policy = policy
        self.mapViolation = mapViolation
    }

    mutating func validate(_ value: PublicJSONParsedValue, depth: Int) throws {
        try state.validateDepth(depth, policy: policy, mapViolation: mapViolation)

        switch value {
        case .null:
            try state.validateNull(policy: policy, mapViolation: mapViolation)
        case .bool:
            break
        case let .number(number):
            guard number.isFinite else {
                throw mapViolation(.nonFiniteNumber(number))
            }
        case .string:
            break
        case let .array(array):
            for element in array {
                try validate(element, depth: depth + 1)
            }
        case let .object(object):
            try state.countObjectKeys(object.count, policy: policy, mapViolation: mapViolation)
            for nested in object.values {
                try validate(nested, depth: depth + 1)
            }
        }
    }
}

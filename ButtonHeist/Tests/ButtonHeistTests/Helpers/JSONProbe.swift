import Foundation

enum JSONValue: Decodable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        if let object = try? decoder.container(keyedBy: JSONCodingKey.self) {
            var values: [String: JSONValue] = [:]
            for key in object.allKeys {
                values[key.stringValue] = try object.decode(JSONValue.self, forKey: key)
            }
            self = .object(values)
            return
        }

        if var array = try? decoder.unkeyedContainer() {
            var values: [JSONValue] = []
            while !array.isAtEnd {
                values.append(try array.decode(JSONValue.self))
            }
            self = .array(values)
            return
        }

        let scalar = try decoder.singleValueContainer()
        if scalar.decodeNil() {
            self = .null
        } else if let value = try? scalar.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? scalar.decode(Int.self) {
            self = .int(value)
        } else if let value = try? scalar.decode(Double.self) {
            self = .double(value)
        } else if let value = try? scalar.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: scalar,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    var typeDescription: String {
        switch self {
        case .object: return "object"
        case .array: return "array"
        case .string: return "string"
        case .int: return "int"
        case .double: return "double"
        case .bool: return "bool"
        case .null: return "null"
        }
    }
}

struct JSONProbe {
    private let value: JSONValue
    private let path: String

    init(_ value: JSONValue, path: String = "$") {
        self.value = value
        self.path = path
    }

    init(data: Data, decoder: JSONDecoder = JSONDecoder()) throws {
        do {
            self.init(try decoder.decode(JSONValue.self, from: data))
        } catch {
            throw JSONProbeFailure(path: "$", reason: "Failed to decode JSON: \(error)")
        }
    }

    func object(_ key: String? = nil) throws -> JSONProbe {
        let probe = try key.map(child) ?? self
        guard case .object = probe.value else {
            throw probe.typeMismatch(expected: "object")
        }
        return probe
    }

    func array(_ key: String? = nil) throws -> [JSONProbe] {
        let probe = try key.map(child) ?? self
        guard case .array(let values) = probe.value else {
            throw probe.typeMismatch(expected: "array")
        }
        return values.enumerated().map { index, value in
            JSONProbe(value, path: "\(probe.path)[\(index)]")
        }
    }

    func string(_ key: String? = nil) throws -> String {
        let probe = try key.map(child) ?? self
        guard case .string(let value) = probe.value else {
            throw probe.typeMismatch(expected: "string")
        }
        return value
    }

    func strings(_ key: String? = nil) throws -> [String] {
        try array(key).map { try $0.string() }
    }

    func bool(_ key: String? = nil) throws -> Bool {
        let probe = try key.map(child) ?? self
        guard case .bool(let value) = probe.value else {
            throw probe.typeMismatch(expected: "bool")
        }
        return value
    }

    func int(_ key: String? = nil) throws -> Int {
        let probe = try key.map(child) ?? self
        guard case .int(let value) = probe.value else {
            throw probe.typeMismatch(expected: "int")
        }
        return value
    }

    func double(_ key: String? = nil) throws -> Double {
        let probe = try key.map(child) ?? self
        switch probe.value {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            throw probe.typeMismatch(expected: "double")
        }
    }

    func assertPresent(_ key: String) throws {
        guard case .object(let object) = value else {
            throw typeMismatch(expected: "object")
        }
        guard object[key] != nil else {
            throw JSONProbeFailure(path: childPath(for: key), reason: "Expected value to be present")
        }
    }

    func assertMissing(_ key: String) throws {
        guard case .object(let object) = value else {
            throw typeMismatch(expected: "object")
        }
        guard object[key] == nil else {
            throw JSONProbeFailure(path: childPath(for: key), reason: "Expected value to be absent")
        }
    }

    func isEmptyObject() throws -> Bool {
        guard case .object(let object) = value else {
            throw typeMismatch(expected: "object")
        }
        return object.isEmpty
    }

    func decode<T: Decodable>(
        _ type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        do {
            let data = try JSONEncoder().encode(value)
            return try decoder.decode(type, from: data)
        } catch {
            throw JSONProbeFailure(path: path, reason: "Failed to decode \(type): \(error)")
        }
    }

    private func child(_ key: String) throws -> JSONProbe {
        guard case .object(let object) = value else {
            throw typeMismatch(expected: "object")
        }
        guard let value = object[key] else {
            throw JSONProbeFailure(path: childPath(for: key), reason: "Missing JSON value")
        }
        return JSONProbe(value, path: childPath(for: key))
    }

    private func childPath(for key: String) -> String {
        path + Self.pathComponent(forKey: key)
    }

    private func typeMismatch(expected: String) -> JSONProbeFailure {
        JSONProbeFailure(
            path: path,
            reason: "Expected \(expected), got \(value.typeDescription)"
        )
    }

    private static func pathComponent(forKey key: String) -> String {
        guard isIdentifier(key) else {
            let escaped = key
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "[\"\(escaped)\"]"
        }
        return ".\(key)"
    }

    private static func isIdentifier(_ key: String) -> Bool {
        guard let first = key.first, first == "_" || first.isLetter else {
            return false
        }
        return key.dropFirst().allSatisfy { character in
            character == "_" || character.isLetter || character.isNumber
        }
    }
}

struct JSONProbeFailure: Error, CustomStringConvertible, LocalizedError, Equatable {
    let path: String
    let reason: String

    var description: String {
        "\(reason) at \(path)"
    }

    var errorDescription: String? {
        description
    }
}

private struct JSONCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

extension JSONValue: Encodable {
    func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let object):
            var container = encoder.container(keyedBy: JSONCodingKey.self)
            for (key, value) in object {
                try container.encode(value, forKey: JSONCodingKey(stringValue: key))
            }
        case .array(let array):
            var container = encoder.unkeyedContainer()
            for value in array {
                try container.encode(value)
            }
        case .string(let string):
            var container = encoder.singleValueContainer()
            try container.encode(string)
        case .int(let int):
            var container = encoder.singleValueContainer()
            try container.encode(int)
        case .double(let double):
            var container = encoder.singleValueContainer()
            try container.encode(double)
        case .bool(let bool):
            var container = encoder.singleValueContainer()
            try container.encode(bool)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

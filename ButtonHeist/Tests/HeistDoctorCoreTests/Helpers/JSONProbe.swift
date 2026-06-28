import Foundation
import Testing

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
        _ = try probe.requireObject()
        return probe
    }

    func array(_ key: String? = nil) throws -> [JSONProbe] {
        let probe = try key.map(child) ?? self
        let values = try probe.requireArray()
        return values.enumerated().map { index, value in
            JSONProbe(value, path: "\(probe.path)[\(index)]")
        }
    }

    func string(_ key: String? = nil) throws -> String {
        let probe = try key.map(child) ?? self
        return try probe.requireString()
    }

    func assertPresent(_ key: String) throws {
        let object = try requireObject()
        #expect(object[key] != nil, "Expected value to be present at \(childPath(for: key))")
    }

    func assertMissing(_ key: String) throws {
        let object = try requireObject()
        #expect(object[key] == nil, "Expected value to be absent at \(childPath(for: key))")
    }

    private func child(_ key: String) throws -> JSONProbe {
        let object = try requireObject()
        let value = try #require(object[key], "Missing JSON value at \(childPath(for: key))")
        return JSONProbe(value, path: childPath(for: key))
    }

    private func childPath(for key: String) -> String {
        path + Self.pathComponent(forKey: key)
    }

    private func requireObject() throws -> [String: JSONValue] {
        try #require(objectValue, "\(typeMismatchDescription(expected: "object"))")
    }

    private func requireArray() throws -> [JSONValue] {
        try #require(arrayValue, "\(typeMismatchDescription(expected: "array"))")
    }

    private func requireString() throws -> String {
        try #require(stringValue, "\(typeMismatchDescription(expected: "string"))")
    }

    private var objectValue: [String: JSONValue]? {
        guard case .object(let object) = value else {
            return nil
        }
        return object
    }

    private var arrayValue: [JSONValue]? {
        guard case .array(let array) = value else {
            return nil
        }
        return array
    }

    private var stringValue: String? {
        guard case .string(let string) = value else {
            return nil
        }
        return string
    }

    private func typeMismatchDescription(expected: String) -> String {
        "Expected \(expected), got \(value.typeDescription) at \(path)"
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

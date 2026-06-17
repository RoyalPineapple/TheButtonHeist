import Foundation
import TheScore

extension TheFence {

    struct ExpectationPayload {
        let expectation: AccessibilityPredicate?
        let timeout: Double?

        init(expectation: AccessibilityPredicate?, timeout: Double?) {
            self.expectation = expectation
            self.timeout = timeout
        }

        init(arguments: CommandArgumentEnvelope) throws {
            self.init(
                expectation: try Self.parseExpectation(arguments.argumentValues["expect"]),
                timeout: try arguments.schemaNumber("timeout")
            )
        }

        var postActionValidationTimeout: Double? {
            expectation == nil ? nil : timeout
        }

        static func parseExpectation(_ value: HeistValue?) throws -> AccessibilityPredicate? {
            guard let value else { return nil }
            return try parsePredicate(value)
        }

        /// Parse a required `AccessibilityPredicate` object (the `wait`
        /// `predicate` field). Throws if missing or malformed.
        static func parseRequiredPredicate(_ value: HeistValue?) throws -> AccessibilityPredicate {
            guard let value else {
                throw FenceError.invalidRequest("wait requires a \"predicate\" object")
            }
            return try parsePredicate(value)
        }

        static func parsePredicate(_ value: HeistValue) throws -> AccessibilityPredicate {
            guard case .object(let object) = value else {
                throw FenceError.invalidRequest(
                    "Invalid predicate type: expected object with a \"type\" discriminator"
                )
            }
            guard let type = object["type"] else {
                throw FenceError.invalidRequest(
                    "Predicate object requires a \"type\" discriminator " +
                        "(e.g. {\"type\": \"present\", …}). " +
                        "Got keys: \(object.keys.sorted())"
                )
            }
            guard case .string = type else {
                throw FenceError.invalidRequest(
                    "Predicate object requires a string \"type\" discriminator " +
                        "(e.g. {\"type\": \"present\", …}). " +
                        "Got type: \(type.schemaObservedDescription)"
                )
            }
            try validatePredicateStringMatchObjects(value, path: [])
            do {
                let data = try JSONEncoder().encode(value)
                return try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
            } catch let error as DecodingError {
                throw Self.expectationDecodingFailure(error, value: value)
            }
        }

        private static func validatePredicateStringMatchObjects(_ value: HeistValue, path: [String]) throws {
            guard case .object(let object) = value else { return }
            if let element = object["element"] {
                try validateElementPredicateStringMatchObjects(element, path: path + ["element"])
            }
            if let states = object["states"], case .array(let values) = states {
                for (index, child) in values.enumerated() {
                    try validatePredicateStringMatchObjects(child, path: path + ["states[\(index)]"])
                }
            }
            if let whereValue = object["where"] {
                try validatePredicateStringMatchObjects(whereValue, path: path + ["where"])
            }
        }

        private static func validateElementPredicateStringMatchObjects(_ value: HeistValue, path: [String]) throws {
            guard case .object(let object) = value else { return }
            for key in ["label", "identifier", "value"] {
                guard let match = object[key] else { continue }
                guard case .object = match else {
                    throw SchemaValidationError(
                        field: (path + [key]).joined(separator: "."),
                        observed: match.schemaObservedDescription,
                        expected: "StringMatch object with mode and value"
                    )
                }
            }
        }

        private static func expectationDecodingFailure(_ error: DecodingError, value: HeistValue) -> Error {
            switch error {
            case .typeMismatch(let type, let context):
                return SchemaValidationError(
                    field: expectationField(codingPath: context.codingPath),
                    observed: expectationValue(value, at: context.codingPath)?.schemaObservedDescription
                        ?? value.schemaObservedDescription,
                    expected: schemaExpectedDescription(for: type)
                )
            case .valueNotFound(let type, let context):
                return SchemaValidationError(
                    field: expectationField(codingPath: context.codingPath),
                    observed: "missing",
                    expected: schemaExpectedDescription(for: type)
                )
            case .keyNotFound(let key, let context):
                return SchemaValidationError(
                    field: expectationField(codingPath: context.codingPath + [key]),
                    observed: "missing",
                    expected: "present"
                )
            case .dataCorrupted(let context):
                return FenceError.invalidRequest(context.debugDescription)
            @unknown default:
                return FenceError.invalidRequest(String(describing: error))
            }
        }

        private static func expectationField(codingPath: [CodingKey]) -> String {
            var path = ""
            for key in codingPath {
                if let index = key.intValue {
                    path += "[\(index)]"
                } else if path.isEmpty {
                    path = key.stringValue
                } else {
                    path += ".\(key.stringValue)"
                }
            }
            return path.isEmpty ? "expect" : path
        }

        private static func expectationValue(_ value: HeistValue, at codingPath: [CodingKey]) -> HeistValue? {
            codingPath.reduce(Optional(value)) { current, key in
                guard let current else { return nil }
                if let index = key.intValue {
                    guard case .array(let values) = current, values.indices.contains(index) else { return nil }
                    return values[index]
                }
                guard case .object(let values) = current else { return nil }
                return values[key.stringValue]
            }
        }

        private static func schemaExpectedDescription(for type: Any.Type) -> String {
            switch type {
            case is String.Type:
                return "string"
            case is Bool.Type:
                return "boolean"
            case is Int.Type:
                return "integer"
            case is Double.Type:
                return "number"
            case is [AccessibilityPredicate].Type:
                return "array of predicate objects"
            case is ElementPredicate.Type, is AccessibilityPredicate.Type:
                return "object"
            default:
                if String(describing: type) == "Dictionary<String, Any>" {
                    return "object"
                }
                return String(describing: type)
            }
        }
    }

    // MARK: - Expectation Parsing

    /// Parse compact command input into the same typed expectation argument
    /// shape accepted by direct, MCP, batch, and heist request decoding.
    public nonisolated static func parseExpectationArgument(_ rawValue: String) throws -> HeistValue {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" else {
            throw FenceError.invalidRequest("Expected expectation JSON object")
        }

        let value: HeistValue
        do {
            value = try JSONDecoder().decode(HeistValue.self, from: Data(trimmed.utf8))
        } catch {
            throw FenceError.invalidRequest("Invalid expectation JSON: \(error.localizedDescription)")
        }

        guard case .object = value else {
            throw FenceError.invalidRequest("Expected expectation JSON to decode as an object")
        }
        return value
    }
}

import Foundation
import TheScore

extension TheFence {

    struct ExpectationPayload {
        let expectation: ActionExpectation?
        let timeout: Double?

        init(expectation: ActionExpectation?, timeout: Double?) {
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

        static func parseExpectation(_ value: HeistValue?) throws -> ActionExpectation? {
            guard let value else { return nil }
            guard case .object(let object) = value else {
                throw FenceError.invalidRequest(
                    "Invalid expectation type: expected object with a \"type\" discriminator"
                )
            }
            guard let type = object["type"] else {
                throw FenceError.invalidRequest(
                    "Expectation object requires a \"type\" discriminator " +
                        "(e.g. {\"type\": \"element_updated\", …}). " +
                        "Got keys: \(object.keys.sorted())"
                )
            }
            guard case .string = type else {
                throw FenceError.invalidRequest(
                    "Expectation object requires a string \"type\" discriminator " +
                        "(e.g. {\"type\": \"element_updated\", …}). " +
                        "Got type: \(type.schemaObservedDescription)"
                )
            }
            do {
                let data = try JSONEncoder().encode(value)
                return try JSONDecoder().decode(ActionExpectation.self, from: data)
            } catch let error as DecodingError {
                throw Self.expectationDecodingFailure(error, value: value)
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
            case is [ActionExpectation].Type:
                return "array of expectation objects"
            case is ElementMatcher.Type, is ActionExpectation.Type:
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
    /// shape accepted by direct, MCP, batch, and playback request decoding.
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

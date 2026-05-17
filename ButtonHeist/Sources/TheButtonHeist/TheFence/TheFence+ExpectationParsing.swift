import Foundation

import TheScore

extension TheFence {

    // MARK: - Expectation Parsing

    /// Parse the `"expect"` field off a CLI/MCP request dictionary into a typed
    /// `ActionExpectation`. Returns `nil` when no expectation is set. The
    /// accepted shape is the discriminator object used by `ActionExpectation`'s
    /// wire encoding: `{"type": "...", …}`. Compound expectations use object
    /// sub-expectations with `{"type": "compound", "expectations": [...]}`.
    func parseExpectation(_ dictionary: [String: Any]) throws -> ActionExpectation? {
        guard let expect = dictionary["expect"] else { return nil }
        return try FenceExpectationParser.decode(expect)
    }
}

private enum FenceExpectationParser {
    static func decode(_ value: Any) throws -> ActionExpectation {
        if let object = value as? [String: Any] {
            return try decode(object)
        }
        throw FenceError.invalidRequest(
            "Invalid expectation type: expected object with a \"type\" discriminator"
        )
    }

    static func decode(_ object: [String: Any]) throws -> ActionExpectation {
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            return try JSONDecoder().decode(ActionExpectation.self, from: data)
        } catch let error as FenceError {
            throw error
        } catch let error as DecodingError {
            throw FenceError.invalidRequest(message(for: error, object: object))
        } catch {
            throw FenceError.invalidRequest(
                "Invalid expectation object: expected JSON-compatible values"
            )
        }
    }

    private static var validTypes: String {
        ActionExpectation.wireTypeValues.joined(separator: ", ")
    }

    private static func message(for error: DecodingError, object: [String: Any]) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return missingKeyMessage(key.stringValue, object: objectFor(context: context, in: object) ?? object)
        case .dataCorrupted(let context):
            if let message = discriminatorMessage(context: context, root: object) {
                return message
            }
            return context.debugDescription
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context):
            if isCompoundExpectationElement(context: context) {
                return "compound expectations must be objects with a \"type\" discriminator"
            }
            return context.debugDescription
        @unknown default:
            return "Invalid expectation object"
        }
    }

    private static func missingKeyMessage(_ key: String, object: [String: Any]) -> String {
        if key == "type" {
            return "Expectation object requires a \"type\" discriminator " +
                "(e.g. {\"type\": \"element_updated\", …}). " +
                "Got keys: \(object.keys.sorted())"
        }
        if key == "matcher", let typeString = object["type"] as? String {
            return "\(typeString) requires a \"matcher\" object"
        }
        if key == "expectations" {
            return "compound requires an \"expectations\" array"
        }
        return "Expectation object requires a \"\(key)\" field"
    }

    private static func discriminatorMessage(context: DecodingError.Context, root: [String: Any]) -> String? {
        let object = objectFor(context: context, in: root) ?? root
        if let typeString = object["type"] as? String,
           !ActionExpectation.wireTypeValues.contains(typeString) {
            return "Unknown expectation type: \"\(typeString)\". Valid: \(validTypes)"
        }
        if let propertyString = object["property"] as? String,
           ElementProperty(rawValue: propertyString) == nil {
            return "Unknown element property: \"\(propertyString)\". Valid: \(validProperties)"
        }
        return nil
    }

    private static var validProperties: String {
        ElementProperty.allCases.map(\.rawValue).joined(separator: ", ")
    }

    private static func isCompoundExpectationElement(context: DecodingError.Context) -> Bool {
        context.codingPath.contains { $0.stringValue == "expectations" }
    }

    private static func objectFor(context: DecodingError.Context, in root: [String: Any]) -> [String: Any]? {
        object(at: context.codingPath, in: root) ?? object(at: Array(context.codingPath.dropLast()), in: root)
    }

    private static func object(at codingPath: [any CodingKey], in root: [String: Any]) -> [String: Any]? {
        var current: Any = root
        for key in codingPath {
            if let index = key.intValue {
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            } else {
                guard let dictionary = current as? [String: Any],
                      let value = dictionary[key.stringValue] else { return nil }
                current = value
            }
        }
        return current as? [String: Any]
    }
}

import Foundation
import ThePlans

import TheScore

extension TheFence.CommandArgumentEnvelope {

    @ButtonHeistActor
    func decodedElementTarget() throws -> ElementTarget? {
        if let elementTarget {
            if keys.contains("target") {
                throw SchemaValidationError(
                    field: field("target"),
                    observed: observedDescription(for: "target") ?? "object",
                    expected: "not present when typed element target is provided"
                )
            }
            return elementTarget
        }
        guard let target = try schemaDictionary("target") else { return nil }
        return try target.decodeElementTargetPayload()
    }

    @ButtonHeistActor
    func requiredElementTarget(command: TheFence.Command) throws -> ElementTarget {
        guard let target = try decodedElementTarget() else {
            throw TheFence.MissingElementTarget(command: command.rawValue)
        }
        return target
    }

    @ButtonHeistActor
    func scrollContainerSelection() throws -> ScrollContainerSelection {
        if let containerName = try optionalContainerName("container") {
            if try decodedElementTarget() != nil {
                throw SchemaValidationError(
                    field: field("container"),
                    observed: observedDescription(for: "container") ?? "string",
                    expected: "not present when an element target is provided"
                )
            }
            return .container(containerName)
        }
        if let elementTarget = try decodedElementTarget() {
            return .element(elementTarget)
        }
        return .visibleContainer
    }

    func optionalContainerName(_ key: String) throws -> ContainerName? {
        guard let value = try schemaString(key) else { return nil }
        guard let containerName = ContainerName(parsing: value) else {
            throw SchemaValidationError(
                field: field(key),
                observed: value.isEmpty ? "string \"\"" : "blank string",
                expected: "non-empty container name"
            )
        }
        return containerName
    }

    func nonEmptyString(_ key: String) throws -> String {
        let value = try requiredSchemaString(key)
        if value.isEmpty {
            throw SchemaValidationError(field: field(key), observed: "string \"\"", expected: "non-empty string")
        }
        return value
    }

    func optionalNonEmptyString(_ key: String) throws -> String? {
        guard let value = try schemaString(key) else { return nil }
        if value.isEmpty {
            throw SchemaValidationError(field: field(key), observed: "string \"\"", expected: "non-empty string")
        }
        return value
    }

    func decodeElementTargetPayload() throws -> ElementTarget {
        try requireObjectStringMatchFields()
        let value = HeistValue.object(argumentValues)
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(ElementTarget.self, from: data)
        } catch let error as DecodingError {
            throw elementTargetPayloadFailure(error, value: value)
        } catch {
            throw FenceError.invalidRequest(String(describing: error))
        }
    }

    private func requireObjectStringMatchFields() throws {
        for field in ElementTarget.inlineSchemaFields where field.kind == .stringMatch {
            guard let value = argumentValues[field.name] else { continue }
            guard case .object = value else {
                throw SchemaValidationError(
                    field: self.field(field.name),
                    observed: value.schemaObservedDescription,
                    expected: "StringMatch object with mode and value"
                )
            }
        }
    }

    private func elementTargetPayloadFailure(_ error: DecodingError, value: HeistValue) -> Error {
        switch error {
        case .typeMismatch(let type, let context):
            return SchemaValidationError(
                field: field(codingPath: context.codingPath),
                observed: payloadValue(at: context.codingPath, in: value)?.schemaObservedDescription
                    ?? value.schemaObservedDescription,
                expected: expectedDescription(for: type)
            )
        case .valueNotFound(let type, let context):
            return SchemaValidationError(
                field: field(codingPath: context.codingPath),
                observed: "missing",
                expected: expectedDescription(for: type)
            )
        case .keyNotFound(let key, let context):
            return SchemaValidationError(
                field: field(codingPath: context.codingPath + [key]),
                observed: "missing",
                expected: "present"
            )
        case .dataCorrupted(let context):
            let field = field(codingPath: context.codingPath)
            guard field != "arguments" else {
                return FenceError.invalidRequest(context.debugDescription)
            }
            return SchemaValidationError(
                field: field,
                observed: payloadValue(at: context.codingPath, in: value)?.schemaObservedDescription ?? "invalid value",
                expected: context.debugDescription
            )
        @unknown default:
            return FenceError.invalidRequest(String(describing: error))
        }
    }

    private func field(codingPath: [CodingKey]) -> String {
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
        guard !path.isEmpty else { return "target" }
        return field(path)
    }

    private func payloadValue(at codingPath: [CodingKey], in value: HeistValue) -> HeistValue? {
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

    private func expectedDescription(for type: Any.Type) -> String {
        switch type {
        case is String.Type:
            return "string"
        case is Bool.Type:
            return "boolean"
        case is Int.Type:
            return "integer"
        case is Double.Type:
            return "number"
        default:
            if String(describing: type).hasPrefix("Array<") {
                return "array"
            }
            if String(describing: type) == "Dictionary<String, Any>" {
                return "object"
            }
            return String(describing: type)
        }
    }

}

extension TheFence {

    nonisolated static func parseTraitNames(_ names: [String]?, field: String) throws -> [HeistTrait]? {
        try names?.enumerated().map { index, name in
            guard let trait = HeistTrait(rawValue: name) else {
                throw SchemaValidationError(
                    field: "\(field)[\(index)]",
                    observed: "string \"\(name)\"",
                    expected: SchemaValidationError.expectedEnum(HeistTrait.self)
                )
            }
            return trait
        }
    }
}

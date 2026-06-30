import Foundation
import ThePlans

import TheScore

extension TheFence.CommandArgumentEnvelope {

    @ButtonHeistActor
    func decodedElementTarget() throws -> ElementTarget? {
        guard let target = try schemaDictionary(.target) else { return nil }
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
        if let containerName = try optionalContainerName(.container) {
            if try decodedElementTarget() != nil {
                throw SchemaValidationError(
                    field: field(.container),
                    observed: observedDescription(for: .container) ?? "string",
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

    func optionalContainerName(_ key: FenceParameterKey) throws -> ContainerName? {
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

    func nonEmptyString(_ key: FenceParameterKey) throws -> String {
        let value = try requiredSchemaString(key)
        if value.isEmpty {
            throw SchemaValidationError(field: field(key), observed: "string \"\"", expected: "non-empty string")
        }
        return value
    }

    func optionalNonEmptyString(_ key: FenceParameterKey) throws -> String? {
        guard let value = try schemaString(key) else { return nil }
        if value.isEmpty {
            throw SchemaValidationError(field: field(key), observed: "string \"\"", expected: "non-empty string")
        }
        return value
    }

    func decodeElementTargetPayload() throws -> ElementTarget {
        try requireObjectStringMatchFields()
        let value = HeistValue.object(argumentValues)
        return try TheFence.HeistValuePayloadDecoder.decode(
            value,
            field: argumentFieldPrefix ?? "target",
            as: ElementTarget.self
        )
    }

    private func requireObjectStringMatchFields() throws {
        try TheFence.validateElementPredicatePayloadStringMatches(
            .object(argumentValues),
            field: argumentFieldPrefix ?? "target"
        )
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

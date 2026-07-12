import Foundation
import ThePlans

import TheScore

extension TheFence.CommandArgumentEnvelope {

    @ButtonHeistActor
    func decodedAccessibilityTarget() throws -> AccessibilityTarget? {
        guard let target = try schemaDictionary(.target) else { return nil }
        return try target.decodeAccessibilityTargetPayload()
    }

    @ButtonHeistActor
    func requiredAccessibilityTarget(command: TheFence.Command) throws -> AccessibilityTarget {
        guard let target = try decodedAccessibilityTarget() else {
            throw TheFence.MissingAccessibilityTarget(command: command)
        }
        return try target.resolvedElementTarget(command: command)
    }

    @ButtonHeistActor
    func scrollContainerSelection() throws -> ScrollContainerSelection {
        if let containerName = try optionalContainerName(.containerName) {
            if try decodedAccessibilityTarget() != nil {
                throw SchemaValidationError(
                    field: field(.containerName),
                    observed: observedDescription(for: .containerName) ?? "string",
                    expected: "not present when an element target is provided"
                )
            }
            return .container(containerName)
        }
        if let target = try decodedAccessibilityTarget() {
            return .element(try target.resolvedElementTarget(command: .scroll))
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

    func decodeAccessibilityTargetPayload() throws -> AccessibilityTarget {
        try requireObjectStringMatchFields()
        return try TheFence.HeistValuePayloadDecoder.decode(
            objectValue,
            field: argumentFieldPrefix ?? "target",
            as: AccessibilityTarget.self
        )
    }

    private func requireObjectStringMatchFields() throws {
        try TheFence.validateElementPredicatePayloadStringMatches(
            objectValue,
            field: argumentFieldPrefix ?? "target"
        )
    }

}

extension AccessibilityTarget {
    func resolvedElementTarget(command: TheFence.Command) throws -> AccessibilityTarget {
        let resolved = try resolve(in: .empty)
        guard resolved.selectsElement else {
            throw TheFence.ContainerTargetRequiresElement(command: command)
        }
        return resolved
    }

    var selectsElement: Bool {
        switch self {
        case .predicate:
            return true
        case .container:
            return false
        case .ref:
            preconditionFailure("resolved accessibility targets cannot contain refs")
        case .within(_, let target):
            return target.selectsElement
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

import Foundation
import ThePlans

import TheScore

extension TheFence.CommandArgumentEnvelope {

    @ButtonHeistActor
    func decodedAccessibilityTarget() throws -> AccessibilityTarget? {
        guard let value = value(for: .target) else { return nil }
        guard case .object(let object) = value else {
            throw SchemaValidationError(
                field: field(.target),
                observed: value.schemaObservedDescription,
                expected: "object"
            )
        }
        return try TheFence.CommandArgumentEnvelope(
            values: object,
            fieldPrefix: field(.target)
        ).decodeAccessibilityTargetPayload()
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
        if let containerName = try optionalContainerName() {
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

    func optionalContainerName() throws -> ContainerName? {
        guard let value = try value(FenceParameters.containerName) else { return nil }
        guard let containerName = ContainerName(parsing: value) else {
            throw SchemaValidationError(
                field: field(FenceParameters.containerName.key),
                observed: value.isEmpty ? "string \"\"" : "blank string",
                expected: "non-empty container name"
            )
        }
        return containerName
    }

    func decodeAccessibilityTargetPayload() throws -> AccessibilityTarget {
        try TheFence.HeistValuePayloadDecoder.decode(
            objectValue,
            field: argumentFieldPrefix ?? "target",
            as: AccessibilityTarget.self
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

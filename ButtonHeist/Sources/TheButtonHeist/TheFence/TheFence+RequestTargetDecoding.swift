import Foundation

import TheScore

extension TheFence.CommandArgumentReadable {

    @ButtonHeistActor
    func elementTarget() throws -> ElementTarget? {
        if let playbackSemanticTarget {
            if keys.contains("target") {
                throw SchemaValidationError(
                    field: field("target"),
                    observed: observedDescription(for: "target") ?? "object",
                    expected: "not present when semantic playback target is provided"
                )
            }
            return playbackSemanticTarget.playbackElementTarget
        }
        guard let targetValue = argumentValues["target"] else { return nil }
        guard case .object = targetValue else {
            throw SchemaValidationError(
                field: field("target"),
                observed: targetValue.schemaObservedDescription,
                expected: "object"
            )
        }
        return try decodeElementTargetCommandValue(targetValue)
    }

    @ButtonHeistActor
    func requiredElementTarget(command: TheFence.Command) throws -> ElementTarget {
        guard let target = try elementTarget() else {
            throw TheFence.MissingElementTarget(command: command.rawValue)
        }
        return target
    }

    func scrollContainerTarget() throws -> ScrollContainerTarget? {
        let container = try schemaDictionary("container")
        let stableId = try container?.schemaString("stableId") ?? schemaString("stableId")
        let captureLocalRef = try container?.schemaString("captureLocalRef") ?? schemaString("captureLocalRef")
        guard stableId != nil || captureLocalRef != nil else { return nil }
        return ScrollContainerTarget(stableId: stableId, captureLocalRef: captureLocalRef)
    }

    @ButtonHeistActor
    func scrollContainerSelection() throws -> ScrollContainerSelection {
        let elementTarget = try elementTarget()
        let containerTarget = try scrollContainerTarget()
        switch (containerTarget, elementTarget) {
        case (.some, .some):
            throw SchemaValidationError(
                field: "target",
                observed: observedDescription,
                expected: "at most one of container or element target"
            )
        case (.some(let containerTarget), nil):
            return .container(containerTarget)
        case (nil, .some(let elementTarget)):
            return .element(elementTarget)
        case (nil, nil):
            return .visibleContainer
        }
    }

    func customActionContainerTarget() throws -> (matcher: ContainerMatcher, ordinal: Int?)? {
        guard let container = try schemaDictionary("container") else { return nil }
        let matcher = ContainerMatcher(
            stableId: try container.schemaString("stableId"),
            type: try container.schemaEnum("type", as: ContainerTypeName.self),
            label: try container.schemaString("label"),
            value: try container.schemaString("value"),
            identifier: try container.schemaString("identifier"),
            isModalBoundary: try container.schemaBoolean("isModalBoundary")
        )
        let ordinal = try nonNegativeInteger("ordinal")
        guard matcher.hasPredicates else {
            throw SchemaValidationError(
                field: "container",
                observed: container.observedDescription,
                expected: "container target with stableId, type, label, value, identifier, or isModalBoundary"
            )
        }
        return (matcher, ordinal)
    }

    @ButtonHeistActor
    func customActionTarget(actionName: String) throws -> CustomActionTarget {
        let containerTarget = try customActionContainerTarget()
        if let containerTarget {
            guard !hasElementTargetFields else {
                throw SchemaValidationError(
                    field: "target",
                    observed: observedDescription,
                    expected: "exactly one element target or container selector"
                )
            }
            return CustomActionTarget(
                containerTarget: containerTarget.matcher,
                ordinal: containerTarget.ordinal,
                actionName: actionName
            )
        }

        guard let elementTarget = try elementTarget() else {
            throw TheFence.MissingElementTarget(command: TheFence.Command.activate.rawValue)
        }
        return CustomActionTarget(elementTarget: elementTarget, actionName: actionName)
    }

    var hasElementTargetFields: Bool {
        playbackSemanticTarget != nil || keys.contains("target")
    }

    func requiredString(_ key: String) throws -> String {
        try requiredSchemaString(key)
    }

    func nonEmptyString(_ key: String) throws -> String {
        let value = try requiredString(key)
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

    func integer(_ key: String) throws -> Int? {
        try schemaInteger(key)
    }

    func nonNegativeInteger(_ key: String) throws -> Int? {
        try schemaNonNegativeInteger(key)
    }

    func boolean(_ key: String) throws -> Bool? {
        try schemaBoolean(key)
    }

    func requiredEnumValue<E>(
        _ key: String,
        as type: E.Type
    ) throws -> E where E: CaseIterable & RawRepresentable, E.RawValue == String {
        try requiredSchemaEnum(key, as: type)
    }

    func countArgument() throws -> TheFence.CountArgument {
        TheFence.CountArgument(
            value: try integer("count"),
            observed: observedDescription(for: "count")
        )
    }

    private func decodeElementTargetCommandValue(_ targetValue: HeistValue) throws -> ElementTarget {
        do {
            return try ElementTarget.decodeCommandTarget(from: targetValue)
        } catch let error as DecodingError {
            let context = decodingContext(from: error)
            throw SchemaValidationError(
                field: elementTargetField(codingPath: context.codingPath),
                observed: elementTargetValue(targetValue, at: context.codingPath)?.schemaObservedDescription
                    ?? targetValue.schemaObservedDescription,
                expected: context.debugDescription
            )
        } catch {
            throw SchemaValidationError(
                field: field("target"),
                observed: targetValue.schemaObservedDescription,
                expected: "valid element target"
            )
        }
    }

    private func elementTargetField(codingPath: [CodingKey]) -> String {
        var path = "target"
        for key in codingPath {
            if let index = key.intValue {
                path += "[\(index)]"
            } else {
                path += ".\(key.stringValue)"
            }
        }
        return field(path)
    }

    private func elementTargetValue(_ value: HeistValue, at codingPath: [CodingKey]) -> HeistValue? {
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

    private func decodingContext(from error: DecodingError) -> DecodingError.Context {
        switch error {
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .keyNotFound(_, let context),
             .dataCorrupted(let context):
            return context
        @unknown default:
            return DecodingError.Context(codingPath: [], debugDescription: error.localizedDescription)
        }
    }
}

private extension SemanticActionTarget {
    var playbackElementTarget: ElementTarget {
        .matcher(matcher, ordinal: ordinal)
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

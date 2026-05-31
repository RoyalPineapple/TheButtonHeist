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
        return try target.decodeCommandPayload(ElementTarget.self)
    }

    @ButtonHeistActor
    func requiredElementTarget(command: TheFence.Command) throws -> ElementTarget {
        guard let target = try decodedElementTarget() else {
            throw TheFence.MissingElementTarget(command: command.rawValue)
        }
        return target
    }

    func scrollContainerTarget() throws -> ScrollContainerTarget? {
        let container = try schemaDictionary("container")
        try container?.rejectUnknownKeys(allowed: ["stableId"], expected: "valid scroll container field")
        let stableId = try container?.schemaString("stableId") ?? schemaString("stableId")
        guard stableId != nil else { return nil }
        return ScrollContainerTarget(stableId: stableId)
    }

    @ButtonHeistActor
    func scrollContainerSelection() throws -> ScrollContainerSelection {
        let elementTarget = try decodedElementTarget()
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

    func countArgument() throws -> TheFence.CountArgument {
        TheFence.CountArgument(
            value: try schemaInteger("count"),
            observed: observedDescription(for: "count")
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

import TheScore

extension TheFence.CommandArgumentReadable {

    @ButtonHeistActor
    func elementTarget() throws -> ElementTarget? {
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
        return try target.decodedElementTarget()
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

    func decodedElementTarget() throws -> ElementTarget {
        try rejectUnknownKeys(
            allowed: Set(ElementTarget.inlineFieldNames),
            expected: "valid element target field"
        )

        let heistId = try schemaString(ElementTarget.heistIdFieldName)
        let matcher = try elementMatcher()
        let matcherWasProvided = ElementTarget.matcherFieldNames.contains { keys.contains($0) }
        let ordinal = try nonNegativeInteger("ordinal")

        do {
            return try ElementTargetGrammar.validatedTarget(
                heistId: heistId,
                matcher: matcher,
                matcherWasProvided: matcherWasProvided,
                ordinal: ordinal
            )
        } catch let error as ElementTargetGrammarError {
            throw SchemaValidationError(
                field: argumentFieldPrefix ?? "target",
                observed: observedDescription,
                expected: error.diagnosticDescription
            )
        }
    }

    private func elementMatcher() throws -> ElementMatcher {
        ElementMatcher(
            label: try schemaString("label"),
            identifier: try schemaString("identifier"),
            value: try schemaString("value"),
            traits: try TheFence.parseTraitNames(try schemaStringArray("traits"), field: field("traits")),
            excludeTraits: try TheFence.parseTraitNames(
                try schemaStringArray("excludeTraits"),
                field: field("excludeTraits")
            )
        )
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
        elementTarget != nil || keys.contains("target")
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

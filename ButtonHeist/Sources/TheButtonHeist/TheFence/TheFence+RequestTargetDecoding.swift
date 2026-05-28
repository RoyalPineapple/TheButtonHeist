import TheScore

extension TheFence {

    struct ElementActionRequestInput {
        private let request: any CommandArgumentReadable

        init(_ request: some CommandArgumentReadable) {
            self.request = request
        }

        var observedDescription: String {
            request.observedDescription
        }

        @ButtonHeistActor
        func elementTarget(in fence: TheFence) throws -> ElementTarget? {
            guard let target = try request.schemaDictionary("target") else { return nil }
            try target.rejectUnknownKeys(
                allowed: ["heistId", "matcher", "ordinal"],
                expected: "valid target field"
            )
            let heistId = try target.schemaString("heistId")
            let matcherObject = try target.schemaDictionary("matcher")
            let ordinal = try target.schemaNonNegativeInteger("ordinal")
            let hasMixedHeistIdTarget = ordinal != nil || matcherObject != nil
            if heistId != nil, hasMixedHeistIdTarget {
                throw SchemaValidationError(
                    field: "target",
                    observed: target.observedDescription,
                    expected: "either heistId or matcher with optional ordinal"
                )
            }
            if let heistId {
                return .heistId(heistId)
            }
            guard let matcherObject else {
                throw SchemaValidationError(
                    field: "target",
                    observed: target.observedDescription,
                    expected: "heistId or matcher"
                )
            }
            try matcherObject.rejectUnknownKeys(
                allowed: ["label", "identifier", "value", "traits", "excludeTraits"],
                expected: "valid target.matcher field"
            )
            let matcher = try matcher(from: matcherObject)
            guard matcher.nonEmpty != nil else {
                throw SchemaValidationError(
                    field: target.field("matcher"),
                    observed: matcherObject.observedDescription,
                    expected: "matcher with label, identifier, value, traits, or excludeTraits"
                )
            }
            return ElementTarget(
                matcher: matcher,
                ordinal: ordinal
            )
        }

        @ButtonHeistActor
        func requiredElementTarget(command: TheFence.Command, in fence: TheFence) throws -> ElementTarget {
            guard let target = try elementTarget(in: fence) else {
                throw MissingElementTarget(command: command.rawValue)
            }
            return target
        }

        func scrollContainerTarget() throws -> ScrollContainerTarget? {
            let container = try request.schemaDictionary("container")
            let stableId = try container?.schemaString("stableId") ?? string("stableId")
            let captureLocalRef = try container?.schemaString("captureLocalRef") ?? string("captureLocalRef")
            guard stableId != nil || captureLocalRef != nil else { return nil }
            return ScrollContainerTarget(stableId: stableId, captureLocalRef: captureLocalRef)
        }

        @ButtonHeistActor
        func scrollContainerSelection(in fence: TheFence) throws -> ScrollContainerSelection {
            let elementTarget = try elementTarget(in: fence)
            let containerTarget = try scrollContainerTarget()
            switch (containerTarget, elementTarget) {
            case (.some, .some):
                throw SchemaValidationError(
                    field: "target",
                    observed: request.observedDescription,
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
            guard let container = try request.schemaDictionary("container") else { return nil }
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
        func customActionTarget(actionName: String, in fence: TheFence) throws -> CustomActionTarget {
            let containerTarget = try customActionContainerTarget()
            if let containerTarget {
                guard !hasElementTargetFields else {
                    throw SchemaValidationError(
                        field: "target",
                        observed: request.observedDescription,
                        expected: "exactly one element target or container selector"
                    )
                }
                return CustomActionTarget(
                    containerTarget: containerTarget.matcher,
                    ordinal: containerTarget.ordinal,
                    actionName: actionName
                )
            }

            guard let elementTarget = try elementTarget(in: fence) else {
                throw MissingElementTarget(command: TheFence.Command.activate.rawValue)
            }
            return CustomActionTarget(elementTarget: elementTarget, actionName: actionName)
        }

        var hasElementTargetFields: Bool {
            request.keys.contains("target")
        }

        @ButtonHeistActor
        func matcher() throws -> ElementMatcher {
            try matcher(from: request)
        }

        @ButtonHeistActor
        func matcher(from source: some TheFence.CommandArgumentReadable) throws -> ElementMatcher {
            ElementMatcher(
                label: try source.schemaString("label"),
                identifier: try source.schemaString("identifier"),
                value: try source.schemaString("value"),
                traits: try TheFence.parseTraitNames(
                    try source.schemaStringArray("traits"),
                    field: source.field("traits")
                ),
                excludeTraits: try TheFence.parseTraitNames(
                    try source.schemaStringArray("excludeTraits"),
                    field: source.field("excludeTraits")
                )
            )
        }

        func string(_ key: String) throws -> String? {
            try request.schemaString(key)
        }

        func requiredString(_ key: String) throws -> String {
            try request.requiredSchemaString(key)
        }

        func nonEmptyString(_ key: String) throws -> String {
            let value = try requiredString(key)
            if value.isEmpty {
                throw SchemaValidationError(field: request.field(key), observed: "string \"\"", expected: "non-empty string")
            }
            return value
        }

        func optionalNonEmptyString(_ key: String) throws -> String? {
            guard let value = try string(key) else { return nil }
            if value.isEmpty {
                throw SchemaValidationError(field: request.field(key), observed: "string \"\"", expected: "non-empty string")
            }
            return value
        }

        func integer(_ key: String) throws -> Int? {
            try request.schemaInteger(key)
        }

        func nonNegativeInteger(_ key: String) throws -> Int? {
            try request.schemaNonNegativeInteger(key)
        }

        func boolean(_ key: String) throws -> Bool? {
            try request.schemaBoolean(key)
        }

        func number(_ key: String) throws -> Double? {
            try request.schemaNumber(key)
        }

        func enumValue<E>(
            _ key: String,
            as type: E.Type
        ) throws -> E? where E: CaseIterable & RawRepresentable, E.RawValue == String {
            try request.schemaEnum(key, as: type)
        }

        func requiredEnumValue<E>(
            _ key: String,
            as type: E.Type
        ) throws -> E where E: CaseIterable & RawRepresentable, E.RawValue == String {
            try request.requiredSchemaEnum(key, as: type)
        }

        func countArgument() throws -> TheFence.CountArgument {
            TheFence.CountArgument(
                value: try integer("count"),
                observed: request.observedDescription(for: "count")
            )
        }
    }

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

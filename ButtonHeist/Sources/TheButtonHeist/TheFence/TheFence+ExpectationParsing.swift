import TheScore

extension TheFence {

    struct ExpectationPayload {
        let expectation: ActionExpectation?
        let timeout: Double?

        init(expectation: ActionExpectation?, timeout: Double?) {
            self.expectation = expectation
            self.timeout = timeout
        }

        init(arguments: some CommandArgumentReadable) throws {
            self.init(
                expectation: try Self.parseExpectation(arguments.argumentValues["expect"]),
                timeout: try arguments.schemaNumber("timeout")
            )
        }

        var postActionValidationTimeout: Double? {
            expectation == nil ? nil : timeout
        }

        static func parseExpectation(_ value: CommandArgumentValue?) throws -> ActionExpectation? {
            guard let value else { return nil }
            return try FenceExpectationParser.decode(value)
        }
    }

    // MARK: - Expectation Parsing

    /// Parse the `"expect"` field off a CLI/MCP request dictionary into a typed
    /// `ActionExpectation`. Returns `nil` when no expectation is set. The
    /// accepted shape is the discriminator object used by `ActionExpectation`'s
    /// wire encoding: `{"type": "...", …}`. Compound expectations use object
    /// sub-expectations with `{"type": "compound", "expectations": [...]}`.
    func parseExpectationPayload(_ arguments: some CommandArgumentReadable) throws -> ExpectationPayload {
        try ExpectationPayload(arguments: arguments)
    }
}

private enum FenceExpectationParser {
    static func decode(_ value: TheFence.CommandArgumentValue) throws -> ActionExpectation {
        if case .object(let object) = value {
            return try decode(TheFence.CommandArgumentObject(values: object, fieldPrefix: nil))
        }
        throw FenceError.invalidRequest(
            "Invalid expectation type: expected object with a \"type\" discriminator"
        )
    }

    static func decode(_ object: TheFence.CommandArgumentObject) throws -> ActionExpectation {
        let type = try expectationType(in: object)
        switch type {
        case "delivery":
            return .delivery
        case "screen_changed":
            return .screenChanged
        case "elements_changed":
            return .elementsChanged
        case "element_updated":
            return try .elementUpdated(
                heistId: object.schemaString("heistId"),
                property: elementProperty(in: object),
                oldValue: object.schemaString("oldValue"),
                newValue: object.schemaString("newValue")
            )
        case "element_appeared":
            return try .elementAppeared(requiredMatcher(in: object, type: type))
        case "element_disappeared":
            return try .elementDisappeared(requiredMatcher(in: object, type: type))
        case "compound":
            return try .compound(compoundExpectations(in: object))
        default:
            throw FenceError.invalidRequest("Unknown expectation type: \"\(type)\". Valid: \(validTypes)")
        }
    }

    private static var validTypes: String {
        ActionExpectation.wireTypeValues.joined(separator: ", ")
    }

    private static func expectationType(in object: TheFence.CommandArgumentObject) throws -> String {
        guard let value = object.argumentValues["type"] else {
            throw FenceError.invalidRequest(missingTypeMessage(object))
        }
        guard case .string(let type) = value else {
            throw FenceError.invalidRequest(
                "Expectation object requires a string \"type\" discriminator " +
                    "(e.g. {\"type\": \"element_updated\", …}). " +
                    "Got \(object.field("type")): \(value.rawValue)"
            )
        }
        guard ActionExpectation.wireTypeValues.contains(type) else {
            throw FenceError.invalidRequest("Unknown expectation type: \"\(type)\". Valid: \(validTypes)")
        }
        return type
    }

    private static func missingTypeMessage(_ object: TheFence.CommandArgumentObject) -> String {
        "Expectation object requires a \"type\" discriminator " +
            "(e.g. {\"type\": \"element_updated\", …}). " +
            "Got keys: \(object.keys.sorted())"
    }

    private static func elementProperty(in object: TheFence.CommandArgumentObject) throws -> ElementProperty? {
        guard let propertyString = try object.schemaString("property") else { return nil }
        guard let property = ElementProperty(rawValue: propertyString) else {
            throw FenceError.invalidRequest(
                "Unknown element property: \"\(propertyString)\". Valid: \(validProperties)"
            )
        }
        return property
    }

    private static var validProperties: String {
        ElementProperty.allCases.map(\.rawValue).joined(separator: ", ")
    }

    private static func requiredMatcher(
        in object: TheFence.CommandArgumentObject,
        type: String
    ) throws -> ElementMatcher {
        guard let matcher = try object.schemaDictionary("matcher") else {
            throw FenceError.invalidRequest("\(type) requires a \"matcher\" object")
        }
        return try elementMatcher(from: matcher)
    }

    private static func elementMatcher(from object: TheFence.CommandArgumentObject) throws -> ElementMatcher {
        ElementMatcher(
            heistId: try object.schemaString("heistId"),
            label: try object.schemaString("label"),
            identifier: try object.schemaString("identifier"),
            value: try object.schemaString("value"),
            traits: try TheFence.parseTraitNames(
                try object.schemaStringArray("traits"),
                field: object.field("traits")
            ),
            excludeTraits: try TheFence.parseTraitNames(
                try object.schemaStringArray("excludeTraits"),
                field: object.field("excludeTraits")
            )
        )
    }

    private static func compoundExpectations(in object: TheFence.CommandArgumentObject) throws -> [ActionExpectation] {
        guard let value = object.argumentValues["expectations"] else {
            throw FenceError.invalidRequest("compound requires an \"expectations\" array")
        }
        guard case .array(let values) = value else {
            throw SchemaValidationError(
                field: object.field("expectations"),
                observed: value.rawValue,
                expected: "array of objects"
            )
        }
        return try values.enumerated().map { index, value in
            guard case .object(let expectationObject) = value else {
                throw FenceError.invalidRequest("compound expectations must be objects with a \"type\" discriminator")
            }
            return try decode(
                TheFence.CommandArgumentObject(
                    values: expectationObject,
                    fieldPrefix: "\(object.field("expectations"))[\(index)]"
                )
            )
        }
    }
}

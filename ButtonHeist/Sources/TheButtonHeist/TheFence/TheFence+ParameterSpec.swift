import TheScore

public struct FenceParameterSpec: Sendable, Equatable {

    public enum ParamType: String, Sendable, Equatable {
        case string
        case integer
        case number
        case boolean
        case stringArray
        case object
        case array
    }

    public let key: String
    public let type: ParamType
    public let required: Bool
    public let enumValues: [String]?
    public let defaultValue: HeistValue?
    public let jsonSchemaProperty: HeistValue
    public let objectProperties: [FenceParameterSpec]
    public let arrayItemProperties: [FenceParameterSpec]

}

extension TheFence {

    enum DecodeLimits {
        static let maxRunHeistSteps = 100
        static let maxRunHeistRequestBytes = 1_000_000
        static let maxRunHeistNestingDepth = 32
        static let maxHeistResultRows = maxRunHeistSteps
        static let maxInlineScreenshotBase64Bytes = 1_000_000
    }
}

public struct FenceParameterKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension FenceParameterKey {
    static let absent = Self("absent"), action = Self("action"), angle = Self("angle"), app = Self("app")
    static let argument = Self("argument")
    static let command = Self("command")
    static let container = Self("container")
    static let continuation = Self("continuation")
    static let detail = Self("detail"), device = Self("device"), direction = Self("direction"), duration = Self("duration")
    static let edge = Self("edge"), element = Self("element"), elements = Self("elements"), end = Self("end")
    static let endOffset = Self("endOffset"), excludeTraits = Self("excludeTraits")
    static let elementDirection = Self("elementDirection"), elementToPoint = Self("elementToPoint")
    static let elementUnitPoints = Self("elementUnitPoints")
    static let expect = Self("expect"), from = Self("from"), heistId = Self("heistId")
    static let heist = Self("heist"), identifier = Self("identifier"), includeInterface = Self("includeInterface")
    static let inlineData = Self("inlineData"), path = Self("path"), isModalBoundary = Self("isModalBoundary")
    static let label = Self("label"), matcher = Self("matcher"), mode = Self("mode")
    static let newValue = Self("newValue"), oldValue = Self("oldValue"), ordinal = Self("ordinal"), output = Self("output")
    static let point = Self("point"), pointDirection = Self("pointDirection"), pointToPoint = Self("pointToPoint")
    static let plan = Self("plan"), policy = Self("policy"), predicate = Self("predicate"), property = Self("property")
    static let radius = Self("radius")
    static let rotor = Self("rotor"), rotorIndex = Self("rotorIndex")
    static let scale = Self("scale"), spread = Self("spread"), start = Self("start")
    static let startOffset = Self("startOffset")
    static let step = Self("step")
    static let containerName = Self("containerName")
    static let states = Self("states"), body = Self("body")
    static let name = Self("name"), parameter = Self("parameter"), definitions = Self("definitions")
    static let subtree = Self("subtree"), target = Self("target"), text = Self("text"), textRange = Self("textRange")
    static let timeout = Self("timeout"), version = Self("version")
    static let to = Self("to"), token = Self("token"), traits = Self("traits"), type = Self("type"), value = Self("value")
    static let valueRef = Self("value_ref")
    static let values = Self("values")
    static let `where` = Self("where")
    static let x = Self("x"), y = Self("y")
}

func fenceEnumValues<E>(_ type: E.Type) -> [String] where E: CaseIterable & RawRepresentable, E.RawValue == String {
    type.allCases.map(\.rawValue)
}

func param(
    _ key: FenceParameterKey,
    _ type: FenceParameterSpec.ParamType,
    required: Bool = false,
    enumValues: [String]? = nil,
    defaultValue: HeistValue? = nil,
    minimum: Double? = nil,
    maximum: Double? = nil,
    minLength: Int? = nil,
    minItems: Int? = nil,
    maxItems: Int? = nil,
    objectProperties: [FenceParameterSpec] = [],
    objectAdditionalProperties: Bool = false,
    arrayItemType: FenceParameterSpec.ParamType? = nil,
    arrayItemProperties: [FenceParameterSpec] = [],
    arrayItemAdditionalProperties: Bool = false
) -> FenceParameterSpec {
    var schema: [String: HeistValue] = ["type": .string(type.jsonSchemaType)]
    if let enumValues { schema["enum"] = .array(enumValues.map { .string($0) }) }
    if let defaultValue { schema["default"] = defaultValue }
    if let minimum { schema["minimum"] = jsonSchemaNumber(minimum) }
    if let maximum { schema["maximum"] = jsonSchemaNumber(maximum) }
    if let minLength { schema["minLength"] = .int(minLength) }
    if let minItems { schema["minItems"] = .int(minItems) }
    if let maxItems { schema["maxItems"] = .int(maxItems) }

    switch type {
    case .stringArray:
        schema["items"] = .object(["type": .string(FenceParameterSpec.ParamType.string.jsonSchemaType)])
    case .object where !objectProperties.isEmpty:
        schema["properties"] = .object(FenceParameterSpec.jsonSchemaProperties(from: objectProperties))
        addRequiredKeys(from: objectProperties, to: &schema)
        schema["additionalProperties"] = .bool(objectAdditionalProperties)
    case .array:
        if let arrayItemType {
            var items: [String: HeistValue] = ["type": .string(arrayItemType.jsonSchemaType)]
            if arrayItemType == .object {
                items["properties"] = .object(FenceParameterSpec.jsonSchemaProperties(from: arrayItemProperties))
                addRequiredKeys(from: arrayItemProperties, to: &items)
                items["additionalProperties"] = .bool(arrayItemAdditionalProperties)
            }
            schema["items"] = .object(items)
        }
    default:
        break
    }

    return FenceParameterSpec(
        key: key.rawValue,
        type: type,
        required: required,
        enumValues: enumValues,
        defaultValue: defaultValue,
        jsonSchemaProperty: .object(schema),
        objectProperties: objectProperties,
        arrayItemProperties: arrayItemProperties
    )
}

private func addRequiredKeys(
    from specs: [FenceParameterSpec],
    to schema: inout [String: HeistValue]
) {
    let required = specs.filter(\.required).map(\.key)
    if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
}

private func jsonSchemaNumber(_ value: Double) -> HeistValue {
    value.rounded(.towardZero) == value ? .int(Int(value)) : .double(value)
}

public enum MCPExposure: Sendable, Equatable {
    case directTool
    case notExposed
}

public struct MCPToolAnnotationSpec: Sendable, Equatable {
    public let readOnlyHint: Bool?
    public let idempotentHint: Bool?

    public init(
        readOnlyHint: Bool? = nil,
        idempotentHint: Bool? = nil
    ) {
        self.readOnlyHint = readOnlyHint
        self.idempotentHint = idempotentHint
    }
}

public extension FenceParameterSpec.ParamType {
    var jsonSchemaType: String {
        self == .stringArray ? "array" : rawValue
    }
}

public extension FenceCommandDescriptor {
    var inputJSONSchema: HeistValue {
        FenceParameterSpec.jsonInputSchema(
            properties: FenceParameterSpec.jsonSchemaProperties(from: parameters),
            required: parameters.filter(\.required).map(\.key)
        )
    }
}

public extension FenceParameterSpec {
    func parameters(named key: FenceParameterKey) -> [FenceParameterSpec] {
        let childMatches = objectProperties.flatMap { $0.parameters(named: key) }
            + arrayItemProperties.flatMap { $0.parameters(named: key) }
        guard self.key == key.rawValue else { return childMatches }
        return [self] + childMatches
    }

    var objectPropertyKeys: Set<String> {
        Set(objectProperties.map(\.key))
    }

    static func jsonSchemaProperties(from specs: [FenceParameterSpec]) -> [String: HeistValue] {
        var properties: [String: HeistValue] = [:]
        for spec in specs where properties[spec.key] == nil {
            properties[spec.key] = spec.jsonSchemaProperty
        }
        return properties
    }

    static func jsonInputSchema(
        properties: [String: HeistValue],
        required: [String] = []
    ) -> HeistValue {
        var schema: [String: HeistValue] = [
            "type": .string(FenceParameterSpec.ParamType.object.jsonSchemaType),
            "properties": .object(properties),
            "additionalProperties": .bool(false),
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return .object(schema)
    }
}

public enum CLIExposure: Sendable, Equatable {
    case directCommand
    case notExposed
}

enum FenceParameterBlocks: Sendable {
    private static let matcherFields = ElementTarget.predicateSchemaFields.map(elementTargetFieldSpec)
    private static let inlineElementTargetFields = ElementTarget.inlineSchemaFields.map(elementTargetFieldSpec)

    static let elementTarget: [FenceParameterSpec] = [
        param(.target, .object, objectProperties: inlineElementTargetFields),
    ]
    static let gestureElement = param(.element, .object, objectProperties: inlineElementTargetFields)
    static let gesturePoint = param(.point, .object, objectProperties: screenPoint)

    static let gesturePointSelection: [FenceParameterSpec] = [
        gestureElement,
        gesturePoint,
    ]

    static let swipeElementDirection = param(
        .elementDirection,
        .object,
        objectProperties: [
            gestureElement,
            param(.direction, .string, required: true, enumValues: fenceEnumValues(SwipeDirection.self)),
        ]
    )

    static let swipeElementUnitPoints = param(
        .elementUnitPoints,
        .object,
        objectProperties: [
            gestureElement,
            param(.start, .object, required: true, objectProperties: unitPoint),
            param(.end, .object, required: true, objectProperties: unitPoint),
        ]
    )

    static let swipePointToPoint = param(
        .pointToPoint,
        .object,
        objectProperties: [
            param(.start, .object, required: true, objectProperties: screenPoint),
            param(.end, .object, required: true, objectProperties: screenPoint),
        ]
    )

    static let swipePointDirection = param(
        .pointDirection,
        .object,
        objectProperties: [
            param(.start, .object, required: true, objectProperties: screenPoint),
            param(.direction, .string, required: true, enumValues: fenceEnumValues(SwipeDirection.self)),
        ]
    )

    static let swipeIntents = [
        swipeElementDirection,
        swipeElementUnitPoints,
        swipePointToPoint,
        swipePointDirection,
    ]

    static var swipeIntentKeys: [String] {
        swipeIntents.map(\.key)
    }

    static func swipeIntentSpec(_ key: String) -> FenceParameterSpec {
        guard let spec = swipeIntents.first(where: { $0.key == key }) else {
            preconditionFailure("Unknown swipe intent \(key)")
        }
        return spec
    }

    static let dragElementToPoint = param(
        .elementToPoint,
        .object,
        objectProperties: [
            gestureElement,
            param(.end, .object, required: true, objectProperties: screenPoint),
        ]
    )

    static let dragPointToPoint = param(
        .pointToPoint,
        .object,
        objectProperties: [
            param(.start, .object, required: true, objectProperties: screenPoint),
            param(.end, .object, required: true, objectProperties: screenPoint),
        ]
    )

    static let dragIntents = [
        dragElementToPoint,
        dragPointToPoint,
    ]

    static var dragIntentKeys: [String] {
        dragIntents.map(\.key)
    }

    static func dragIntentSpec(_ key: String) -> FenceParameterSpec {
        guard let spec = dragIntents.first(where: { $0.key == key }) else {
            preconditionFailure("Unknown drag intent \(key)")
        }
        return spec
    }

    static let elementFilter = matcherFields

    private static let subtreeElementProperties = matcherFields

    private static let subtreeContainerProperties: [FenceParameterSpec] = [
        param(.containerName, .string),
        param(.type, .string, enumValues: fenceEnumValues(ContainerTypeName.self)),
        param(.label, .string), param(.value, .string), param(.identifier, .string),
        param(.isModalBoundary, .boolean),
    ]

    // `subtree.container` is a plain object matcher in the public schema — MCP
    // (OpenAI) tool input schemas reject JSON Schema combinators, so this must
    // never emit `oneOf`/`anyOf`/`allOf`. Pass the container name as
    // `{ "container": { "containerName": "main_scroll" } }`.
    private static let subtreeContainer = param(
        .container,
        .object,
        objectProperties: subtreeContainerProperties
    )

    static let interfaceSubtree: FenceParameterSpec = param(
        .subtree, .object,
        objectProperties: [
            param(.element, .object, objectProperties: subtreeElementProperties),
            subtreeContainer,
            param(.ordinal, .integer, minimum: 0),
        ]
    )

    private static let predicateType = param(
        .type, .string, required: true,
        enumValues: AccessibilityPredicate.wireTypeValues
    )

    /// Documented fields of an `AccessibilityPredicate.State` object (`present`,
    /// `absent`, `all`). A `State` is recursive — `all` nests further states —
    /// so item objects allow additional keys and the decoder enforces the
    /// per-type required-field rules.
    private static let stateProperties: [FenceParameterSpec] = [
        param(.type, .string, enumValues: ["present", "absent", "all"]),
        param(.element, .object, objectProperties: matcherFields),
    ]

    /// Object properties for an `AccessibilityPredicate` (the `expect` slot and
    /// the `wait` `predicate` field). Element fields nest under `element`;
    /// `property`/`from`/`to` filter `element_updated`; `states` carries the
    /// child conditions of `all`; `where` carries the post-transition state of
    /// `screen_changed`.
    private static let accessibilityPredicateProperties: [FenceParameterSpec] = [
        predicateType,
        param(.element, .object, objectProperties: matcherFields),
        param(.property, .string, enumValues: fenceEnumValues(ElementProperty.self)),
        param(.from, .string),
        param(.to, .string),
        param(
            .states, .array,
            arrayItemType: .object,
            arrayItemProperties: stateProperties,
            arrayItemAdditionalProperties: true
        ),
        param(.where, .object, objectProperties: stateProperties, objectAdditionalProperties: true),
    ]

    static let expect: FenceParameterSpec = param(
        .expect, .object,
        objectProperties: accessibilityPredicateProperties
    )

    static let predicate: FenceParameterSpec = param(
        .predicate, .object, required: true,
        objectProperties: accessibilityPredicateProperties
    )

    static let expectationTimeout = param(.timeout, .number, maximum: 30)
    static let expectation: [FenceParameterSpec] = [expect, expectationTimeout]

    /// Parameters for the unified `wait` command: a predicate plus a timeout.
    static let wait: [FenceParameterSpec] = [predicate, expectationTimeout]

    static let unitPoint: [FenceParameterSpec] = [
        param(.x, .number, required: true), param(.y, .number, required: true),
    ]
    static let screenPoint: [FenceParameterSpec] = unitPoint
    static let gestureDuration = param(
        .duration, .number,
        maximum: GestureDuration.maximumSeconds
    )
    private static func elementTargetFieldSpec(_ field: ElementTarget.SchemaField) -> FenceParameterSpec {
        guard let key = FenceParameterKey(rawValue: field.name) else {
            preconditionFailure("ElementTarget field '\(field.name)' is not a Fence parameter key")
        }
        switch field.kind {
        case .string:
            return param(key, .string)
        case .stringArray:
            return param(key, .stringArray)
        case .nonNegativeInteger:
            return param(key, .integer, minimum: 0)
        }
    }
}

import TheScore
import ThePlans

@_spi(ButtonHeistTooling) public struct FenceParameterSpec: Sendable, Equatable {

    public enum ParamType: String, Sendable, Equatable {
        case string
        case integer
        case number
        case boolean
        case stringArray
        case stringMatch
        case object
        case array
    }

    public let key: String
    public let type: ParamType
    public let required: Bool
    public let enumValues: [String]?
    public let defaultValue: HeistValue?
    let minimum: Double?
    let maximum: Double?
    let exclusiveMinimum: Double?
    let minLength: Int?
    let minItems: Int?
    let maxItems: Int?
    let jsonSchema: FenceParameterJSONSchema
    public let objectProperties: [FenceParameterSpec]
    let objectAdditionalProperties: Bool
    let arrayItemType: ParamType?
    public let arrayItemProperties: [FenceParameterSpec]
    let arrayItemAdditionalProperties: Bool

}

indirect enum FenceParameterJSONSchema: Sendable, Equatable {
    case scalar(FenceParameterJSONScalarSchema)
    case object(FenceParameterJSONObjectSchema)
    case array(FenceParameterJSONArraySchema)

    var heistValue: HeistValue {
        .object(heistValueProperties)
    }

    private var heistValueProperties: [String: HeistValue] {
        switch self {
        case .scalar(let schema):
            return schema.heistValueProperties
        case .object(let schema):
            return schema.heistValueProperties
        case .array(let schema):
            return schema.heistValueProperties
        }
    }

    static func scalar(
        _ type: FenceParameterSpec.ParamType,
        constraints: FenceParameterJSONSchemaConstraints = .empty
    ) -> Self {
        .scalar(FenceParameterJSONScalarSchema(type: type, constraints: constraints))
    }

    static func object(
        properties: [FenceParameterJSONSchemaProperty]? = nil,
        additionalProperties: Bool? = nil,
        constraints: FenceParameterJSONSchemaConstraints = .empty
    ) -> Self {
        .object(FenceParameterJSONObjectSchema(
            properties: properties,
            additionalProperties: additionalProperties,
            constraints: constraints
        ))
    }

    static func array(
        items: FenceParameterJSONSchema? = nil,
        constraints: FenceParameterJSONSchemaConstraints = .empty
    ) -> Self {
        .array(FenceParameterJSONArraySchema(items: items, constraints: constraints))
    }

    static func stringMatch(
        modeValues: [String],
        description: String
    ) -> Self {
        .object(
            properties: [
                FenceParameterJSONSchemaProperty(
                    key: .mode,
                    schema: .scalar(.string, constraints: FenceParameterJSONSchemaConstraints(enumValues: modeValues)),
                    required: true
                ),
                FenceParameterJSONSchemaProperty(
                    key: .value,
                    schema: .scalar(.string),
                    required: true
                ),
            ],
            additionalProperties: false,
            constraints: FenceParameterJSONSchemaConstraints(description: description)
        )
    }
}

struct FenceParameterJSONScalarSchema: Sendable, Equatable {
    let type: FenceParameterSpec.ParamType
    let constraints: FenceParameterJSONSchemaConstraints

    var heistValueProperties: [String: HeistValue] {
        var properties = ["type": HeistValue.string(type.jsonSchemaType)]
        constraints.add(to: &properties)
        return properties
    }
}

struct FenceParameterJSONObjectSchema: Sendable, Equatable {
    let properties: [FenceParameterJSONSchemaProperty]?
    let additionalProperties: Bool?
    let constraints: FenceParameterJSONSchemaConstraints

    var heistValueProperties: [String: HeistValue] {
        var fields = ["type": HeistValue.string(FenceParameterSpec.ParamType.object.jsonSchemaType)]
        constraints.add(to: &fields)
        if let properties {
            fields["properties"] = .object(Self.heistValueProperties(from: properties))
            let required = properties.filter(\.required).map(\.key)
            if !required.isEmpty {
                fields["required"] = .array(required.map { .string($0) })
            }
        }
        if let additionalProperties {
            fields["additionalProperties"] = .bool(additionalProperties)
        }
        return fields
    }

    private static func heistValueProperties(
        from properties: [FenceParameterJSONSchemaProperty]
    ) -> [String: HeistValue] {
        var projectedProperties: [String: HeistValue] = [:]
        for property in properties where projectedProperties[property.key] == nil {
            projectedProperties[property.key] = property.schema.heistValue
        }
        return projectedProperties
    }
}

struct FenceParameterJSONArraySchema: Sendable, Equatable {
    let items: FenceParameterJSONSchema?
    let constraints: FenceParameterJSONSchemaConstraints

    var heistValueProperties: [String: HeistValue] {
        var fields = ["type": HeistValue.string(FenceParameterSpec.ParamType.array.jsonSchemaType)]
        constraints.add(to: &fields)
        if let items {
            fields["items"] = items.heistValue
        }
        return fields
    }
}

struct FenceParameterJSONSchemaProperty: Sendable, Equatable {
    let key: String
    let schema: FenceParameterJSONSchema
    let required: Bool

    init(
        key: FenceParameterKey,
        schema: FenceParameterJSONSchema,
        required: Bool = false
    ) {
        self.key = key.rawValue
        self.schema = schema
        self.required = required
    }

    init(_ spec: FenceParameterSpec) {
        key = spec.key
        schema = spec.jsonSchema
        required = spec.required
    }
}

struct FenceParameterJSONSchemaConstraints: Sendable, Equatable {
    static let empty = Self()

    let enumValues: [String]?
    let defaultValue: HeistValue?
    let minimum: Double?
    let maximum: Double?
    let exclusiveMinimum: Double?
    let minLength: Int?
    let minItems: Int?
    let maxItems: Int?
    let description: String?

    init(
        enumValues: [String]? = nil,
        defaultValue: HeistValue? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        exclusiveMinimum: Double? = nil,
        minLength: Int? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        description: String? = nil
    ) {
        self.enumValues = enumValues
        self.defaultValue = defaultValue
        self.minimum = minimum
        self.maximum = maximum
        self.exclusiveMinimum = exclusiveMinimum
        self.minLength = minLength
        self.minItems = minItems
        self.maxItems = maxItems
        self.description = description
    }

    func add(to properties: inout [String: HeistValue]) {
        if let enumValues { properties["enum"] = .array(enumValues.map { .string($0) }) }
        if let defaultValue { properties["default"] = defaultValue }
        if let minimum { properties["minimum"] = jsonSchemaNumber(minimum) }
        if let maximum { properties["maximum"] = jsonSchemaNumber(maximum) }
        if let exclusiveMinimum { properties["exclusiveMinimum"] = jsonSchemaNumber(exclusiveMinimum) }
        if let minLength { properties["minLength"] = .int(minLength) }
        if let minItems { properties["minItems"] = .int(minItems) }
        if let maxItems { properties["maxItems"] = .int(maxItems) }
        if let description { properties["description"] = .string(description) }
    }
}

extension TheFence {

    enum DecodeLimits {
        static let maxRunHeistSteps = 100
        static let maxRunHeistRequestBytes = PublicJSONInputLimits.maxRequestBytes
        static let maxRunHeistNestingDepth = PublicJSONInputLimits.maxNestingDepth
        static let maxRunHeistObjectKeys = PublicJSONInputLimits.maxTotalObjectKeys
        static let maxHeistResultRows = maxRunHeistSteps
        static let maxInlineScreenshotBase64Bytes = 1_000_000
    }
}

@_spi(ButtonHeistTooling) public struct FenceParameterKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

@_spi(ButtonHeistTooling) public extension FenceParameterKey {
    static let absent = Self("absent"), action = Self("action"), angle = Self("angle"), app = Self("app")
    static let argument = Self("argument")
    static let after = Self("after")
    static let before = Self("before")
    static let checks = Self("checks")
    static let command = Self("command")
    static let container = Self("container")
    static let continuation = Self("continuation")
    static let detail = Self("detail"), device = Self("device"), direction = Self("direction"), duration = Self("duration")
    static let edge = Self("edge"), element = Self("element"), elements = Self("elements"), end = Self("end")
    static let endOffset = Self("endOffset"), excludeTraits = Self("excludeTraits")
    static let elementDirection = Self("elementDirection"), elementToPoint = Self("elementToPoint")
    static let elementUnitPoints = Self("elementUnitPoints")
    static let expect = Self("expect"), from = Self("from"), heistId = Self("heistId")
    static let heist = Self("heist"), identifier = Self("identifier")
    static let inlineData = Self("inlineData"), path = Self("path"), isModalBoundary = Self("isModalBoundary")
    static let kind = Self("kind"), label = Self("label"), match = Self("match"), matcher = Self("matcher")
    static let maxScrollsPerContainer = Self("maxScrollsPerContainer")
    static let maxScrollsPerDiscovery = Self("maxScrollsPerDiscovery")
    static let mode = Self("mode")
    static let newValue = Self("newValue"), oldValue = Self("oldValue"), ordinal = Self("ordinal"), output = Self("output")
    static let point = Self("point"), pointDirection = Self("pointDirection"), pointToPoint = Self("pointToPoint")
    static let plan = Self("plan"), policy = Self("policy"), predicate = Self("predicate"), property = Self("property")
    static let radius = Self("radius")
    static let replacingExisting = Self("replacingExisting")
    static let requestId = Self("requestId")
    static let rotor = Self("rotor"), rotorIndex = Self("rotorIndex")
    static let scale = Self("scale"), spread = Self("spread"), start = Self("start")
    static let startOffset = Self("startOffset")
    static let step = Self("step")
    static let containerName = Self("containerName")
    static let unitPoint = Self("unitPoint")
    static let states = Self("states"), scopes = Self("scopes"), assertions = Self("assertions"), body = Self("body")
    static let name = Self("name"), parameter = Self("parameter"), definitions = Self("definitions")
    static let subtree = Self("subtree"), target = Self("target"), text = Self("text"), textRange = Self("textRange")
    static let timeout = Self("timeout"), version = Self("version")
    static let to = Self("to"), token = Self("token"), traits = Self("traits"), type = Self("type"), value = Self("value")
    static let valueRef = Self("value_ref")
    static let targetRef = Self("target_ref")
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
    exclusiveMinimum: Double? = nil,
    minLength: Int? = nil,
    minItems: Int? = nil,
    maxItems: Int? = nil,
    objectProperties: [FenceParameterSpec] = [],
    objectAdditionalProperties: Bool = false,
    arrayItemType: FenceParameterSpec.ParamType? = nil,
    arrayItemProperties: [FenceParameterSpec] = [],
    arrayItemAdditionalProperties: Bool = false
) -> FenceParameterSpec {
    let constraints = FenceParameterJSONSchemaConstraints(
        enumValues: enumValues,
        defaultValue: defaultValue,
        minimum: minimum,
        maximum: maximum,
        exclusiveMinimum: exclusiveMinimum,
        minLength: minLength,
        minItems: minItems,
        maxItems: maxItems
    )
    let jsonSchema = parameterJSONSchema(
        type,
        constraints: constraints,
        objectProperties: objectProperties,
        objectAdditionalProperties: objectAdditionalProperties,
        arrayItemType: arrayItemType,
        arrayItemProperties: arrayItemProperties,
        arrayItemAdditionalProperties: arrayItemAdditionalProperties
    )

    return FenceParameterSpec(
        key: key.rawValue,
        type: type,
        required: required,
        enumValues: enumValues,
        defaultValue: defaultValue,
        minimum: minimum,
        maximum: maximum,
        exclusiveMinimum: exclusiveMinimum,
        minLength: minLength,
        minItems: minItems,
        maxItems: maxItems,
        jsonSchema: jsonSchema,
        objectProperties: objectProperties,
        objectAdditionalProperties: objectAdditionalProperties,
        arrayItemType: arrayItemType,
        arrayItemProperties: arrayItemProperties,
        arrayItemAdditionalProperties: arrayItemAdditionalProperties
    )
}

private func parameterJSONSchema(
    _ type: FenceParameterSpec.ParamType,
    constraints: FenceParameterJSONSchemaConstraints,
    objectProperties: [FenceParameterSpec],
    objectAdditionalProperties: Bool,
    arrayItemType: FenceParameterSpec.ParamType?,
    arrayItemProperties: [FenceParameterSpec],
    arrayItemAdditionalProperties: Bool
) -> FenceParameterJSONSchema {
    switch type {
    case .stringArray:
        return .array(items: .scalar(.string), constraints: constraints)
    case .object:
        guard !objectProperties.isEmpty else {
            return .object(constraints: constraints)
        }
        return .object(
            properties: objectProperties.map(FenceParameterJSONSchemaProperty.init),
            additionalProperties: objectAdditionalProperties,
            constraints: constraints
        )
    case .array:
        return .array(
            items: arrayItemType.map {
                arrayItemJSONSchema(
                    $0,
                    objectProperties: arrayItemProperties,
                    objectAdditionalProperties: arrayItemAdditionalProperties
                )
            },
            constraints: constraints
        )
    case .stringMatch:
        return .object(constraints: constraints)
    case .string, .integer, .number, .boolean:
        return .scalar(type, constraints: constraints)
    }
}

private func arrayItemJSONSchema(
    _ type: FenceParameterSpec.ParamType,
    objectProperties: [FenceParameterSpec],
    objectAdditionalProperties: Bool
) -> FenceParameterJSONSchema {
    switch type {
    case .stringArray:
        return .array(items: .scalar(.string))
    case .object:
        return .object(
            properties: objectProperties.map(FenceParameterJSONSchemaProperty.init),
            additionalProperties: objectAdditionalProperties
        )
    case .array:
        return .array()
    case .stringMatch:
        return .object()
    case .string, .integer, .number, .boolean:
        return .scalar(type)
    }
}

private func jsonSchemaNumber(_ value: Double) -> HeistValue {
    value.rounded(.towardZero) == value ? .int(Int(value)) : .double(value)
}

@_spi(ButtonHeistTooling) public enum MCPExposure: Sendable, Equatable {
    case directTool
    case notExposed
}

@_spi(ButtonHeistTooling) public struct MCPToolAnnotationSpec: Sendable, Equatable {
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

@_spi(ButtonHeistTooling) public extension FenceParameterSpec.ParamType {
    var jsonSchemaType: String {
        switch self {
        case .stringArray:
            return "array"
        case .stringMatch:
            return "object"
        default:
            return rawValue
        }
    }
}

@_spi(ButtonHeistTooling) public extension FenceCommandDescriptor {
    var inputJSONSchema: HeistValue {
        FenceParameterSpec.jsonInputSchema(
            parameters: parameters
        )
    }
}

@_spi(ButtonHeistTooling) public extension FenceParameterSpec {
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
            properties[spec.key] = spec.jsonSchema.heistValue
        }
        return properties
    }

    static func jsonInputSchema(
        parameters: [FenceParameterSpec]
    ) -> HeistValue {
        FenceParameterJSONSchema.object(
            properties: parameters.map(FenceParameterJSONSchemaProperty.init),
            additionalProperties: false
        ).heistValue
    }
}

@_spi(ButtonHeistTooling) public enum CLIExposure: Sendable, Equatable {
    case directCommand
    case notExposed
}

enum FenceParameterBlocks: Sendable {
    private static let matcherFields = ElementTarget.predicateSchemaFields.map(elementTargetFieldSpec)
    static let inlineElementTargetFields = ElementTarget.inlineSchemaFields.map(elementTargetFieldSpec)

    static let elementTarget: [FenceParameterSpec] = [
        param(.target, .object, objectProperties: inlineElementTargetFields),
    ]
    static let gestureElement = param(.element, .object, objectProperties: inlineElementTargetFields)
    static let gestureUnitPoint = param(.unitPoint, .object, objectProperties: unitPoint)
    static let gesturePoint = param(.point, .object, objectProperties: screenPoint)

    static let gesturePointSelection: [FenceParameterSpec] = [
        gestureElement,
        gestureUnitPoint,
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

    static let dragElementToPoint = param(
        .elementToPoint,
        .object,
        objectProperties: [
            gestureElement,
            param(.start, .object, objectProperties: unitPoint),
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

    /// Documented fields of an `AccessibilityPredicate.State` object (`exists`,
    /// `missing`, `all`). A `State` is recursive — `all` nests further states —
    /// so item objects allow additional keys and the decoder enforces the
    /// per-type required-field rules.
    private static let stateProperties: [FenceParameterSpec] = [
        param(.type, .string, enumValues: ["exists", "missing", "all"]),
        param(.element, .object, objectProperties: matcherFields),
        param(.target, .object, objectProperties: inlineElementTargetFields),
        param(.targetRef, .string),
        param(.states, .array, arrayItemType: .object, arrayItemProperties: [], arrayItemAdditionalProperties: true),
    ]

    private static let assertionProperties: [FenceParameterSpec] = [
        param(.type, .string, enumValues: ["exists", "missing", "all", "appeared", "disappeared", "updated"]),
        param(.element, .object, objectProperties: matcherFields),
        param(.target, .object, objectProperties: inlineElementTargetFields),
        param(.targetRef, .string),
        param(.property, .string, enumValues: fenceEnumValues(ElementProperty.self)),
        param(.before, .object, objectProperties: matcherFields),
        param(.after, .object, objectProperties: matcherFields),
        param(.states, .array, arrayItemType: .object, arrayItemProperties: [], arrayItemAdditionalProperties: true),
    ]

    private static let changeScopeProperties: [FenceParameterSpec] = [
        param(.type, .string, enumValues: ["screen", "elements", "all"]),
        param(
            .assertions,
            .array,
            arrayItemType: .object,
            arrayItemProperties: assertionProperties,
            arrayItemAdditionalProperties: true
        ),
        param(
            .scopes,
            .array,
            arrayItemType: .object,
            arrayItemProperties: [],
            arrayItemAdditionalProperties: true
        ),
    ]

    /// Object properties for an `AccessibilityPredicate` (the `expect` slot and
    /// the `wait` `predicate` field). State predicates use `element`, `target`,
    /// `target_ref`, or `states`; change predicates use `scopes`, whose children
    /// carry `screen` state assertions or `elements` delta assertions.
    private static let accessibilityPredicateProperties: [FenceParameterSpec] = [
        predicateType,
        param(.element, .object, objectProperties: matcherFields),
        param(.target, .object, objectProperties: inlineElementTargetFields),
        param(.targetRef, .string),
        param(.property, .string, enumValues: fenceEnumValues(ElementProperty.self)),
        param(.before, .object, objectProperties: matcherFields),
        param(.after, .object, objectProperties: matcherFields),
        param(
            .states, .array,
            arrayItemType: .object,
            arrayItemProperties: stateProperties,
            arrayItemAdditionalProperties: true
        ),
        param(
            .scopes, .array,
            arrayItemType: .object,
            arrayItemProperties: changeScopeProperties,
            arrayItemAdditionalProperties: true
        ),
    ]

    static let expect: FenceParameterSpec = param(
        .expect, .object,
        objectProperties: accessibilityPredicateProperties
    )

    static let predicate: FenceParameterSpec = param(
        .predicate, .object, required: true,
        objectProperties: accessibilityPredicateProperties
    )

    static let expectationTimeout = param(.timeout, .number, maximum: defaultWaitTimeout, exclusiveMinimum: 0)
    static let expectation: [FenceParameterSpec] = [expect, expectationTimeout]

    /// Parameters for the unified `wait` command: a predicate plus a timeout.
    static let wait: [FenceParameterSpec] = [predicate, expectationTimeout]

    static let unitPoint: [FenceParameterSpec] = [
        param(.x, .number, required: true), param(.y, .number, required: true),
    ]
    static let screenPoint: [FenceParameterSpec] = unitPoint
    static let gestureDuration = param(
        .duration, .number,
        maximum: GestureDuration.maximumSeconds,
        exclusiveMinimum: 0
    )

    private static func stringMatchParam(_ key: FenceParameterKey, allowsArray: Bool = false) -> FenceParameterSpec {
        let modeValues = StringMatch<String>.Mode.allCases.map(\.rawValue)
        let description = "StringMatch object with mode \(modeValues.joined(separator: "/")) and value. " +
            "Use mode exact for exact matching. Broad modes require a non-empty value." +
            (allowsArray
                ? " Element matcher fields also accept an array of StringMatch objects; every object must match."
                : "")
        return FenceParameterSpec(
            key: key.rawValue,
            type: .stringMatch,
            required: false,
            enumValues: nil,
            defaultValue: nil,
            minimum: nil,
            maximum: nil,
            exclusiveMinimum: nil,
            minLength: nil,
            minItems: nil,
            maxItems: nil,
            jsonSchema: .stringMatch(modeValues: modeValues, description: description),
            objectProperties: [],
            objectAdditionalProperties: false,
            arrayItemType: nil,
            arrayItemProperties: [],
            arrayItemAdditionalProperties: false
        )
    }

    private static func elementTargetFieldSpec(_ field: ElementTarget.SchemaField) -> FenceParameterSpec {
        guard let key = FenceParameterKey(rawValue: field.name) else {
            preconditionFailure("ElementTarget field '\(field.name)' is not a Fence parameter key")
        }
        switch field.kind {
        case .predicateChecks:
            return predicateChecksParam(key)
        case .string:
            return param(key, .string)
        case .stringMatch:
            return stringMatchParam(key, allowsArray: true)
        case .stringArray:
            return param(key, .stringArray)
        case .nonNegativeInteger:
            return param(key, .integer, minimum: 0)
        }
    }

    private static func predicateChecksParam(_ key: FenceParameterKey) -> FenceParameterSpec {
        param(
            key, .array,
            arrayItemType: .object,
            arrayItemProperties: [
                param(
                    .kind, .string, required: true,
                    enumValues: ["label", "identifier", "value", "traits", "excludeTraits"]
                ),
                stringMatchParam(.match),
                param(.values, .stringArray),
            ],
            arrayItemAdditionalProperties: false
        )
    }
}

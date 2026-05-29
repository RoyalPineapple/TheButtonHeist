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
    public let jsonSchemaProperty: FenceJSONSchemaValue

}

extension TheFence {

    enum DecodeLimits {
        static let maxRunBatchSteps = 100
        static let maxRunBatchRequestBytes = 1_000_000
        static let maxRunBatchNestingDepth = 32
        static let maxBatchResultRows = maxRunBatchSteps
        static let maxInlineScreenshotBase64Bytes = 1_000_000
        static let maxInlineRecordingBase64Bytes = 10_000_000
        static let maxExpandedRecordingResponseBytes = 10_000_000

        static let maxDrawPathPoints = 10_000
        static let maxDrawBezierSegments = 1_000
        static let minDrawBezierSamplesPerSegment = 2
        static let maxDrawBezierSamplesPerSegment = DrawBezierTarget.maxSamplesPerSegment
        static let maxDrawBezierGeneratedPathPoints = 50_000
        static let maxDrawGestureDurationSeconds = 60.0
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
    static let centerX = Self("centerX"), centerY = Self("centerY"), command = Self("command")
    static let container = Self("container"), count = Self("count"), captureLocalRef = Self("captureLocalRef")
    static let cp1X = Self("cp1X"), cp1Y = Self("cp1Y"), cp2X = Self("cp2X"), cp2Y = Self("cp2Y")
    static let currentHeistId = Self("currentHeistId"), currentTextEndOffset = Self("currentTextEndOffset")
    static let currentTextStartOffset = Self("currentTextStartOffset"), deleteSource = Self("delete_source")
    static let detail = Self("detail"), device = Self("device"), direction = Self("direction"), duration = Self("duration")
    static let edge = Self("edge"), element = Self("element"), elements = Self("elements"), end = Self("end")
    static let endX = Self("endX"), endY = Self("endY"), excludeTraits = Self("excludeTraits")
    static let expect = Self("expect"), expectations = Self("expectations"), fps = Self("fps"), heistId = Self("heistId")
    static let identifier = Self("identifier"), inactivityTimeout = Self("inactivity_timeout")
    static let includeInteractionLog = Self("includeInteractionLog"), includeInterface = Self("includeInterface")
    static let inlineData = Self("inlineData"), input = Self("input"), isModalBoundary = Self("isModalBoundary")
    static let label = Self("label"), matcher = Self("matcher"), maxDuration = Self("max_duration"), mode = Self("mode")
    static let newValue = Self("newValue"), oldValue = Self("oldValue"), ordinal = Self("ordinal"), output = Self("output")
    static let points = Self("points"), policy = Self("policy"), property = Self("property"), radius = Self("radius")
    static let rotor = Self("rotor"), rotorIndex = Self("rotorIndex"), samplesPerSegment = Self("samplesPerSegment")
    static let scale = Self("scale"), segments = Self("segments"), spread = Self("spread"), start = Self("start")
    static let startX = Self("startX"), startY = Self("startY"), stableId = Self("stableId"), steps = Self("steps")
    static let subtree = Self("subtree"), target = Self("target"), text = Self("text"), timeout = Self("timeout")
    static let token = Self("token"), traits = Self("traits"), type = Self("type"), value = Self("value")
    static let velocity = Self("velocity"), x = Self("x"), y = Self("y")
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
    var schema: [String: FenceJSONSchemaValue] = ["type": .string(type.jsonSchemaType)]
    if let enumValues { schema["enum"] = .array(enumValues.map { .string($0) }) }
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
            var items: [String: FenceJSONSchemaValue] = ["type": .string(arrayItemType.jsonSchemaType)]
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
        jsonSchemaProperty: .object(schema)
    )
}

private func addRequiredKeys(
    from specs: [FenceParameterSpec],
    to schema: inout [String: FenceJSONSchemaValue]
) {
    let required = specs.filter(\.required).map(\.key)
    if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
}

private func jsonSchemaNumber(_ value: Double) -> FenceJSONSchemaValue {
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

public struct MCPToolContract: Sendable, Equatable {
    public let name: String
    public let description: String
    public let parameters: [FenceParameterSpec]
    public let annotations: MCPToolAnnotationSpec?

    public init(
        name: String,
        description: String,
        parameters: [FenceParameterSpec],
        annotations: MCPToolAnnotationSpec? = nil
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.annotations = annotations
    }

    public var requiredParameterKeys: [String] {
        return parameters.filter(\.required).map(\.key)
    }
}

public typealias FenceJSONSchemaValue = HeistValue

public extension MCPToolContract {
    var inputJSONSchema: FenceJSONSchemaValue {
        FenceParameterSpec.jsonInputSchema(
            properties: FenceParameterSpec.jsonSchemaProperties(from: parameters),
            required: requiredParameterKeys
        )
    }
}

public extension FenceParameterSpec.ParamType {
    var jsonSchemaType: String {
        self == .stringArray ? "array" : rawValue
    }
}

public extension FenceParameterSpec {
    static func jsonSchemaProperties(from specs: [FenceParameterSpec]) -> [String: FenceJSONSchemaValue] {
        var properties: [String: FenceJSONSchemaValue] = [:]
        for spec in specs where properties[spec.key] == nil {
            properties[spec.key] = spec.jsonSchemaProperty
        }
        return properties
    }

    static func jsonInputSchema(
        properties: [String: FenceJSONSchemaValue],
        required: [String] = []
    ) -> FenceJSONSchemaValue {
        var schema: [String: FenceJSONSchemaValue] = [
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
    case sessionOnly
    case notExposed
}

enum FenceParameterBlocks: Sendable {
    private static let matcherFields = ElementTarget.matcherFieldNames.map(matcherFieldSpec)

    static let elementTarget: [FenceParameterSpec] = [
        param(.target, .object, objectProperties: [
            param(.heistId, .string),
        ] + matcherFields + [
            param(.ordinal, .integer, minimum: 0),
        ]),
    ]

    static let elementFilter = matcherFields

    private static let scrollContainerFields: [FenceParameterSpec] = [
        param(.stableId, .string), param(.captureLocalRef, .string),
    ]

    static let scrollContainerTarget: [FenceParameterSpec] = scrollContainerFields + [
        param(.container, .object, objectProperties: scrollContainerFields),
    ]

    private static let subtreeElementProperties = [param(.heistId, .string)] + matcherFields

    private static let subtreeContainerProperties: [FenceParameterSpec] = [
        param(.stableId, .string),
        param(.type, .string, enumValues: fenceEnumValues(ContainerTypeName.self)),
        param(.label, .string), param(.value, .string), param(.identifier, .string),
        param(.isModalBoundary, .boolean),
    ]

    static let interfaceSubtree: FenceParameterSpec = param(
        .subtree, .object,
        objectProperties: [
            param(.element, .object, objectProperties: subtreeElementProperties),
            param(.container, .object, objectProperties: subtreeContainerProperties),
            param(.ordinal, .integer, minimum: 0),
        ]
    )

    private static let expectationType = param(
        .type, .string, required: true,
        enumValues: ActionExpectation.wireTypeValues
    )

    static let expect: FenceParameterSpec = param(
        .expect, .object,
        objectProperties: [
            expectationType,
            param(.heistId, .string),
            param(.property, .string, enumValues: fenceEnumValues(ElementProperty.self)),
            param(.oldValue, .string),
            param(.newValue, .string),
            param(.matcher, .object, objectProperties: matcherFields),
            param(
                .expectations, .array,
                arrayItemType: .object,
                arrayItemProperties: [expectationType],
                arrayItemAdditionalProperties: true
            ),
        ]
    )

    static let expectationTimeout = param(.timeout, .number, maximum: 30)
    static let expectation: [FenceParameterSpec] = [expect, expectationTimeout]

    static let unitPoint: [FenceParameterSpec] = [
        param(.x, .number, required: true), param(.y, .number, required: true),
    ]
    static let coordinateXY: [FenceParameterSpec] = [param(.x, .number), param(.y, .number)]
    static let optionalStart: [FenceParameterSpec] = [param(.startX, .number), param(.startY, .number)]
    static let requiredStart: [FenceParameterSpec] = [
        param(.startX, .number, required: true), param(.startY, .number, required: true),
    ]
    static let optionalEnd: [FenceParameterSpec] = [param(.endX, .number), param(.endY, .number)]
    static let requiredEnd: [FenceParameterSpec] = [
        param(.endX, .number, required: true), param(.endY, .number, required: true),
    ]
    static let center: [FenceParameterSpec] = [param(.centerX, .number), param(.centerY, .number)]
    static let gestureDuration = param(
        .duration, .number,
        maximum: TheFence.DecodeLimits.maxDrawGestureDurationSeconds
    )
    static let incrementCount = param(.count, .integer, minimum: 1, maximum: 100)

    private static func matcherFieldSpec(_ name: String) -> FenceParameterSpec {
        guard let key = FenceParameterKey(rawValue: name) else {
            preconditionFailure("ElementTarget matcher field '\(name)' is not a Fence parameter key")
        }
        switch key {
        case .label, .identifier, .value:
            return param(key, .string)
        case .traits, .excludeTraits:
            return param(key, .stringArray)
        default:
            preconditionFailure("ElementTarget matcher field '\(name)' is not mapped in Fence parameter specs")
        }
    }

    static let bezierSegment: [FenceParameterSpec] = [
        param(.cp1X, .number, required: true), param(.cp1Y, .number, required: true),
        param(.cp2X, .number, required: true), param(.cp2Y, .number, required: true),
        param(.endX, .number, required: true), param(.endY, .number, required: true),
    ]
}

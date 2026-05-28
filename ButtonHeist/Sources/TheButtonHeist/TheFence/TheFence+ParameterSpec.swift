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
    private static let matcherFields: [FenceParameterSpec] = [
        param(.label, .string), param(.identifier, .string), param(.value, .string),
        param(.traits, .stringArray), param(.excludeTraits, .stringArray),
    ]

    static let elementTarget: [FenceParameterSpec] = [
        param(.target, .object, objectProperties: [
            param(.heistId, .string),
            param(.matcher, .object, objectProperties: matcherFields),
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

    static let bezierSegment: [FenceParameterSpec] = [
        param(.cp1X, .number, required: true), param(.cp1Y, .number, required: true),
        param(.cp2X, .number, required: true), param(.cp2Y, .number, required: true),
        param(.endX, .number, required: true), param(.endY, .number, required: true),
    ]
}

extension TheFence.Command {

    var catalogParameters: [FenceParameterSpec] {
        let target = FenceParameterBlocks.elementTarget
        let scrollContainerTarget = FenceParameterBlocks.scrollContainerTarget
        let filter = FenceParameterBlocks.elementFilter
        let expect = FenceParameterBlocks.expect
        let expectation = FenceParameterBlocks.expectation
        let duration = FenceParameterBlocks.gestureDuration

        switch self {

        case .help, .quit, .ping, .listDevices, .getSessionState,
             .listTargets, .getSessionLog:
            return []

        case .dismissKeyboard:
            return expectation

        case .getInterface:
            return filter + [
                FenceParameterBlocks.interfaceSubtree,
                param(.detail, .string, enumValues: fenceEnumValues(InterfaceDetail.self)),
            ]

        case .getScreen:
            return [param(.output, .string), param(.inlineData, .boolean), param(.includeInterface, .boolean)]

        case .waitForChange:
            return expectation

        case .oneFingerTap:
            return target + FenceParameterBlocks.coordinateXY + expectation

        case .longPress:
            return target + FenceParameterBlocks.coordinateXY + [duration] + expectation

        case .swipe:
            return target + [
                param(.direction, .string, enumValues: fenceEnumValues(SwipeDirection.self)),
                param(.start, .object, objectProperties: FenceParameterBlocks.unitPoint),
                param(.end, .object, objectProperties: FenceParameterBlocks.unitPoint),
            ] + FenceParameterBlocks.optionalStart + FenceParameterBlocks.optionalEnd + [duration] + expectation

        case .drag:
            return target + FenceParameterBlocks.requiredEnd + FenceParameterBlocks.optionalStart + [duration] + expectation

        case .pinch:
            return target + [param(.scale, .number, required: true)] + FenceParameterBlocks.center + [
                param(.spread, .number), duration,
            ] + expectation

        case .rotate:
            return target + [param(.angle, .number, required: true)] + FenceParameterBlocks.center + [
                param(.radius, .number), duration,
            ] + expectation

        case .twoFingerTap:
            return target + FenceParameterBlocks.center + [param(.spread, .number)] + expectation

        case .drawPath:
            return [
                param(
                    .points, .array, required: true,
                    minItems: 2,
                    maxItems: TheFence.DecodeLimits.maxDrawPathPoints,
                    arrayItemType: .object,
                    arrayItemProperties: FenceParameterBlocks.unitPoint
                ),
                duration,
                param(.velocity, .number),
            ] + expectation

        case .drawBezier:
            return FenceParameterBlocks.requiredStart + [
                param(
                    .segments, .array, required: true,
                    minItems: 1,
                    maxItems: TheFence.DecodeLimits.maxDrawBezierSegments,
                    arrayItemType: .object,
                    arrayItemProperties: FenceParameterBlocks.bezierSegment
                ),
                param(
                    .samplesPerSegment, .integer,
                    minimum: Double(TheFence.DecodeLimits.minDrawBezierSamplesPerSegment),
                    maximum: Double(TheFence.DecodeLimits.maxDrawBezierSamplesPerSegment)
                ),
                duration,
                param(.velocity, .number),
            ] + expectation

        case .scroll:
            return scrollContainerTarget + target + [
                param(
                    .direction, .string,
                    enumValues: fenceEnumValues(ScrollDirection.self),
                    defaultValue: .string(ScrollDirection.down.rawValue)
                ),
            ] + expectation

        case .scrollToVisible:
            return target + expectation

        case .elementSearch:
            return target + [
                param(.direction, .string, enumValues: fenceEnumValues(ScrollSearchDirection.self)),
            ] + expectation

        case .scrollToEdge:
            return scrollContainerTarget + target + [
                param(
                    .edge, .string,
                    enumValues: fenceEnumValues(ScrollEdge.self),
                    defaultValue: .string(ScrollEdge.top.rawValue)
                ),
            ] + expectation

        case .activate:
            return target + [param(.action, .string), FenceParameterBlocks.incrementCount] + expectation

        case .rotor:
            return target + [
                param(.rotor, .string),
                param(.rotorIndex, .integer, minimum: 0),
                param(
                    .direction, .string,
                    enumValues: fenceEnumValues(RotorDirection.self),
                    defaultValue: .string(RotorDirection.next.rawValue)
                ),
                param(.currentHeistId, .string),
                param(.currentTextStartOffset, .integer, minimum: 0),
                param(.currentTextEndOffset, .integer, minimum: 0),
            ] + expectation

        case .typeText:
            return target + [param(.text, .string, required: true, minLength: 1)] + expectation

        case .editAction:
            return [param(.action, .string, required: true, enumValues: fenceEnumValues(EditAction.self))] + expectation

        case .setPasteboard:
            return [param(.text, .string, required: true)] + expectation

        case .getPasteboard:
            return []

        case .waitFor:
            return target + [param(.absent, .boolean), FenceParameterBlocks.expectationTimeout, expect]

        case .startRecording:
            return [
                param(.fps, .integer, minimum: 1, maximum: 15),
                param(.scale, .number, minimum: 0.25, maximum: 1.0),
                param(.maxDuration, .number),
                param(.inactivityTimeout, .number),
            ]

        case .stopRecording:
            return [param(.output, .string), param(.inlineData, .boolean), param(.includeInteractionLog, .boolean)]

        case .runBatch:
            return [
                param(
                    .steps, .array, required: true,
                    minItems: 1,
                    maxItems: TheFence.DecodeLimits.maxRunBatchSteps,
                    arrayItemType: .object,
                    arrayItemProperties: [
                        param(
                            .command, .string, required: true,
                            enumValues: Self.batchExecutableCases.map(\.rawValue)
                        ),
                        expect,
                    ],
                    arrayItemAdditionalProperties: true
                ),
                param(.policy, .string, enumValues: fenceEnumValues(TheFence.BatchPolicy.self)),
            ]

        case .connect:
            return [param(.target, .string), param(.device, .string), param(.token, .string)]

        case .archiveSession:
            return [param(.deleteSource, .boolean)]

        case .startHeist:
            return [param(.app, .string), param(.identifier, .string)]

        case .stopHeist:
            return [param(.output, .string, required: true)]

        case .playHeist:
            return [param(.input, .string, required: true)]
        }
    }
}

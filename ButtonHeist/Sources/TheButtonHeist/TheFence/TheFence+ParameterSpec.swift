import Foundation
import TheScore

// MARK: - Parameter Specification

/// Describes one parameter key that TheFence extracts from the `[String: Any]` request dictionary.
/// Used to generate MCP tool schemas and verify CLI/MCP sync.
///
/// Declared at module scope (not nested in TheFence) to avoid inheriting @ButtonHeistActor isolation.
public struct FenceParameterSpec: Sendable, Equatable {

    // MARK: - Nested Types

    /// JSON-level type of a parameter value.
    public enum ParamType: String, Sendable, Equatable {
        case string
        case integer
        case number       // double
        case boolean
        case stringArray
        case object
        case array        // generic array (points, segments, steps)
    }

    // MARK: - Properties

    public let key: String
    public let type: ParamType
    public let required: Bool
    public let enumValues: [String]?
    public let minimum: Double?
    public let maximum: Double?
    public let minLength: Int?
    public let minItems: Int?
    public let maxItems: Int?
    public let objectProperties: [FenceParameterSpec]
    public let objectAdditionalProperties: Bool
    public let arrayItemType: ParamType?
    public let arrayItemProperties: [FenceParameterSpec]
    public let arrayItemAdditionalProperties: Bool

    // MARK: - Init

    public init(
        key: String,
        type: ParamType,
        required: Bool = false,
        enumValues: [String]? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        objectProperties: [FenceParameterSpec] = [],
        objectAdditionalProperties: Bool = false,
        arrayItemType: ParamType? = nil,
        arrayItemProperties: [FenceParameterSpec] = [],
        arrayItemAdditionalProperties: Bool = false
    ) {
        self.key = key
        self.type = type
        self.required = required
        self.enumValues = enumValues
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.minItems = minItems
        self.maxItems = maxItems
        self.objectProperties = objectProperties
        self.objectAdditionalProperties = objectAdditionalProperties
        self.arrayItemType = arrayItemType
        self.arrayItemProperties = arrayItemProperties
        self.arrayItemAdditionalProperties = arrayItemAdditionalProperties
    }
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
        static let maxDrawBezierSamplesPerSegment = 1_000
        static let maxDrawBezierGeneratedPathPoints = 50_000
        static let maxDrawGestureDurationSeconds = 60.0
    }
}

/// Canonical external request keys owned by The Fence.
public enum FenceParameterKey: String, CaseIterable, Sendable {
    case absent
    case action
    case angle
    case app
    case centerX
    case centerY
    case command
    case container
    case count
    case cp1X
    case cp1Y
    case cp2X
    case cp2Y
    case captureLocalRef
    case currentHeistId
    case currentTextEndOffset
    case currentTextStartOffset
    case deleteSource = "delete_source"
    case detail
    case device
    case direction
    case duration
    case edge
    case element
    case elements
    case end
    case endX
    case endY
    case excludeTraits
    case expect
    case expectations
    case fps
    case heistId
    case identifier
    case inactivityTimeout = "inactivity_timeout"
    case includeInteractionLog
    case includeInterface
    case inlineData
    case input
    case isModalBoundary
    case label
    case matcher
    case maxDuration = "max_duration"
    case mode
    case newValue
    case oldValue
    case ordinal
    case output
    case points
    case policy
    case property
    case radius
    case rotor
    case rotorIndex
    case samplesPerSegment
    case scale
    case segments
    case spread
    case start
    case startX
    case startY
    case stableId
    case steps
    case subtree
    case target
    case text
    case timeout
    case token
    case traits
    case type
    case value
    case velocity
    case x
    case y
}

public extension FenceParameterSpec {
    init(
        key: FenceParameterKey,
        type: ParamType,
        required: Bool = false,
        enumValues: [String]? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        objectProperties: [FenceParameterSpec] = [],
        objectAdditionalProperties: Bool = false,
        arrayItemType: ParamType? = nil,
        arrayItemProperties: [FenceParameterSpec] = [],
        arrayItemAdditionalProperties: Bool = false
    ) {
        self.init(
            key: key.rawValue,
            type: type,
            required: required,
            enumValues: enumValues,
            minimum: minimum,
            maximum: maximum,
            minLength: minLength,
            objectProperties: objectProperties,
            objectAdditionalProperties: objectAdditionalProperties,
            arrayItemType: arrayItemType,
            arrayItemProperties: arrayItemProperties,
            arrayItemAdditionalProperties: arrayItemAdditionalProperties
        )
    }
}

func fenceEnumValues<E>(_ type: E.Type) -> [String] where E: CaseIterable & RawRepresentable, E.RawValue == String {
    type.allCases.map(\.rawValue)
}

func param(
    _ key: FenceParameterKey,
    _ type: FenceParameterSpec.ParamType,
    required: Bool = false,
    enumValues: [String]? = nil,
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
    FenceParameterSpec(
        key: key.rawValue,
        type: type,
        required: required,
        enumValues: enumValues,
        minimum: minimum,
        maximum: maximum,
        minLength: minLength,
        minItems: minItems,
        maxItems: maxItems,
        objectProperties: objectProperties,
        objectAdditionalProperties: objectAdditionalProperties,
        arrayItemType: arrayItemType,
        arrayItemProperties: arrayItemProperties,
        arrayItemAdditionalProperties: arrayItemAdditionalProperties
    )
}

// MARK: - MCP Exposure

/// How a command is surfaced in the MCP tool list.
///
/// Declared at module scope to avoid inheriting @ButtonHeistActor isolation.
public enum MCPExposure: Sendable, Equatable {
    /// Tool name equals command rawValue (1:1 mapping).
    case directTool
    /// Command is routed through a grouped tool (e.g. gestures via the "gesture" tool).
    case groupedUnder(String)
    /// Not exposed via MCP (REPL-only or subsumed by another command).
    case notExposed
}

/// Selector metadata for an MCP tool that routes to more than one Fence command.
///
/// This is part of the command contract because it defines the external tool
/// parameter that selects the canonical Fence command. The MCP adapter renders
/// it; runtime routing also consumes it.
public struct MCPToolSelector: Sendable, Equatable {
    public let parameter: FenceParameterSpec
    public let defaultValue: String?
    public let commandByValue: [String: TheFence.Command]
    public let consumedValues: Set<String>

    public init(
        parameter: FenceParameterSpec,
        defaultValue: String? = nil,
        commandByValue: [String: TheFence.Command],
        consumedValues: Set<String>? = nil
    ) {
        self.parameter = parameter
        self.defaultValue = defaultValue
        self.commandByValue = commandByValue
        self.consumedValues = consumedValues ?? Set(commandByValue.keys)
    }

    public func command(for value: String?) -> TheFence.Command? {
        guard let value else {
            guard let defaultValue else { return nil }
            return commandByValue[defaultValue]
        }
        return commandByValue[value]
    }

    public func selectorValue(for command: TheFence.Command) -> String? {
        let values = commandByValue.compactMap { $0.value == command ? $0.key : nil }
        return values.count == 1 ? values[0] : nil
    }

    public func consumesValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return consumedValues.contains(value)
    }
}

/// MCP annotation metadata owned by the canonical tool contract.
///
/// The MCP adapter translates this neutral spec into SDK-specific annotation
/// values without owning the command-name lists that receive those annotations.
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

/// Canonical MCP-facing tool contract derived from the Fence command catalog.
///
/// MCP adapters render tool metadata and schemas from this contract instead of
/// hand-maintaining command-name or parameter-name mirrors.
public struct MCPToolContract: Sendable, Equatable {
    public let name: String
    public let commands: [TheFence.Command]
    public let selector: MCPToolSelector?
    public let description: String
    public let annotations: MCPToolAnnotationSpec?

    public init(
        name: String,
        commands: [TheFence.Command],
        selector: MCPToolSelector? = nil,
        description: String,
        annotations: MCPToolAnnotationSpec? = nil
    ) {
        self.name = name
        self.commands = commands
        self.selector = selector
        self.description = description
        self.annotations = annotations
    }

    public var parameters: [FenceParameterSpec] {
        var merged: [FenceParameterSpec] = []
        for spec in commands.flatMap(\.parameters) {
            append(spec, to: &merged, replacingExisting: false)
        }
        if let selector {
            append(selector.parameter, to: &merged, replacingExisting: true)
        }
        return merged
    }

    public var requiredParameterKeys: [String] {
        if let selector {
            // Selector tools flatten several command shapes into one Claude-compatible
            // schema. Requiring command-specific keys here would overconstrain other
            // selector values without JSON Schema composition.
            return selector.parameter.required ? [selector.parameter.key] : []
        }
        return parameters.filter(\.required).map(\.key)
    }

    private func append(
        _ spec: FenceParameterSpec,
        to specs: inout [FenceParameterSpec],
        replacingExisting: Bool
    ) {
        guard let existingIndex = specs.firstIndex(where: { $0.key == spec.key }) else {
            specs.append(spec)
            return
        }
        if replacingExisting {
            specs[existingIndex] = spec
        }
    }
}

/// Neutral JSON Schema value owned by the Fence command contract.
///
/// Adapters translate this tree into their transport-specific value type; they
/// do not own schema literals or parameter-shape branching.
public enum FenceJSONSchemaValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([FenceJSONSchemaValue])
    case object([String: FenceJSONSchemaValue])
}

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
        switch self {
        case .string:
            return "string"
        case .integer:
            return "integer"
        case .number:
            return "number"
        case .boolean:
            return "boolean"
        case .stringArray, .array:
            return "array"
        case .object:
            return "object"
        }
    }
}

public extension FenceParameterSpec {
    var jsonSchemaProperty: FenceJSONSchemaValue {
        Self.jsonSchemaProperty(for: self)
    }

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

    static func jsonSchemaProperty(for spec: FenceParameterSpec) -> FenceJSONSchemaValue {
        var schema: [String: FenceJSONSchemaValue] = ["type": .string(spec.type.jsonSchemaType)]
        if let enumValues = spec.enumValues { schema["enum"] = .array(enumValues.map { .string($0) }) }
        if let minimum = spec.minimum { schema["minimum"] = jsonSchemaNumber(minimum) }
        if let maximum = spec.maximum { schema["maximum"] = jsonSchemaNumber(maximum) }
        if let minLength = spec.minLength { schema["minLength"] = .int(minLength) }
        if let minItems = spec.minItems { schema["minItems"] = .int(minItems) }
        if let maxItems = spec.maxItems { schema["maxItems"] = .int(maxItems) }

        switch spec.type {
        case .stringArray:
            schema["items"] = .object(["type": .string(FenceParameterSpec.ParamType.string.jsonSchemaType)])

        case .object where !spec.objectProperties.isEmpty:
            schema["properties"] = .object(jsonSchemaProperties(from: spec.objectProperties))
            let required = spec.objectProperties.filter(\.required).map(\.key)
            if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
            schema["additionalProperties"] = .bool(spec.objectAdditionalProperties)

        case .array:
            if let itemType = spec.arrayItemType {
                var items: [String: FenceJSONSchemaValue] = ["type": .string(itemType.jsonSchemaType)]
                if itemType == .object {
                    items["properties"] = .object(jsonSchemaProperties(from: spec.arrayItemProperties))
                    let required = spec.arrayItemProperties.filter(\.required).map(\.key)
                    if !required.isEmpty { items["required"] = .array(required.map { .string($0) }) }
                    items["additionalProperties"] = .bool(spec.arrayItemAdditionalProperties)
                }
                schema["items"] = .object(items)
            }

        default:
            break
        }

        return .object(schema)
    }

    private static func jsonSchemaNumber(_ value: Double) -> FenceJSONSchemaValue {
        if value.rounded(.towardZero) == value {
            return .int(Int(value))
        }
        return .double(value)
    }
}

// MARK: - CLI Exposure

/// How a command is surfaced by the top-level `buttonheist` CLI.
///
/// Declared next to `MCPExposure` so command-surface contracts live with the
/// command catalog instead of being reverse-engineered from docs.
public enum CLIExposure: Sendable, Equatable {
    /// Top-level CLI command name equals the command raw value.
    case directCommand
    /// Command is routed through another top-level command.
    case groupedUnder(String)
    /// Only accepted by the interactive session parser or raw JSON mode.
    case sessionOnly
    /// Not exposed by the CLI.
    case notExposed
}

// MARK: - Shared Parameter Blocks

/// Reusable parameter groups shared across command specs.
/// At module scope so they're not actor-isolated.
enum FenceParameterBlocks: Sendable {
    static let elementTarget: [FenceParameterSpec] = [
        param(.heistId, .string), param(.label, .string), param(.value, .string),
        param(.traits, .stringArray), param(.excludeTraits, .stringArray),
        param(.identifier, .string), param(.ordinal, .integer),
    ]

    static var elementFilter: [FenceParameterSpec] {
        elementTarget.filter {
            $0.key != FenceParameterKey.heistId.rawValue && $0.key != FenceParameterKey.ordinal.rawValue
        }
    }

    private static let scrollContainerFields: [FenceParameterSpec] = [
        param(.stableId, .string), param(.captureLocalRef, .string),
    ]

    static let scrollContainerTarget: [FenceParameterSpec] = scrollContainerFields + [
        param(.container, .object, objectProperties: scrollContainerFields),
    ]

    private static let subtreeElementProperties: [FenceParameterSpec] = [
        param(.heistId, .string), param(.label, .string), param(.value, .string),
        param(.identifier, .string), param(.traits, .stringArray), param(.excludeTraits, .stringArray),
    ]

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

    private static let expectationMatcherProperties: [FenceParameterSpec] = [
        param(.label, .string), param(.identifier, .string), param(.value, .string),
        param(.traits, .stringArray), param(.excludeTraits, .stringArray),
    ]

    static let expect: FenceParameterSpec = param(
        .expect, .object,
        objectProperties: [
            expectationType,
            param(.heistId, .string),
            param(.property, .string, enumValues: fenceEnumValues(ElementProperty.self)),
            param(.oldValue, .string),
            param(.newValue, .string),
            param(.matcher, .object, objectProperties: expectationMatcherProperties),
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

// MARK: - Per-Command Specs

extension TheFence.Command {

    /// All parameter keys this command extracts from the request dictionary.
    /// Does not include the "command" key itself or internal keys like "_requestId".
    var catalogParameters: [FenceParameterSpec] {
        let target = FenceParameterBlocks.elementTarget
        let scrollContainerTarget = FenceParameterBlocks.scrollContainerTarget
        let filter = FenceParameterBlocks.elementFilter
        let expect = FenceParameterBlocks.expect
        let expectation = FenceParameterBlocks.expectation
        let duration = FenceParameterBlocks.gestureDuration

        switch self {

        // MARK: No parameters (meta / read-only)
        case .help, .quit, .exit, .status, .ping, .listDevices, .getSessionState,
             .listTargets, .getSessionLog:
            return []

        case .dismissKeyboard:
            return expectation

        // MARK: Interface / observation
        case .getInterface:
            return filter + [
                FenceParameterBlocks.interfaceSubtree,
                param(.detail, .string, enumValues: fenceEnumValues(InterfaceDetail.self)),
                param(.elements, .stringArray),
            ]

        case .getScreen:
            return [param(.output, .string), param(.inlineData, .boolean), param(.includeInterface, .boolean)]

        case .waitForChange:
            return expectation

        // MARK: Gestures
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

        // MARK: Scroll
        case .scroll:
            return scrollContainerTarget + target + [
                param(.direction, .string, enumValues: fenceEnumValues(ScrollDirection.self)),
            ] + expectation

        case .scrollToVisible:
            return target + expectation

        case .elementSearch:
            return target + [
                param(.direction, .string, enumValues: fenceEnumValues(ScrollSearchDirection.self)),
            ] + expectation

        case .scrollToEdge:
            return scrollContainerTarget + target + [
                param(.edge, .string, enumValues: fenceEnumValues(ScrollEdge.self)),
            ] + expectation

        // MARK: Accessibility actions
        case .activate:
            return target + [param(.action, .string), FenceParameterBlocks.incrementCount] + expectation

        case .increment, .decrement:
            return target + [FenceParameterBlocks.incrementCount] + expectation

        case .performCustomAction:
            return target + [param(.container, .object), param(.action, .string, required: true)] + expectation

        case .rotor:
            return target + [
                param(.rotor, .string),
                param(.rotorIndex, .integer, minimum: 0),
                param(.direction, .string, enumValues: fenceEnumValues(RotorDirection.self)),
                param(.currentHeistId, .string),
                param(.currentTextStartOffset, .integer, minimum: 0),
                param(.currentTextEndOffset, .integer, minimum: 0),
            ] + expectation

        // MARK: Text / keyboard
        case .typeText:
            return target + [param(.text, .string, required: true, minLength: 1)] + expectation

        case .editAction:
            return [param(.action, .string, required: true, enumValues: fenceEnumValues(EditAction.self))] + expectation

        // MARK: Pasteboard
        case .setPasteboard:
            return [param(.text, .string, required: true)] + expectation

        case .getPasteboard:
            return []

        // MARK: Wait
        case .waitFor:
            return target + [param(.absent, .boolean), FenceParameterBlocks.expectationTimeout, expect]

        // MARK: Recording
        case .startRecording:
            return [
                param(.fps, .integer, minimum: 1, maximum: 15),
                param(.scale, .number, minimum: 0.25, maximum: 1.0),
                param(.maxDuration, .number),
                param(.inactivityTimeout, .number),
            ]

        case .stopRecording:
            return [param(.output, .string), param(.inlineData, .boolean), param(.includeInteractionLog, .boolean)]

        // MARK: Batch
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

        // MARK: Connection
        case .connect:
            return [param(.target, .string), param(.device, .string), param(.token, .string)]

        // MARK: Session management
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

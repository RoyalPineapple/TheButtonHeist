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

    /// Why a non-required parameter belongs in the public command contract.
    public enum OptionalRole: String, Sendable, Equatable {
        case matcher
        case payload
        case behaviorSwitch
        case compatibility
    }

    // MARK: - Properties

    public let key: String
    public let type: ParamType
    public let required: Bool
    public let optionalRole: OptionalRole?
    public let description: String?
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
        optionalRole: OptionalRole? = nil,
        description: String? = nil,
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
        self.optionalRole = optionalRole
        self.description = description
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
        description: String? = nil,
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
            description: description,
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
        if let description = spec.description { schema["description"] = .string(description) }
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

    /// Element targeting: heistId, label, value, traits, excludeTraits, identifier, ordinal.
    /// Used by action/gesture/scroll commands that call `elementTarget(args)`.
    static let elementTarget: [FenceParameterSpec] = [
        .init(
            key: "heistId", type: .string, optionalRole: .matcher,
            description: """
                Current-hierarchy heistId handle returned by get_interface or an action delta. \
                Recordings persist minimum matchers for durable replay.
                """
        ),
        .init(key: "label", type: .string, optionalRole: .matcher, description: "Accessibility label — the text VoiceOver reads (e.g. \"Sign In\")"),
        .init(key: "value", type: .string, optionalRole: .matcher, description: "Accessibility value — current state or placeholder (e.g. \"50%\")"),
        .init(
            key: "traits", type: .stringArray, optionalRole: .matcher,
            description: "Required traits (role qualifiers like button, header, selected). All must match."
        ),
        .init(key: "excludeTraits", type: .stringArray, optionalRole: .matcher, description: "Traits that must NOT be present"),
        .init(
            key: "identifier", type: .string, optionalRole: .matcher,
            description: "accessibilityIdentifier; preferred when developer-assigned and stable"
        ),
        .init(
            key: "ordinal", type: .integer, optionalRole: .matcher,
            description: """
                0-based index to disambiguate when multiple elements match, or as \
                the fallback target when no matcher predicates exist. 0 = first \
                match, 1 = second, etc. in the returned hierarchy order. Omit to \
                require a unique match — ambiguity errors show the valid range.
                """
        ),
    ]

    /// Element filtering: label, value, traits, excludeTraits, identifier (no heistId/ordinal).
    /// Used by get_interface when filtering returned interface elements.
    static let elementFilter: [FenceParameterSpec] = [
        .init(key: "label", type: .string, optionalRole: .matcher, description: "Accessibility label — the text VoiceOver reads (e.g. \"Sign In\")"),
        .init(key: "value", type: .string, optionalRole: .matcher, description: "Accessibility value — current state or placeholder (e.g. \"50%\")"),
        .init(
            key: "traits", type: .stringArray, optionalRole: .matcher,
            description: "Required traits (role qualifiers like button, header, selected). All must match."
        ),
        .init(key: "excludeTraits", type: .stringArray, optionalRole: .matcher, description: "Traits that must NOT be present"),
        .init(
            key: "identifier", type: .string, optionalRole: .matcher,
            description: "accessibilityIdentifier; preferred when developer-assigned and stable"
        ),
    ]

    /// Scroll-container targeting for commands that move a container directly.
    static let scrollContainerTarget: [FenceParameterSpec] = [
        .init(
            key: "stableId", type: .string, optionalRole: .matcher,
            description: "Scrollable container stableId returned by get_interface. Prefer this for scroll and scroll_to_edge."
        ),
        .init(
            key: "captureLocalRef", type: .string, optionalRole: .matcher,
            description: "Capture-local scroll container reference when supplied by the client."
        ),
        .init(
            key: "container", type: .object, optionalRole: .matcher,
            description: "Explicit scroll container selector. Use stableId or captureLocalRef.",
            objectProperties: [
                .init(key: "stableId", type: .string, optionalRole: .matcher),
                .init(key: "captureLocalRef", type: .string, optionalRole: .matcher),
            ]
        ),
    ]

    /// Subtree selector for get_interface. Cuts the parsed interface tree
    /// at one matched leaf or container node.
    static let interfaceSubtree: FenceParameterSpec = .init(
        key: "subtree", type: .object, optionalRole: .matcher,
        description: """
            Subtree selector within the parsed hierarchy. Omit for the whole tree. \
            Pass exactly one of element or container. A leaf subtree is just that leaf; \
            a container subtree includes the container and descendants. Ambiguous matches require ordinal.
            """,
        objectProperties: [
            .init(
                key: "element", type: .object, optionalRole: .matcher,
                description: "Leaf selector using ElementMatcher fields",
                objectProperties: [
                    .init(
                        key: "heistId", type: .string, optionalRole: .matcher,
                        description: "Leaf element heistId returned by get_interface or an action delta"
                    ),
                    .init(key: "label", type: .string, optionalRole: .matcher, description: "Exact leaf label"),
                    .init(key: "value", type: .string, optionalRole: .matcher, description: "Exact leaf value"),
                    .init(key: "identifier", type: .string, optionalRole: .matcher, description: "Exact leaf accessibility identifier"),
                    .init(
                        key: "traits", type: .stringArray, optionalRole: .matcher,
                        description: "Leaf traits that must all be present"
                    ),
                    .init(
                        key: "excludeTraits", type: .stringArray, optionalRole: .matcher,
                        description: "Leaf traits that must not be present"
                    ),
                ]
            ),
            .init(
                key: "container", type: .object, optionalRole: .matcher,
                description: "Container selector using ContainerMatcher fields",
                objectProperties: [
                    .init(
                        key: "stableId", type: .string, optionalRole: .matcher,
                        description: "Container stableId returned on container nodes"
                    ),
                    .init(
                        key: "type", type: .string, optionalRole: .matcher,
                        description: "Container type",
                        enumValues: fenceEnumValues(ContainerTypeName.self)
                    ),
                    .init(key: "label", type: .string, optionalRole: .matcher, description: "Exact semantic container label"),
                    .init(key: "value", type: .string, optionalRole: .matcher, description: "Exact semantic container value"),
                    .init(
                        key: "identifier", type: .string, optionalRole: .matcher,
                        description: "Exact semantic container accessibility identifier"
                    ),
                    .init(
                        key: "isModalBoundary", type: .boolean, optionalRole: .matcher,
                        description: "Container modal-boundary flag"
                    ),
                ]
            ),
            .init(
                key: "ordinal", type: .integer, optionalRole: .matcher,
                description: "0-based candidate index to disambiguate multiple matching subtree candidates",
                minimum: 0
            ),
        ]
    )

    /// Inline expectation for action commands.
    static let expect: FenceParameterSpec = .init(
        key: "expect", type: .object, optionalRole: .behaviorSwitch,
        description: """
            Inline verification for this action. Use {"type": "screen_changed"} or \
            {"type": "elements_changed"} for simple expectations, or object forms like \
            {"type": "element_updated"|"element_appeared"|"element_disappeared"|"compound", ...}. \
            See docs/MCP-AGENT-GUIDE.md for the full expectation vocabulary and recipes.
            """,
        objectProperties: [
            .init(
                key: "type", type: .string, required: true,
                description: "Object-form discriminator, such as screen_changed or element_updated.",
                enumValues: ActionExpectation.wireTypeValues
            ),
            .init(key: "heistId", type: .string, optionalRole: .matcher, description: "element_updated: match a specific element"),
            .init(
                key: "property", type: .string, optionalRole: .payload,
                description: "element_updated: match a specific property",
                enumValues: fenceEnumValues(ElementProperty.self)
            ),
            .init(key: "oldValue", type: .string, optionalRole: .payload, description: "element_updated: expected previous value"),
            .init(key: "newValue", type: .string, optionalRole: .payload, description: "element_updated: expected new value"),
            .init(
                key: "matcher", type: .object, optionalRole: .matcher,
                description: "element_appeared / element_disappeared: predicate identifying the element",
                objectProperties: [
                    .init(key: "label", type: .string, optionalRole: .matcher),
                    .init(key: "identifier", type: .string, optionalRole: .matcher),
                    .init(key: "value", type: .string, optionalRole: .matcher),
                    .init(key: "traits", type: .stringArray, optionalRole: .matcher),
                    .init(key: "excludeTraits", type: .stringArray, optionalRole: .matcher),
                ]
            ),
            .init(
                key: "expectations", type: .array, optionalRole: .payload,
                description: "compound: array of sub-expectation objects",
                arrayItemType: .object,
                arrayItemProperties: [
                    .init(
                        key: "type", type: .string, required: true,
                        enumValues: ActionExpectation.wireTypeValues
                    ),
                ],
                arrayItemAdditionalProperties: true
            ),
        ]
    )

    static let expectationTimeout: FenceParameterSpec = .init(
        key: "timeout", type: .number, optionalRole: .behaviorSwitch,
        description: "Max seconds to wait for the expectation when expect is provided (default: 10, max: 30)",
        maximum: 30
    )

    static let expectation: [FenceParameterSpec] = [expect, expectationTimeout]

    static let unitPoint: [FenceParameterSpec] = [
        .init(key: "x", type: .number, required: true, description: "X position (0-1)"),
        .init(key: "y", type: .number, required: true, description: "Y position (0-1)"),
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

        switch self {

        // MARK: No parameters (meta / read-only)
        case .help, .quit, .exit, .status, .ping, .listDevices, .getSessionState,
             .listTargets, .getSessionLog:
            return []

        // These take no targeting parameters but accept expect
        case .dismissKeyboard:
            return expectation

        // MARK: Interface / observation
        case .getInterface:
            return filter + [
                FenceParameterBlocks.interfaceSubtree,
                .init(
                    key: "detail", type: .string, optionalRole: .behaviorSwitch,
                    description: """
                        Level of detail. summary (default): identity fields, traits, and actions only \
                        — no hint, customContent, frames, or activation points. full: adds VoiceOver \
                        hint, customContent, frame, and activation point.
                        """,
                    enumValues: fenceEnumValues(InterfaceDetail.self)
                ),
                .init(
                    key: "elements", type: .stringArray, optionalRole: .matcher,
                    description: "Optional list of leaf heistId handles to return as subtrees. Omit for the app accessibility hierarchy."
                ),
            ]

        case .getScreen:
            return [
                .init(
                    key: "output", type: .string, optionalRole: .payload,
                    description: "File path to save PNG (omit for default artifact path; cannot be combined with inlineData=true)"
                ),
                .init(
                    key: "inlineData", type: .boolean, optionalRole: .behaviorSwitch,
                    description: """
                        Return base64 PNG data inline instead of an artifact path \
                        (default false; capped before delivery; not allowed inside run_batch)
                        """
                ),
                .init(
                    key: "includeInterface", type: .boolean, optionalRole: .behaviorSwitch,
                    description: "Include the fresh visible interface tree in the response (default false)"
                ),
            ]

        case .waitForChange:
            return [
                expect,
                .init(
                    key: "timeout", type: .number, optionalRole: .behaviorSwitch,
                    description: "Maximum wait time in seconds (default: 30, max: 30)",
                    maximum: 30
                ),
            ]

        // MARK: Gestures
        case .oneFingerTap:
            return target + [
                .init(key: "x", type: .number, optionalRole: .payload, description: "X coordinate"),
                .init(key: "y", type: .number, optionalRole: .payload, description: "Y coordinate"),
            ] + expectation

        case .longPress:
            return target + [
                .init(key: "x", type: .number, optionalRole: .payload, description: "X coordinate"),
                .init(key: "y", type: .number, optionalRole: .payload, description: "Y coordinate"),
                .init(
                    key: "duration", type: .number, optionalRole: .payload,
                    description: "Duration in seconds (default 0.5, max 60)",
                    maximum: TheFence.DecodeLimits.maxDrawGestureDurationSeconds
                ),
            ] + expectation

        case .swipe:
            return target + [
                .init(
                    key: "direction", type: .string, optionalRole: .payload,
                    description: "Swipe direction: up, down, left, right",
                    enumValues: fenceEnumValues(SwipeDirection.self)
                ),
                .init(
                    key: "start", type: .object, optionalRole: .payload,
                    description: "Swipe start unit point relative to element frame. (0,0)=top-left, (1,1)=bottom-right",
                    objectProperties: FenceParameterBlocks.unitPoint
                ),
                .init(
                    key: "end", type: .object, optionalRole: .payload,
                    description: "Swipe end unit point relative to element frame. (0,0)=top-left, (1,1)=bottom-right",
                    objectProperties: FenceParameterBlocks.unitPoint
                ),
                .init(key: "startX", type: .number, optionalRole: .payload, description: "Start X coordinate (swipe, draw_bezier)"),
                .init(key: "startY", type: .number, optionalRole: .payload, description: "Start Y coordinate (swipe, draw_bezier)"),
                .init(key: "endX", type: .number, optionalRole: .payload, description: "End X coordinate (swipe, drag)"),
                .init(key: "endY", type: .number, optionalRole: .payload, description: "End Y coordinate (swipe, drag)"),
                .init(
                    key: "duration", type: .number, optionalRole: .payload,
                    description: "Duration in seconds (max 60)",
                    maximum: TheFence.DecodeLimits.maxDrawGestureDurationSeconds
                ),
            ] + expectation

        case .drag:
            return target + [
                .init(key: "endX", type: .number, required: true, description: "End X coordinate (swipe, drag)"),
                .init(key: "endY", type: .number, required: true, description: "End Y coordinate (swipe, drag)"),
                .init(key: "startX", type: .number, optionalRole: .payload, description: "Start X coordinate (swipe, draw_bezier)"),
                .init(key: "startY", type: .number, optionalRole: .payload, description: "Start Y coordinate (swipe, draw_bezier)"),
                .init(
                    key: "duration", type: .number, optionalRole: .payload,
                    description: "Duration in seconds (max 60)",
                    maximum: TheFence.DecodeLimits.maxDrawGestureDurationSeconds
                ),
            ] + expectation

        case .pinch:
            return target + [
                .init(key: "scale", type: .number, required: true, description: "Pinch scale factor (>1 zoom in, <1 zoom out)"),
                .init(
                    key: "centerX", type: .number, optionalRole: .payload,
                    description: "Center X (pinch, rotate, two_finger_tap; defaults to element center)"
                ),
                .init(
                    key: "centerY", type: .number, optionalRole: .payload,
                    description: "Center Y (pinch, rotate, two_finger_tap; defaults to element center)"
                ),
                .init(key: "spread", type: .number, optionalRole: .payload, description: "Finger spread distance (pinch, two_finger_tap)"),
                .init(
                    key: "duration", type: .number, optionalRole: .payload,
                    description: "Duration in seconds (max 60)",
                    maximum: TheFence.DecodeLimits.maxDrawGestureDurationSeconds
                ),
            ] + expectation

        case .rotate:
            return target + [
                .init(key: "angle", type: .number, required: true, description: "Rotation angle in radians"),
                .init(
                    key: "centerX", type: .number, optionalRole: .payload,
                    description: "Center X (pinch, rotate, two_finger_tap; defaults to element center)"
                ),
                .init(
                    key: "centerY", type: .number, optionalRole: .payload,
                    description: "Center Y (pinch, rotate, two_finger_tap; defaults to element center)"
                ),
                .init(key: "radius", type: .number, optionalRole: .payload, description: "Rotation radius (rotate)"),
                .init(
                    key: "duration", type: .number, optionalRole: .payload,
                    description: "Duration in seconds (max 60)",
                    maximum: TheFence.DecodeLimits.maxDrawGestureDurationSeconds
                ),
            ] + expectation

        case .twoFingerTap:
            return target + [
                .init(
                    key: "centerX", type: .number, optionalRole: .payload,
                    description: "Center X (pinch, rotate, two_finger_tap; defaults to element center)"
                ),
                .init(
                    key: "centerY", type: .number, optionalRole: .payload,
                    description: "Center Y (pinch, rotate, two_finger_tap; defaults to element center)"
                ),
                .init(key: "spread", type: .number, optionalRole: .payload, description: "Finger spread distance (pinch, two_finger_tap)"),
            ] + expectation

        case .drawPath:
            return [
                .init(
                    key: "points", type: .array, required: true,
                    description: "Array of {x, y} waypoints (draw_path), 2...10,000 points",
                    minItems: 2,
                    maxItems: TheFence.DecodeLimits.maxDrawPathPoints,
                    arrayItemType: .object,
                    arrayItemProperties: [
                        .init(key: "x", type: .number, required: true, description: "X coordinate"),
                        .init(key: "y", type: .number, required: true, description: "Y coordinate"),
                    ]
                ),
                .init(
                    key: "duration", type: .number, optionalRole: .payload,
                    description: "Duration in seconds (draw_path, max 60)",
                    maximum: TheFence.DecodeLimits.maxDrawGestureDurationSeconds
                ),
                .init(key: "velocity", type: .number, optionalRole: .payload, description: "Drawing velocity in points/sec (draw_path, draw_bezier)"),
            ] + expectation

        case .drawBezier:
            return [
                .init(key: "startX", type: .number, required: true, description: "Start X coordinate (swipe, draw_bezier)"),
                .init(key: "startY", type: .number, required: true, description: "Start Y coordinate (swipe, draw_bezier)"),
                .init(
                    key: "segments", type: .array, required: true,
                    description: "Array of bezier segments: {cp1X, cp1Y, cp2X, cp2Y, endX, endY} (draw_bezier), 1...1,000 segments",
                    minItems: 1,
                    maxItems: TheFence.DecodeLimits.maxDrawBezierSegments,
                    arrayItemType: .object,
                    arrayItemProperties: [
                        .init(key: "cp1X", type: .number, required: true, description: "First control point X coordinate"),
                        .init(key: "cp1Y", type: .number, required: true, description: "First control point Y coordinate"),
                        .init(key: "cp2X", type: .number, required: true, description: "Second control point X coordinate"),
                        .init(key: "cp2Y", type: .number, required: true, description: "Second control point Y coordinate"),
                        .init(key: "endX", type: .number, required: true, description: "Segment end X coordinate"),
                        .init(key: "endY", type: .number, required: true, description: "Segment end Y coordinate"),
                    ]
                ),
                .init(
                    key: "samplesPerSegment", type: .integer, optionalRole: .payload,
                    description: "Bezier curve sampling resolution (draw_bezier), 2...1,000; generated path max 50,000 points",
                    minimum: Double(TheFence.DecodeLimits.minDrawBezierSamplesPerSegment),
                    maximum: Double(TheFence.DecodeLimits.maxDrawBezierSamplesPerSegment)
                ),
                .init(
                    key: "duration", type: .number, optionalRole: .payload,
                    description: "Duration in seconds (draw_bezier, max 60)",
                    maximum: TheFence.DecodeLimits.maxDrawGestureDurationSeconds
                ),
                .init(key: "velocity", type: .number, optionalRole: .payload, description: "Drawing velocity in points/sec (draw_path, draw_bezier)"),
            ] + expectation

        // MARK: Scroll
        case .scroll:
            return scrollContainerTarget + target + [
                .init(
                    key: "direction", type: .string, optionalRole: .payload,
                    description: """
                        Scroll direction. Defaults to down. next/previous are page-only directions for mode=page; \
                        mode=search accepts only up, down, left, right and is validated server-side.
                        """,
                    enumValues: fenceEnumValues(ScrollDirection.self)
                ),
            ] + expectation

        case .scrollToVisible:
            return target + expectation

        case .elementSearch:
            return target + [
                .init(
                    key: "direction", type: .string, optionalRole: .payload,
                    description: "Scroll search direction: down, up, left, right",
                    enumValues: fenceEnumValues(ScrollSearchDirection.self)
                ),
            ] + expectation

        case .scrollToEdge:
            return scrollContainerTarget + target + [
                .init(
                    key: "edge", type: .string, optionalRole: .payload,
                    description: "Edge to scroll to. Defaults to top.",
                    enumValues: fenceEnumValues(ScrollEdge.self)
                ),
            ] + expectation

        // MARK: Accessibility actions
        case .activate:
            return target + [
                .init(
                    key: "action", type: .string, optionalRole: .payload,
                    description: "Named action (e.g. \"increment\", \"decrement\", or a custom action name)"
                ),
                .init(
                    key: "count", type: .integer, optionalRole: .behaviorSwitch,
                    description: "Repeat increment/decrement this many times. Omit for 1.",
                    minimum: 1,
                    maximum: 100
                ),
            ] + expectation

        case .increment, .decrement:
            return target + [
                .init(
                    key: "count", type: .integer, optionalRole: .behaviorSwitch,
                    description: "Repeat increment/decrement this many times. Omit for 1.",
                    minimum: 1,
                    maximum: 100
                ),
            ] + expectation

        case .performCustomAction:
            return target + [
                .init(key: "action", type: .string, required: true, description: "Custom accessibility action name"),
            ] + expectation

        case .rotor:
            return target + [
                .init(key: "rotor", type: .string, optionalRole: .payload, description: "Rotor name from the element's rotors list"),
                .init(
                    key: "rotorIndex", type: .integer, optionalRole: .payload,
                    description: "Zero-based rotor index when names are omitted or ambiguous",
                    minimum: 0
                ),
                .init(
                    key: "direction", type: .string, optionalRole: .payload,
                    description: "Rotor movement direction. Defaults to next.",
                    enumValues: fenceEnumValues(RotorDirection.self)
                ),
                .init(
                    key: "currentHeistId", type: .string, optionalRole: .payload,
                    description: "Optional current item heistId; pass the previous result to continue through a rotor"
                ),
                .init(
                    key: "currentTextStartOffset", type: .integer, optionalRole: .payload,
                    description: "Current text-range start offset for continuing through text-range rotor results",
                    minimum: 0
                ),
                .init(
                    key: "currentTextEndOffset", type: .integer, optionalRole: .payload,
                    description: "Current text-range end offset for continuing through text-range rotor results",
                    minimum: 0
                ),
            ] + expectation

        // MARK: Text / keyboard
        case .typeText:
            return target + [
                .init(key: "text", type: .string, required: true, description: "Text to type character-by-character", minLength: 1),
            ] + expectation

        case .editAction:
            return [
                .init(
                    key: "action", type: .string, required: true,
                    description: "Action to perform",
                    enumValues: fenceEnumValues(EditAction.self)
                ),
            ] + expectation

        // MARK: Pasteboard
        case .setPasteboard:
            return [
                .init(key: "text", type: .string, required: true, description: "Text to write to the pasteboard"),
            ] + expectation

        case .getPasteboard:
            return []

        // MARK: Wait
        case .waitFor:
            return target + [
                .init(key: "absent", type: .boolean, optionalRole: .behaviorSwitch, description: "Wait for element to NOT exist (default: false)"),
                .init(
                    key: "timeout", type: .number, optionalRole: .behaviorSwitch,
                    description: "Max seconds to wait (default: 10, max: 30)",
                    maximum: 30
                ),
                expect,
            ]

        // MARK: Recording
        case .startRecording:
            return [
                .init(key: "fps", type: .integer, optionalRole: .payload, description: "Frames per second (default: 8, range: 1-15)", minimum: 1, maximum: 15),
                .init(
                    key: "scale", type: .number, optionalRole: .payload,
                    description: "Resolution scale factor (default: 1.0, range: 0.25-1.0)",
                    minimum: 0.25,
                    maximum: 1.0
                ),
                .init(key: "max_duration", type: .number, optionalRole: .payload, description: "Maximum recording duration in seconds (default: 60)"),
                .init(
                    key: "inactivity_timeout", type: .number, optionalRole: .behaviorSwitch,
                    description: "Optional early-stop after N seconds of no interactions; omitted disables inactivity auto-stop"
                ),
            ]

        case .stopRecording:
            return [
                .init(key: "output", type: .string, optionalRole: .payload, description: "File path to save MP4 (omit for default artifact path)"),
                .init(
                    key: "inlineData", type: .boolean, optionalRole: .behaviorSwitch,
                    description: "Include base64 MP4 video data in the response (default false; capped before delivery)"
                ),
                .init(
                    key: "includeInteractionLog", type: .boolean, optionalRole: .behaviorSwitch,
                    description: "Include the full interaction log in the response (default false; capped before delivery)"
                ),
            ]

        // MARK: Batch
        case .runBatch:
            return [
                .init(
                    key: "steps", type: .array, required: true,
                    description: """
                    Ordered list of batch-executable canonical Fence command requests to execute \
                    (max 100 steps; max request size 1 MB; max nesting depth 32)
                    """,
                    minItems: 1,
                    maxItems: TheFence.DecodeLimits.maxRunBatchSteps,
                    arrayItemType: .object,
                    arrayItemProperties: [
                        .init(
                            key: "command", type: .string, required: true,
                            description: "Canonical TheFence.Command name (e.g. activate, swipe, element_search, dismiss_keyboard). " +
                                "Grouped MCP tool names and selector shapes are not accepted inside batches.",
                            enumValues: Self.batchExecutableCases.map(\.rawValue)
                        ),
                        expect,
                    ],
                    arrayItemAdditionalProperties: true
                ),
                .init(
                    key: "policy", type: .string, optionalRole: .behaviorSwitch,
                    description: "Batch policy: stop_on_error (default) or continue_on_error",
                    enumValues: fenceEnumValues(TheFence.BatchPolicy.self)
                ),
            ]

        // MARK: Connection
        case .connect:
            return [
                .init(key: "target", type: .string, optionalRole: .matcher, description: "Named target from .buttonheist.json config file"),
                .init(key: "device", type: .string, optionalRole: .matcher, description: "Direct host:port address (e.g. 127.0.0.1:1455)"),
                .init(key: "token", type: .string, optionalRole: .payload, description: "Auth token (overrides config file token if both provided)"),
            ]

        // MARK: Session management
        case .archiveSession:
            return [
                .init(
                    key: "delete_source", type: .boolean, optionalRole: .behaviorSwitch,
                    description: "Delete the session directory after archiving (default: false)"
                ),
            ]

        case .startHeist:
            return [
                .init(
                    key: "app", type: .string, optionalRole: .payload,
                    description: "Bundle ID of the app being recorded (default: \(Defaults.demoAppBundleID))"
                ),
                .init(
                    key: "identifier", type: .string, optionalRole: .payload,
                    description: "Session name for the recording (default: heist). Used as directory name if a new session is created."
                ),
            ]

        case .stopHeist:
            return [
                .init(key: "output", type: .string, required: true, description: "File path to write the .heist file"),
            ]

        case .playHeist:
            return [
                .init(key: "input", type: .string, required: true, description: "Path to the .heist file to play back"),
            ]
        }
    }
}

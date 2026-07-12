import ThePlans
import TheScore

@_spi(ButtonHeistTooling) public enum FenceParameters {
    public static let actionName = FenceParameter<String>.string(.action)
    public static let commandName = FenceParameter<String>.string(.command, required: true)
    public static let connectionTarget = FenceParameter<String>.string(.target)
    public static let device = FenceParameter<String>.string(.device)
    public static let editAction = FenceParameter<EditAction>.enumValue(.action, required: true)
    public static let elementProperty = FenceParameter<ElementProperty>.enumValue(.property)
    public static let heistCatalogDetail = FenceParameter<HeistCatalogDetail>.enumValue(
        .detail,
        defaultValue: .summary
    )
    public static let heistName = FenceParameter<String>.string(.heist, required: true)
    public static let inlineData = FenceParameter<Bool>.boolean(.inlineData)
    public static let inlinePlan = FenceParameter<String>.string(.plan)
    public static let interfaceDetail = FenceParameter<InterfaceDetail>.enumValue(.detail)
    public static let maxScrollsPerContainer = FenceParameter<Int>.integer(
        .maxScrollsPerContainer,
        minimum: 1,
        maximum: 2_000
    )
    public static let maxScrollsPerDiscovery = FenceParameter<Int>.integer(
        .maxScrollsPerDiscovery,
        minimum: 1,
        maximum: 2_000
    )
    public static let output = FenceParameter<String>.string(.output)
    public static let pasteboardText = FenceParameter<String>.string(.text, required: true, minLength: 1)
    public static let performStep = FenceParameter<String>.string(.step, required: true, minLength: 1)
    public static let planPath = FenceParameter<String>.string(.path)
    public static let replacingExisting = FenceParameter<Bool>.boolean(.replacingExisting, defaultValue: false)
    public static let screenMode = FenceParameter<ScreenCaptureMode>.enumValue(.mode, defaultValue: .raw)
    public static let rotorDirection = FenceParameter<RotorDirection>.enumValue(.direction, defaultValue: .next)
    public static let rotorIndex = FenceParameter<Int>.integer(.rotorIndex, minimum: 0)
    public static let rotorName = FenceParameter<String>.string(.rotor)
    public static let scrollDirection = FenceParameter<ScrollDirection>.enumValue(.direction, defaultValue: .down)
    public static let scrollEdge = FenceParameter<ScrollEdge>.enumValue(.edge, defaultValue: .top)
    public static let swipeDirection = FenceParameter<SwipeDirection>.enumValue(.direction, required: true)
    public static let text = FenceParameter<String>.string(.text, required: true)
    public static let timeout = FenceParameter<Double>.number(
        .timeout,
        maximum: defaultWaitTimeout,
        exclusiveMinimum: 0
    )
    public static let token = FenceParameter<String>.string(.token)
}

internal func param(
    _ key: FenceParameterKey,
    _ kind: FenceParameterScalarKind,
    required: Bool = false,
    enumValues: [String]? = nil,
    defaultValue: HeistValue? = nil,
    minimum: Double? = nil,
    maximum: Double? = nil,
    exclusiveMinimum: Double? = nil,
    minLength: Int? = nil
) -> FenceParameterSpec {
    let constraints = FenceParameterScalarConstraints(
        enumValues: enumValues,
        defaultValue: defaultValue,
        minimum: minimum,
        maximum: maximum,
        exclusiveMinimum: exclusiveMinimum,
        minLength: minLength
    )
    return FenceParameterSpec(
        key: key.rawValue,
        schema: .scalar(kind, constraints: constraints),
        required: required
    )
}

internal func objectParam(
    _ key: FenceParameterKey,
    required: Bool = false,
    validation: FenceParameterValidation = .schema
) -> FenceParameterSpec {
    FenceParameterSpec(
        key: key.rawValue,
        schema: .object(),
        required: required,
        validation: validation
    )
}

internal func objectParam(
    _ key: FenceParameterKey,
    required: Bool = false,
    properties: [FenceParameterSpec],
    additionalProperties: Bool = false,
    validation: FenceParameterValidation = .schema
) -> FenceParameterSpec {
    FenceParameterSpec(
        key: key.rawValue,
        schema: .object(properties: properties, additionalProperties: additionalProperties),
        required: required,
        validation: validation
    )
}

internal func arrayParam(
    _ key: FenceParameterKey,
    required: Bool = false,
    items: FenceParameterSchema? = nil,
    minItems: Int? = nil,
    maxItems: Int? = nil
) -> FenceParameterSpec {
    FenceParameterSpec(
        key: key.rawValue,
        schema: .array(
            items: items,
            constraints: FenceParameterArrayConstraints(minItems: minItems, maxItems: maxItems)
        ),
        required: required
    )
}

internal func stringArrayParam(
    _ key: FenceParameterKey,
    required: Bool = false,
    minItems: Int? = nil,
    maxItems: Int? = nil
) -> FenceParameterSpec {
    FenceParameterSpec(
        key: key.rawValue,
        schema: .array(
            kind: .stringArray,
            items: .scalar(.string),
            constraints: FenceParameterArrayConstraints(minItems: minItems, maxItems: maxItems)
        ),
        required: required
    )
}

internal func unconstrainedParam(
    _ key: FenceParameterKey,
    required: Bool = false,
    validation: FenceParameterValidation = .schema
) -> FenceParameterSpec {
    FenceParameterSpec(
        key: key.rawValue,
        schema: .unconstrained,
        required: required,
        validation: validation
    )
}

internal func stringMatchParam(
    _ key: FenceParameterKey,
    required: Bool = false,
    allowsArray: Bool = false
) -> FenceParameterSpec {
    let modeValues = StringMatch<String>.Mode.allCases.map(\.rawValue)
    let description = "StringMatch object with mode \(modeValues.joined(separator: "/")) and optional value. " +
        "Use mode exact for exact matching. Broad modes require a non-empty value; isEmpty must omit value." +
        (allowsArray
            ? " Element matcher fields also accept an array of StringMatch objects; every object must match."
            : "")
    return FenceParameterSpec(
        key: key.rawValue,
        schema: .scalar(.stringMatch(modeValues: modeValues, description: description)),
        required: required,
        validation: .customPayload
    )
}

internal func containerPredicateParam(_ key: FenceParameterKey) -> FenceParameterSpec {
    objectParam(
        key,
        properties: [
            arrayParam(
                .checks,
                required: true,
                items: .object(
                    properties: containerPredicateCheckProperties,
                    additionalProperties: false
                ),
                minItems: 1
            ),
        ],
        validation: .customPayload
    )
}

/// The schema model has no reference node, so expand to the public JSON input
/// depth. `PublicJSONInputLimits` remains the single adjustable boundary.
internal let accessibilityTargetSchemaMaximumNestingDepth = PublicJSONInputLimits.maxNestingDepth

internal func accessibilityTargetProperties(
    remainingNestingDepth: Int = accessibilityTargetSchemaMaximumNestingDepth
) -> [FenceParameterSpec] {
    precondition(remainingNestingDepth > 0)
    let terminalProperties = [
        predicateChecksParam(.checks),
        param(.ref, .string),
        param(.ordinal, .integer, minimum: 0),
        containerPredicateParam(.container),
    ]
    guard remainingNestingDepth > 1 else { return terminalProperties }
    return terminalProperties + [
        objectParam(
            .target,
            properties: accessibilityTargetProperties(remainingNestingDepth: remainingNestingDepth - 1),
            additionalProperties: false,
            validation: .customPayload
        ),
    ]
}

internal func predicateChecksParam(_ key: FenceParameterKey) -> FenceParameterSpec {
    arrayParam(
        key,
        items: .object(
            properties: [
                param(
                    .kind, .string, required: true,
                    enumValues: ElementPredicateCheck<String>.Kind.allCases.map(\.rawValue)
                ),
                stringMatchParam(.match),
                arrayParam(.values, items: .unconstrained),
                objectParam(.check),
            ],
            additionalProperties: false
        )
    )
}

private let semanticContainerPredicateProperties: [FenceParameterSpec] = [
    param(.kind, .string, required: true, enumValues: semanticContainerPredicateKindValues),
    stringMatchParam(.match, required: true),
]

private let semanticContainerPredicateKindValues: [String] = [
    SemanticContainerPredicate<String>.label("sample"),
    SemanticContainerPredicate<String>.value("sample"),
].map(\.wireKindValue)

private let containerPredicateCheckProperties: [FenceParameterSpec] = [
    param(
        .kind, .string, required: true,
        enumValues: ContainerPredicateCheck<String>.wireKindValues
    ),
    param(.type, .string, enumValues: AccessibilityContainerKind.allCases.map(\.rawValue)),
    stringMatchParam(.match),
    objectParam(
        .semantic,
        properties: semanticContainerPredicateProperties,
        validation: .customPayload
    ),
    arrayParam(.values, items: .unconstrained, minItems: 1),
    unconstrainedParam(.value, validation: .customPayload),
]

private extension SemanticContainerPredicate {
    var wireKindValue: String {
        switch self {
        case .label:
            "label"
        case .value:
            "value"
        case .identifier:
            "identifier"
        }
    }
}

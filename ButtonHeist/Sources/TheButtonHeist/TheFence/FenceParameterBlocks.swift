import ThePlans
import TheScore

internal enum FenceParameterBlocks: Sendable {
    private static let matcherFields = ElementTarget.predicateSchemaFields.map(elementTargetFieldSpec)
    internal static let inlineElementTargetFields = ElementTarget.inlineSchemaFields.map(elementTargetFieldSpec)

    internal static let elementTarget: [FenceParameterSpec] = [
        objectParam(.target, properties: inlineElementTargetFields, validation: .customPayload),
    ]
    internal static let gestureElement = objectParam(.element, properties: inlineElementTargetFields, validation: .customPayload)
    internal static let gestureUnitPoint = objectParam(.unitPoint, properties: unitPoint)
    internal static let gesturePoint = objectParam(.point, properties: screenPoint)

    internal static let gesturePointSelection: [FenceParameterSpec] = [
        gestureElement,
        gestureUnitPoint,
        gesturePoint,
    ]

    internal static let swipeElementDirection = objectParam(
        .elementDirection,
        properties: [
            gestureElement,
            FenceParameters.swipeDirection.spec,
        ]
    )

    internal static let swipeElementUnitPoints = objectParam(
        .elementUnitPoints,
        properties: [
            gestureElement,
            objectParam(.start, required: true, properties: unitPoint),
            objectParam(.end, required: true, properties: unitPoint),
        ]
    )

    internal static let swipePointToPoint = objectParam(
        .pointToPoint,
        properties: [
            objectParam(.start, required: true, properties: screenPoint),
            objectParam(.end, required: true, properties: screenPoint),
        ]
    )

    internal static let swipePointDirection = objectParam(
        .pointDirection,
        properties: [
            objectParam(.start, required: true, properties: screenPoint),
            FenceParameters.swipeDirection.spec,
        ]
    )

    internal static let swipeIntents = [
        swipeElementDirection,
        swipeElementUnitPoints,
        swipePointToPoint,
        swipePointDirection,
    ]

    internal static let dragElementToPoint = objectParam(
        .elementToPoint,
        properties: [
            gestureElement,
            objectParam(.start, properties: unitPoint),
            objectParam(.end, required: true, properties: screenPoint),
        ]
    )

    internal static let dragPointToPoint = objectParam(
        .pointToPoint,
        properties: [
            objectParam(.start, required: true, properties: screenPoint),
            objectParam(.end, required: true, properties: screenPoint),
        ]
    )

    internal static let dragIntents = [
        dragElementToPoint,
        dragPointToPoint,
    ]

    internal static let elementFilter = matcherFields

    private static let subtreeElementProperties = matcherFields

    private static let subtreeContainer = containerPredicateParam(.container)

    internal static let interfaceSubtree: FenceParameterSpec = objectParam(
        .subtree,
        properties: [
            objectParam(.element, properties: subtreeElementProperties, validation: .customPayload),
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
        objectParam(.element, properties: matcherFields, validation: .customPayload),
        objectParam(.target, properties: inlineElementTargetFields, validation: .customPayload),
        containerPredicateParam(.container),
        param(.targetRef, .string),
        arrayParam(.states, items: .object(properties: [], additionalProperties: true)),
    ]

    private static let assertionProperties: [FenceParameterSpec] = [
        param(.type, .string, enumValues: ["exists", "missing", "all", "appeared", "disappeared", "updated"]),
        objectParam(.element, properties: matcherFields, validation: .customPayload),
        objectParam(.target, properties: inlineElementTargetFields, validation: .customPayload),
        containerPredicateParam(.container),
        param(.targetRef, .string),
        FenceParameters.elementProperty.spec,
        objectParam(.before, properties: matcherFields, validation: .customPayload),
        objectParam(.after, properties: matcherFields, validation: .customPayload),
        arrayParam(.states, items: .object(properties: [], additionalProperties: true)),
    ]

    private static let changeScopeProperties: [FenceParameterSpec] = [
        param(.type, .string, enumValues: ["screen", "elements", "all"]),
        arrayParam(
            .assertions,
            items: .object(properties: assertionProperties, additionalProperties: true)
        ),
        arrayParam(
            .scopes,
            items: .object(properties: [], additionalProperties: true)
        ),
    ]

    /// Object properties for an `AccessibilityPredicate` (the `expect` slot and
    /// the `wait` `predicate` field). State predicates use `element`, `target`,
    /// `target_ref`, `container`, or `states`; change predicates use `scopes`,
    /// whose children carry `screen` state assertions or `elements` delta assertions.
    private static let accessibilityPredicateProperties: [FenceParameterSpec] = [
        predicateType,
        objectParam(.element, properties: matcherFields, validation: .customPayload),
        objectParam(.target, properties: inlineElementTargetFields, validation: .customPayload),
        containerPredicateParam(.container),
        param(.targetRef, .string),
        FenceParameters.elementProperty.spec,
        objectParam(.before, properties: matcherFields, validation: .customPayload),
        objectParam(.after, properties: matcherFields, validation: .customPayload),
        stringMatchParam(.match),
        arrayParam(
            .states,
            items: .object(properties: stateProperties, additionalProperties: true)
        ),
        arrayParam(
            .scopes,
            items: .object(properties: changeScopeProperties, additionalProperties: true)
        ),
    ]

    internal static let expect: FenceParameterSpec = objectParam(
        .expect,
        properties: accessibilityPredicateProperties,
        validation: .customPayload
    )

    internal static let predicate: FenceParameterSpec = objectParam(
        .predicate, required: true,
        properties: accessibilityPredicateProperties,
        validation: .customPayload
    )

    internal static let expectationTimeout = FenceParameters.timeout.spec
    internal static let expectation: [FenceParameterSpec] = [expect, expectationTimeout]

    /// Parameters for the unified `wait` command: a predicate plus a timeout.
    internal static let wait: [FenceParameterSpec] = [predicate, expectationTimeout]

    internal static let unitPoint: [FenceParameterSpec] = [
        param(.x, .number, required: true), param(.y, .number, required: true),
    ]
    internal static let screenPoint: [FenceParameterSpec] = unitPoint
    internal static let gestureDuration = param(
        .duration, .number,
        maximum: GestureDuration.maximumSeconds,
        exclusiveMinimum: 0
    )
}

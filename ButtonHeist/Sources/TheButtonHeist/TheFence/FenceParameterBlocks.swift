import ThePlans
import TheScore

internal enum FenceParameterBlocks: Sendable {
    private static let matcherFields = [predicateChecksParam(.checks)]
    internal static let inlineAccessibilityTargetFields = accessibilityTargetProperties()

    internal static let target: [FenceParameterSpec] = [
        objectParam(.target, properties: inlineAccessibilityTargetFields, validation: .customPayload),
    ]
    internal static let gestureElement = objectParam(.element, properties: inlineAccessibilityTargetFields, validation: .customPayload)
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

    internal static let interfaceSubtree: FenceParameterSpec = objectParam(
        .subtree,
        properties: inlineAccessibilityTargetFields,
        validation: .customPayload
    )

    private static let assertionProperties: [FenceParameterSpec] = [
        param(.type, .string, required: true, enumValues: PredicateAssertionType.allCases.map(\.rawValue)),
        objectParam(.target, properties: inlineAccessibilityTargetFields, validation: .customPayload),
        FenceParameters.elementProperty.spec,
        unconstrainedParam(.before, validation: .customPayload),
        unconstrainedParam(.after, validation: .customPayload),
    ]

    /// Canonical root predicate shape shared by `expect` and `wait.predicate`.
    private static let accessibilityPredicateProperties: [FenceParameterSpec] = [
        param(
            .type,
            .string,
            required: true,
            enumValues: AccessibilityPredicate.wireTypeValues
        ),
        objectParam(.target, properties: inlineAccessibilityTargetFields, validation: .customPayload),
        stringMatchParam(.match),
        param(.scope, .string, enumValues: ChangedScope.allCases.map(\.rawValue)),
        arrayParam(
            .assertions,
            items: .object(properties: assertionProperties, additionalProperties: false)
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
        FenceParameters.unitPointX.spec,
        FenceParameters.unitPointY.spec,
    ]
    internal static let screenPoint: [FenceParameterSpec] = [
        FenceParameters.screenPointX.spec,
        FenceParameters.screenPointY.spec,
    ]
    internal static let gestureDuration = FenceParameters.gestureDuration.spec

}

private enum ChangedScope: String, CaseIterable {
    case screen
    case elements
}

private enum PredicateAssertionType: String, CaseIterable {
    case exists
    case missing
    case appeared
    case disappeared
    case updated
}

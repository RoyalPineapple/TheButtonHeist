import Foundation

/// Semantic element target used by action execution plans.
///
/// `sourceHeistId` is diagnostic source metadata from the capture that produced
/// the matcher. It is never the executable identity. Execution should resolve
/// `matcher` and `ordinal` against fresh live geometry.
public struct SemanticActionTarget: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case sourceHeistId, matcher, ordinal
    }

    public let sourceHeistId: HeistId?
    public let matcher: ElementMatcher
    public let ordinal: Int?

    public init(
        sourceHeistId: HeistId? = nil,
        matcher: ElementMatcher,
        ordinal: Int? = nil
    ) {
        self.sourceHeistId = sourceHeistId
        self.matcher = ElementMatcher(
            label: matcher.label,
            identifier: matcher.identifier,
            value: matcher.value,
            traits: matcher.traits,
            excludeTraits: matcher.excludeTraits
        )
        self.ordinal = ordinal
    }

    public init(_ minimumMatcher: MinimumMatcher) {
        self.init(
            sourceHeistId: minimumMatcher.element.heistId,
            matcher: minimumMatcher.matcher,
            ordinal: minimumMatcher.ordinal
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceHeistId = try container.decodeIfPresent(HeistId.self, forKey: .sourceHeistId)
        let matcher = try container.decode(ElementMatcher.self, forKey: .matcher)
        let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        if matcher.heistId != nil {
            throw DecodingError.dataCorruptedError(
                forKey: .matcher,
                in: container,
                debugDescription: "SemanticActionTarget matcher must not carry heistId; use top-level sourceHeistId for metadata"
            )
        }
        if let ordinal, ordinal < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .ordinal,
                in: container,
                debugDescription: "ordinal must be non-negative, got \(ordinal)"
            )
        }
        self.init(sourceHeistId: sourceHeistId, matcher: matcher, ordinal: ordinal)
        guard self.matcher.hasPredicates || ordinal != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .matcher,
                in: container,
                debugDescription: "SemanticActionTarget requires matcher predicates or an ordinal selector; sourceHeistId is metadata only"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        guard matcher.hasPredicates || ordinal != nil else {
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "SemanticActionTarget requires matcher predicates or an ordinal selector; sourceHeistId is metadata only"
            ))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(sourceHeistId, forKey: .sourceHeistId)
        try container.encode(matcher, forKey: .matcher)
        try container.encodeIfPresent(ordinal, forKey: .ordinal)
    }
}

extension SemanticActionTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("semanticTarget", [
            ScoreDescription.stringField("sourceHeistId", sourceHeistId),
            matcher.description,
            ScoreDescription.valueField("ordinal", ordinal),
        ].compactMap { $0 })
    }
}

public struct BatchCustomActionTarget: Codable, Sendable {
    public let target: SemanticActionTarget?
    public let containerTarget: ContainerMatcher?
    public let containerOrdinal: Int?
    public let actionName: String

    public init(target: SemanticActionTarget, actionName: String) {
        self.target = target
        self.containerTarget = nil
        self.containerOrdinal = nil
        self.actionName = actionName
    }

    public init(containerTarget: ContainerMatcher, ordinal: Int? = nil, actionName: String) {
        self.target = nil
        self.containerTarget = containerTarget
        self.containerOrdinal = ordinal
        self.actionName = actionName
    }
}

extension BatchCustomActionTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("customAction", [
            target?.description,
            containerTarget.map {
                ScoreDescription.call("container", [
                    $0.description,
                    ScoreDescription.valueField("ordinal", containerOrdinal),
                ].compactMap { $0 })
            },
            ScoreDescription.stringField("action", actionName),
        ].compactMap { $0 })
    }
}

extension BatchCustomActionTarget {
    private enum CodingKeys: String, CodingKey {
        case target
        case container
        case ordinal
        case actionName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actionName = try container.decode(String.self, forKey: .actionName)
        let hasElementTarget = container.contains(.target)
        let hasContainerTarget = container.contains(.container)
        guard hasElementTarget != hasContainerTarget else {
            throw DecodingError.dataCorruptedError(
                forKey: .target,
                in: container,
                debugDescription: "BatchCustomActionTarget requires exactly one of target or container"
            )
        }
        if hasElementTarget {
            target = try container.decode(SemanticActionTarget.self, forKey: .target)
            containerTarget = nil
            containerOrdinal = nil
        } else {
            target = nil
            let matcher = try container.decode(ContainerMatcher.self, forKey: .container)
            let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
            guard matcher.hasPredicates || ordinal != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .container,
                    in: container,
                    debugDescription: "BatchCustomActionTarget container requires stableId, type, label, value, identifier, isModalBoundary, or ordinal"
                )
            }
            containerTarget = matcher
            if let ordinal, ordinal < 0 {
                throw DecodingError.dataCorruptedError(
                    forKey: .ordinal,
                    in: container,
                    debugDescription: "ordinal must be non-negative, got \(ordinal)"
                )
            }
            containerOrdinal = ordinal
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionName, forKey: .actionName)
        switch (target, containerTarget) {
        case (let target?, nil):
            try container.encode(target, forKey: .target)
        case (nil, let containerTarget?):
            try container.encode(containerTarget, forKey: .container)
            try container.encodeIfPresent(containerOrdinal, forKey: .ordinal)
        default:
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "BatchCustomActionTarget requires exactly one of target or container"
            ))
        }
    }
}

public struct BatchRotorTarget: Codable, Sendable {
    public let target: SemanticActionTarget
    public let rotor: String?
    public let rotorIndex: Int?
    public let direction: RotorDirection?
    public let currentSourceHeistId: HeistId?
    public let currentTextRange: TextRangeReference?

    public init(
        target: SemanticActionTarget,
        rotor: String? = nil,
        rotorIndex: Int? = nil,
        direction: RotorDirection? = nil,
        currentSourceHeistId: HeistId? = nil,
        currentTextRange: TextRangeReference? = nil
    ) {
        self.target = target
        self.rotor = rotor
        self.rotorIndex = rotorIndex
        self.direction = direction
        self.currentSourceHeistId = currentSourceHeistId
        self.currentTextRange = currentTextRange
    }
}

extension BatchRotorTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("rotor", [
            target.description,
            ScoreDescription.stringField("name", rotor),
            ScoreDescription.valueField("index", rotorIndex),
            ScoreDescription.valueField("direction", direction),
            ScoreDescription.stringField("currentSourceHeistId", currentSourceHeistId),
            currentTextRange?.description,
        ].compactMap { $0 })
    }
}

public struct BatchTouchTapTarget: Codable, Sendable {
    public let target: SemanticActionTarget?
    public let pointX: Double?
    public let pointY: Double?

    public init(target: SemanticActionTarget? = nil, pointX: Double? = nil, pointY: Double? = nil) {
        self.target = target
        self.pointX = pointX
        self.pointY = pointY
    }
}

extension BatchTouchTapTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("tap", [
            target?.description,
            pointX.map { "x=\(ScoreDescription.decimal($0))" },
            pointY.map { "y=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct BatchLongPressTarget: Codable, Sendable {
    public let target: SemanticActionTarget?
    public let pointX: Double?
    public let pointY: Double?
    public let duration: Double

    public init(
        target: SemanticActionTarget? = nil,
        pointX: Double? = nil,
        pointY: Double? = nil,
        duration: Double = 0.5
    ) {
        self.target = target
        self.pointX = pointX
        self.pointY = pointY
        self.duration = duration
    }
}

extension BatchLongPressTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("longPress", [
            target?.description,
            pointX.map { "x=\(ScoreDescription.decimal($0))" },
            pointY.map { "y=\(ScoreDescription.decimal($0))" },
            "duration=\(ScoreDescription.decimal(duration))",
        ].compactMap { $0 })
    }
}

public struct BatchSwipeTarget: Codable, Sendable {
    public static let defaultDuration = SwipeTarget.defaultDuration

    public let target: SemanticActionTarget?
    public let startX: Double?
    public let startY: Double?
    public let endX: Double?
    public let endY: Double?
    public let direction: SwipeDirection?
    public let duration: Double?
    public let start: UnitPoint?
    public let end: UnitPoint?

    public init(
        target: SemanticActionTarget? = nil,
        startX: Double? = nil,
        startY: Double? = nil,
        endX: Double? = nil,
        endY: Double? = nil,
        direction: SwipeDirection? = nil,
        duration: Double? = nil,
        start: UnitPoint? = nil,
        end: UnitPoint? = nil
    ) {
        self.target = target
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.direction = direction
        self.duration = duration
        self.start = start
        self.end = end
    }

    public var resolvedDuration: Double { duration ?? Self.defaultDuration }
}

extension BatchSwipeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("swipe", [
            target?.description,
            startX.map { "startX=\(ScoreDescription.decimal($0))" },
            startY.map { "startY=\(ScoreDescription.decimal($0))" },
            endX.map { "endX=\(ScoreDescription.decimal($0))" },
            endY.map { "endY=\(ScoreDescription.decimal($0))" },
            ScoreDescription.valueField("direction", direction),
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
            start.map { "start=\($0)" },
            end.map { "end=\($0)" },
        ].compactMap { $0 })
    }
}

public struct BatchDragTarget: Codable, Sendable {
    public static let defaultDuration = DragTarget.defaultDuration

    public let target: SemanticActionTarget?
    public let startX: Double?
    public let startY: Double?
    public let endX: Double
    public let endY: Double
    public let duration: Double?

    public init(
        target: SemanticActionTarget? = nil,
        startX: Double? = nil,
        startY: Double? = nil,
        endX: Double,
        endY: Double,
        duration: Double? = nil
    ) {
        self.target = target
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.duration = duration
    }

    public var resolvedDuration: Double { duration ?? Self.defaultDuration }
}

extension BatchDragTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("drag", [
            target?.description,
            startX.map { "startX=\(ScoreDescription.decimal($0))" },
            startY.map { "startY=\(ScoreDescription.decimal($0))" },
            "endX=\(ScoreDescription.decimal(endX))",
            "endY=\(ScoreDescription.decimal(endY))",
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct BatchPinchTarget: Codable, Sendable {
    public static let defaultSpread = PinchTarget.defaultSpread
    public static let defaultDuration = PinchTarget.defaultDuration

    public let target: SemanticActionTarget?
    public let centerX: Double?
    public let centerY: Double?
    public let scale: Double
    public let spread: Double?
    public let duration: Double?

    public init(
        target: SemanticActionTarget? = nil,
        centerX: Double? = nil,
        centerY: Double? = nil,
        scale: Double,
        spread: Double? = nil,
        duration: Double? = nil
    ) {
        self.target = target
        self.centerX = centerX
        self.centerY = centerY
        self.scale = scale
        self.spread = spread
        self.duration = duration
    }

    public var resolvedSpread: Double { spread ?? Self.defaultSpread }
    public var resolvedDuration: Double { duration ?? Self.defaultDuration }
}

extension BatchPinchTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("pinch", [
            target?.description,
            centerX.map { "centerX=\(ScoreDescription.decimal($0))" },
            centerY.map { "centerY=\(ScoreDescription.decimal($0))" },
            "scale=\(ScoreDescription.decimal(scale))",
            spread.map { "spread=\(ScoreDescription.decimal($0))" },
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct BatchRotateTarget: Codable, Sendable {
    public static let defaultRadius = RotateTarget.defaultRadius
    public static let defaultDuration = RotateTarget.defaultDuration

    public let target: SemanticActionTarget?
    public let centerX: Double?
    public let centerY: Double?
    public let angle: Double
    public let radius: Double?
    public let duration: Double?

    public init(
        target: SemanticActionTarget? = nil,
        centerX: Double? = nil,
        centerY: Double? = nil,
        angle: Double,
        radius: Double? = nil,
        duration: Double? = nil
    ) {
        self.target = target
        self.centerX = centerX
        self.centerY = centerY
        self.angle = angle
        self.radius = radius
        self.duration = duration
    }

    public var resolvedRadius: Double { radius ?? Self.defaultRadius }
    public var resolvedDuration: Double { duration ?? Self.defaultDuration }
}

extension BatchRotateTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("rotate", [
            target?.description,
            centerX.map { "centerX=\(ScoreDescription.decimal($0))" },
            centerY.map { "centerY=\(ScoreDescription.decimal($0))" },
            "angle=\(ScoreDescription.decimal(angle))",
            radius.map { "radius=\(ScoreDescription.decimal($0))" },
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct BatchTwoFingerTapTarget: Codable, Sendable {
    public static let defaultSpread = TwoFingerTapTarget.defaultSpread

    public let target: SemanticActionTarget?
    public let centerX: Double?
    public let centerY: Double?
    public let spread: Double?

    public init(
        target: SemanticActionTarget? = nil,
        centerX: Double? = nil,
        centerY: Double? = nil,
        spread: Double? = nil
    ) {
        self.target = target
        self.centerX = centerX
        self.centerY = centerY
        self.spread = spread
    }

    public var resolvedSpread: Double { spread ?? Self.defaultSpread }
}

extension BatchTwoFingerTapTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("twoFingerTap", [
            target?.description,
            centerX.map { "centerX=\(ScoreDescription.decimal($0))" },
            centerY.map { "centerY=\(ScoreDescription.decimal($0))" },
            spread.map { "spread=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct BatchTypeTextTarget: Codable, Sendable {
    public let text: String
    public let target: SemanticActionTarget?

    public init(text: String, target: SemanticActionTarget? = nil) {
        self.text = text
        self.target = target
    }
}

extension BatchTypeTextTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("typeText", [
            ScoreDescription.stringField("text", text),
            target?.description,
        ].compactMap { $0 })
    }
}

public struct BatchScrollTarget: Codable, Sendable {
    public let target: SemanticActionTarget?
    public let direction: ScrollDirection

    public init(target: SemanticActionTarget? = nil, direction: ScrollDirection) {
        self.target = target
        self.direction = direction
    }
}

extension BatchScrollTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scroll", [
            target?.description,
            ScoreDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

public struct BatchScrollToVisibleTarget: Codable, Sendable {
    public let target: SemanticActionTarget?

    public init(target: SemanticActionTarget? = nil) {
        self.target = target
    }
}

extension BatchScrollToVisibleTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scrollToVisible", [
            target?.description,
        ].compactMap { $0 })
    }
}

public struct BatchElementSearchTarget: Codable, Sendable {
    public let target: SemanticActionTarget?
    public let direction: ScrollSearchDirection?

    public init(target: SemanticActionTarget? = nil, direction: ScrollSearchDirection? = nil) {
        self.target = target
        self.direction = direction
    }
}

extension BatchElementSearchTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("elementSearch", [
            target?.description,
            ScoreDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

public struct BatchScrollToEdgeTarget: Codable, Sendable {
    public let target: SemanticActionTarget?
    public let edge: ScrollEdge

    public init(target: SemanticActionTarget? = nil, edge: ScrollEdge) {
        self.target = target
        self.edge = edge
    }
}

extension BatchScrollToEdgeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scrollToEdge", [
            target?.description,
            ScoreDescription.valueField("edge", edge),
        ].compactMap { $0 })
    }
}

public struct BatchWaitForTarget: Codable, Sendable {
    public let target: SemanticActionTarget
    public let absent: Bool?
    public let timeout: Double?

    public init(target: SemanticActionTarget, absent: Bool? = nil, timeout: Double? = nil) {
        self.target = target
        self.absent = absent
        self.timeout = timeout
    }

    public var resolvedAbsent: Bool { absent ?? false }
    public var resolvedTimeout: Double { min(timeout ?? 10, 30) }
}

extension BatchWaitForTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("waitFor", [
            target.description,
            ScoreDescription.valueField("absent", absent),
            timeout.map { "timeout=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

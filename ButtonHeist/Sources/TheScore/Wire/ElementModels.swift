import ThePlans
import Foundation
import AccessibilitySnapshotModel

// MARK: - Element Action Set

/// Set-shaped element actions with deterministic boundary projection.
public struct ElementActionSet: Codable, Equatable, Hashable, Sendable, ExpressibleByArrayLiteral {
    public let actions: Set<ElementAction>

    public init<S: Sequence>(_ actions: S) where S.Element == ElementAction {
        self.actions = Set(actions)
    }

    public init(arrayLiteral elements: ElementAction...) {
        self.init(elements)
    }

    public var orderedActions: [ElementAction] {
        actions.sorted { lhs, rhs in
            lhs.canonicalSortKey < rhs.canonicalSortKey
        }
    }

    public var displayText: String {
        orderedActions.map(\.description).joined(separator: ", ")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([ElementAction].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(orderedActions)
    }
}

extension Sequence where Element == ElementAction {
    var elementActionSet: ElementActionSet {
        ElementActionSet(self)
    }

    var canonicalElementActionArray: [ElementAction] {
        elementActionSet.orderedActions
    }
}

private extension ElementAction {
    var canonicalSortKey: String {
    switch self {
    case .activate:
        return "0:activate"
    case .typeText:
        return "1:typeText"
    case .increment:
        return "2:increment"
    case .decrement:
        return "3:decrement"
    case .custom(let name):
        return "4:\(name)"
    }
}
}

// MARK: - Heist Element

/// A UI element captured from the accessibility hierarchy.
/// Wraps the parser's AccessibilityElement with all its rich data in a wire-friendly form.
public struct HeistElement: Codable, Equatable, Hashable, Sendable {
    public let description: String
    public let label: String?
    public let value: String?
    public let identifier: String?
    /// Read by VoiceOver after the label/value.
    public let hint: String?
    public let traits: [HeistTrait]
    public let frameEvidence: ScreenFrameEvidence
    public var frameX: Double? { frameEvidence.rect?.x.value }
    public var frameY: Double? { frameEvidence.rect?.y.value }
    public var frameWidth: Double? { frameEvidence.rect?.width.value }
    public var frameHeight: Double? { frameEvidence.rect?.height.value }
    /// Where VoiceOver would tap, in screen coordinates. May fall outside `frame`.
    public let activationPointEvidence: ActivationPointEvidence
    public var activationPointX: Double? {
        activationPointEvidence.point?.x ?? frameEvidence.rect?.midX
    }
    public var activationPointY: Double? {
        activationPointEvidence.point?.y ?? frameEvidence.rect?.midY
    }
    public let respondsToUserInteraction: Bool
    public let customContent: [HeistCustomContent]?
    public let rotors: [HeistRotor]?
    public let actions: [ElementAction]

    public init(
        description: String,
        label: String?,
        value: String?,
        identifier: String?,
        hint: String? = nil,
        traits: [HeistTrait] = [],
        frameEvidence: ScreenFrameEvidence,
        activationPointEvidence: ActivationPointEvidence = .unavailable,
        respondsToUserInteraction: Bool = true,
        customContent: [HeistCustomContent]? = nil,
        rotors: [HeistRotor]? = nil,
        actions: [ElementAction]
    ) {
        self.description = description
        self.label = label
        self.value = value
        self.identifier = identifier
        self.hint = hint
        self.traits = traits
        self.frameEvidence = frameEvidence
        self.activationPointEvidence = activationPointEvidence
        self.respondsToUserInteraction = respondsToUserInteraction
        self.customContent = customContent
        self.rotors = rotors
        self.actions = actions.canonicalElementActionArray
    }

    public init(
        description: String,
        label: String?,
        value: String?,
        identifier: String?,
        hint: String? = nil,
        traits: [HeistTrait] = [],
        frameX: FiniteCoordinate,
        frameY: FiniteCoordinate,
        frameWidth: FiniteDimension,
        frameHeight: FiniteDimension,
        activationPointEvidence: ActivationPointEvidence = .unavailable,
        respondsToUserInteraction: Bool = true,
        customContent: [HeistCustomContent]? = nil,
        rotors: [HeistRotor]? = nil,
        actions: [ElementAction]
    ) {
        self.init(
            description: description,
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            frameEvidence: .available(ScreenRect(
                x: frameX,
                y: frameY,
                width: frameWidth,
                height: frameHeight
            )),
            activationPointEvidence: activationPointEvidence,
            respondsToUserInteraction: respondsToUserInteraction,
            customContent: customContent,
            rotors: rotors,
            actions: actions
        )
    }
}

public extension HeistElement {
    var screenFrame: ScreenRect? { frameEvidence.rect }
}

// MARK: - HeistElement Codable

extension HeistElement {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case description
        case label, value, identifier, hint
        case traits
        case frameX, frameY, frameWidth, frameHeight
        case activationPointEvidence
        case respondsToUserInteraction
        case customContent, rotors, actions
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "HeistElement")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let description = try container.decode(String.self, forKey: .description)
        let label = try container.decodeIfPresent(String.self, forKey: .label)
        let value = try container.decodeIfPresent(String.self, forKey: .value)
        let identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        let hint = try container.decodeIfPresent(String.self, forKey: .hint)
        let traits = try container.decode([HeistTrait].self, forKey: .traits)
        let frameEvidence = try Self.decodeFrameEvidence(from: container)
        self.init(
            description: description,
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            frameEvidence: frameEvidence,
            activationPointEvidence: try container.decode(
                ActivationPointEvidence.self,
                forKey: .activationPointEvidence
            ),
            respondsToUserInteraction: try container.decode(Bool.self, forKey: .respondsToUserInteraction),
            customContent: try container.decodeIfPresent([HeistCustomContent].self, forKey: .customContent),
            rotors: try container.decodeIfPresent([HeistRotor].self, forKey: .rotors),
            actions: try container.decode(ElementActionSet.self, forKey: .actions).orderedActions
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(identifier, forKey: .identifier)
        try container.encodeIfPresent(hint, forKey: .hint)
        try container.encode(traits, forKey: .traits)
        if let frame = frameEvidence.rect {
            try container.encode(frame.x, forKey: .frameX)
            try container.encode(frame.y, forKey: .frameY)
            try container.encode(frame.width, forKey: .frameWidth)
            try container.encode(frame.height, forKey: .frameHeight)
        }
        try container.encode(activationPointEvidence, forKey: .activationPointEvidence)
        try container.encode(respondsToUserInteraction, forKey: .respondsToUserInteraction)
        try container.encodeIfPresent(customContent, forKey: .customContent)
        try container.encodeIfPresent(rotors, forKey: .rotors)
        try container.encode(ElementActionSet(actions), forKey: .actions)
    }

    private static func decodeFrameEvidence(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ScreenFrameEvidence {
        let frameKeys: [CodingKeys] = [.frameX, .frameY, .frameWidth, .frameHeight]
        let suppliedFrameKeys = frameKeys.filter(container.contains)
        guard !suppliedFrameKeys.isEmpty else { return .unavailable }
        guard suppliedFrameKeys.count == frameKeys.count else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "HeistElement frame geometry must be fully available or fully unavailable"
            ))
        }
        return .available(ScreenRect(
            x: try container.decode(FiniteCoordinate.self, forKey: .frameX),
            y: try container.decode(FiniteCoordinate.self, forKey: .frameY),
            width: try container.decode(FiniteDimension.self, forKey: .frameWidth),
            height: try container.decode(FiniteDimension.self, forKey: .frameHeight)
        ))
    }
}

public extension HeistElement {
    init(
        accessibilityElement element: AccessibilityElement,
        actions: [ElementAction] = []
    ) {
        let frameEvidence = ScreenFrameEvidence(element.shape)
        let activationPoint = accessibilityActivationPointEvidence(
            for: element,
            frameEvidence: frameEvidence
        )
        let validCustomContent = element.customContent.compactMap { HeistCustomContent(projecting: $0) }
        let validRotors = element.customRotors.filter { !$0.name.isEmpty }
        self.init(
            description: element.description,
            label: element.label,
            value: element.value,
            identifier: element.identifier,
            hint: element.hint,
            traits: element.traits.heistTraits,
            frameEvidence: frameEvidence,
            activationPointEvidence: activationPoint,
            respondsToUserInteraction: element.respondsToUserInteraction,
            customContent: validCustomContent.isEmpty ? nil : validCustomContent,
            rotors: validRotors.isEmpty ? nil : validRotors.map { HeistRotor(name: $0.name) },
            actions: actions
        )
    }
}

private func accessibilityActivationPointEvidence(
    for element: AccessibilityElement,
    frameEvidence: ScreenFrameEvidence
) -> ActivationPointEvidence {
    if element.usesDefaultActivationPoint {
        guard let frame = frameEvidence.rect,
              let x = try? FiniteCoordinate(validating: frame.midX),
              let y = try? FiniteCoordinate(validating: frame.midY)
        else { return .unavailable }
        return .defaultCenter(ScreenPoint(x: x, y: y))
    }
    guard let x = try? FiniteCoordinate(validating: element.activationPoint.x),
          let y = try? FiniteCoordinate(validating: element.activationPoint.y)
    else { return .unavailable }
    let screenPoint = ScreenPoint(x: x, y: y)
    return .explicit(screenPoint)
}

/// Rotor metadata attached to a HeistElement.
///
/// This intentionally describes availability only. Rotor results are discovered
/// live through a command because rotor movement is contextual and can be
/// direction-dependent or unbounded.
public struct HeistRotor: Codable, Equatable, Hashable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

/// Custom content attached to a HeistElement (maps to AccessibilityElement.CustomContent)
public struct HeistCustomContent: Codable, Equatable, Hashable, Sendable {
    public let label: String
    public let value: String
    public let isImportant: Bool

    public init(label: String, value: String, isImportant: Bool) {
        self.label = label
        self.value = value
        self.isImportant = isImportant
    }

    package init?(projecting content: AccessibilityElement.CustomContent) {
        guard !content.label.isEmpty || !content.value.isEmpty else { return nil }
        self.init(label: content.label, value: content.value, isImportant: content.isImportant)
    }
}

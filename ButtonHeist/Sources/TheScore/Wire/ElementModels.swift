import ThePlans
import Foundation
import CoreGraphics
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
        case .increment:
            return "1:increment"
        case .decrement:
            return "2:decrement"
        case .custom(let name):
            return "3:\(name)"
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
    public let frameX: Double
    public let frameY: Double
    public let frameWidth: Double
    public let frameHeight: Double
    /// Where VoiceOver would tap, in screen coordinates. May fall outside `frame`.
    public let activationPointX: Double
    public let activationPointY: Double
    public let activationPointEvidence: ActivationPointEvidence
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
        frameX: Double,
        frameY: Double,
        frameWidth: Double,
        frameHeight: Double,
        activationPointX: Double? = nil,
        activationPointY: Double? = nil,
        activationPointEvidence: ActivationPointEvidence? = nil,
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
        self.frameX = frameX
        self.frameY = frameY
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        precondition((activationPointX == nil) == (activationPointY == nil), "activationPointX and activationPointY must be provided together")
        let fallbackPoint = ScreenPoint(
            x: sanitizedDouble(activationPointX ?? frameX + (frameWidth / 2)),
            y: sanitizedDouble(activationPointY ?? frameY + (frameHeight / 2))
        )
        let resolvedEvidence: ActivationPointEvidence
        if let activationPointEvidence {
            resolvedEvidence = activationPointEvidence
        } else if let activationPointX, let activationPointY {
            resolvedEvidence = activationPointX.isFinite && activationPointY.isFinite
                ? .explicit(ScreenPoint(x: activationPointX, y: activationPointY))
                : .unavailable
        } else {
            resolvedEvidence = .defaultCenter(fallbackPoint)
        }
        self.activationPointEvidence = resolvedEvidence
        self.activationPointX = resolvedEvidence.point?.x ?? fallbackPoint.x
        self.activationPointY = resolvedEvidence.point?.y ?? fallbackPoint.y
        self.respondsToUserInteraction = respondsToUserInteraction
        self.customContent = customContent
        self.rotors = rotors
        self.actions = actions.canonicalElementActionArray
    }

}

public extension HeistElement {
    var screenFrame: ScreenRect {
        ScreenRect(
            x: frameX,
            y: frameY,
            width: frameWidth,
            height: frameHeight
        )
    }
}

// MARK: - HeistElement Codable

extension HeistElement {
    private enum CodingKeys: String, CodingKey {
        case description
        case label, value, identifier, hint
        case traits
        case frameX, frameY, frameWidth, frameHeight
        case activationPointX, activationPointY
        case activationPointEvidence
        case respondsToUserInteraction
        case customContent, rotors, actions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let description = try container.decode(String.self, forKey: .description)
        let label = try container.decodeIfPresent(String.self, forKey: .label)
        let value = try container.decodeIfPresent(String.self, forKey: .value)
        let identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        let hint = try container.decodeIfPresent(String.self, forKey: .hint)
        let traits = try container.decode([HeistTrait].self, forKey: .traits)
        let frameX = try container.decode(Double.self, forKey: .frameX)
        let frameY = try container.decode(Double.self, forKey: .frameY)
        let frameWidth = try container.decode(Double.self, forKey: .frameWidth)
        let frameHeight = try container.decode(Double.self, forKey: .frameHeight)
        let activationPointX = try container.decode(Double.self, forKey: .activationPointX)
        let activationPointY = try container.decode(Double.self, forKey: .activationPointY)
        let activationPointEvidence = try container.decodeIfPresent(
            ActivationPointEvidence.self,
            forKey: .activationPointEvidence
        ) ?? .explicit(ScreenPoint(
            x: sanitizedDouble(activationPointX),
            y: sanitizedDouble(activationPointY)
        ))
        self.init(
            description: description,
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            activationPointX: activationPointX,
            activationPointY: activationPointY,
            activationPointEvidence: activationPointEvidence,
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
        try container.encode(frameX, forKey: .frameX)
        try container.encode(frameY, forKey: .frameY)
        try container.encode(frameWidth, forKey: .frameWidth)
        try container.encode(frameHeight, forKey: .frameHeight)
        try container.encode(activationPointX, forKey: .activationPointX)
        try container.encode(activationPointY, forKey: .activationPointY)
        try container.encode(activationPointEvidence, forKey: .activationPointEvidence)
        try container.encode(respondsToUserInteraction, forKey: .respondsToUserInteraction)
        try container.encodeIfPresent(customContent, forKey: .customContent)
        try container.encodeIfPresent(rotors, forKey: .rotors)
        try container.encode(ElementActionSet(actions), forKey: .actions)
    }
}

public extension HeistElement {
    init(
        accessibilityElement element: AccessibilityElement,
        annotation: InterfaceElementAnnotation? = nil
    ) {
        let frame = accessibilityFrame(for: element.shape)
        let activationPoint = accessibilityActivationPointEvidence(
            for: element,
            sourceFrame: frame,
            projectedFrame: frame
        )
        let validCustomContent = element.customContent.filter { !$0.label.isEmpty || !$0.value.isEmpty }
        let validRotors = element.customRotors.filter { !$0.name.isEmpty }
        self.init(
            description: element.description,
            label: element.label,
            value: element.value,
            identifier: element.identifier,
            hint: element.hint,
            traits: element.traits.heistTraits,
            frameX: sanitizedDouble(frame.origin.x),
            frameY: sanitizedDouble(frame.origin.y),
            frameWidth: sanitizedDouble(frame.size.width),
            frameHeight: sanitizedDouble(frame.size.height),
            activationPointX: activationPoint.point?.x,
            activationPointY: activationPoint.point?.y,
            activationPointEvidence: activationPoint,
            respondsToUserInteraction: element.respondsToUserInteraction,
            customContent: validCustomContent.isEmpty ? nil : validCustomContent.map {
                HeistCustomContent(label: $0.label, value: $0.value, isImportant: $0.isImportant)
            },
            rotors: validRotors.isEmpty ? nil : validRotors.map { HeistRotor(name: $0.name) },
            actions: annotation?.actions ?? []
        )
    }
}

private func accessibilityActivationPointEvidence(
    for element: AccessibilityElement,
    sourceFrame: CGRect,
    projectedFrame: CGRect
) -> ActivationPointEvidence {
    if element.usesDefaultActivationPoint {
        let point = CGPoint(x: projectedFrame.midX, y: projectedFrame.midY)
        guard point.x.isFinite, point.y.isFinite else { return .unavailable }
        return .defaultCenter(ScreenPoint(x: Double(point.x), y: Double(point.y)))
    }
    let sourceActivationPoint = CGPoint(
        x: CGFloat(element.activationPoint.x),
        y: CGFloat(element.activationPoint.y)
    )
    let projectedActivationPoint = CGPoint(
        x: sourceActivationPoint.x + projectedFrame.origin.x - sourceFrame.origin.x,
        y: sourceActivationPoint.y + projectedFrame.origin.y - sourceFrame.origin.y
    )
    guard projectedActivationPoint.x.isFinite, projectedActivationPoint.y.isFinite else { return .unavailable }
    return .explicit(ScreenPoint(
        x: Double(projectedActivationPoint.x),
        y: Double(projectedActivationPoint.y)
    ))
}

private func accessibilityFrame(for shape: AccessibilityShape) -> CGRect {
    switch shape {
    case .frame(let rect):
        return CGRect(
            x: CGFloat(rect.origin.x),
            y: CGFloat(rect.origin.y),
            width: CGFloat(rect.size.width),
            height: CGFloat(rect.size.height)
        )
    case .path(let elements):
        let path = CGMutablePath()
        for element in elements {
            switch element {
            case .move(let point):
                path.move(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
            case .line(let point):
                path.addLine(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
            case .quadCurve(let point, let control):
                path.addQuadCurve(
                    to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)),
                    control: CGPoint(x: CGFloat(control.x), y: CGFloat(control.y))
                )
            case .curve(let point, let control1, let control2):
                path.addCurve(
                    to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)),
                    control1: CGPoint(x: CGFloat(control1.x), y: CGFloat(control1.y)),
                    control2: CGPoint(x: CGFloat(control2.x), y: CGFloat(control2.y))
                )
            case .closeSubpath:
                path.closeSubpath()
            }
        }
        let bounds = path.boundingBoxOfPath
        guard !bounds.isNull,
              bounds.origin.x.isFinite,
              bounds.origin.y.isFinite,
              bounds.size.width.isFinite,
              bounds.size.height.isFinite else {
            return .zero
        }
        return bounds
    }
}

private func sanitizedDouble(_ value: CGFloat) -> Double {
    value.isFinite ? Double(value) : 0
}

private func sanitizedDouble(_ value: Double) -> Double {
    value.isFinite ? value : 0
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
}

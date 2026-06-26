import ThePlans
import Foundation
import CoreGraphics
import AccessibilitySnapshotModel

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
        self.activationPointX = activationPointX ?? frameX + (frameWidth / 2)
        self.activationPointY = activationPointY ?? frameY + (frameHeight / 2)
        self.respondsToUserInteraction = respondsToUserInteraction
        self.customContent = customContent
        self.rotors = rotors
        self.actions = actions
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
        case respondsToUserInteraction
        case customContent, rotors, actions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.description = try container.decode(String.self, forKey: .description)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        self.value = try container.decodeIfPresent(String.self, forKey: .value)
        self.identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        self.hint = try container.decodeIfPresent(String.self, forKey: .hint)
        self.traits = try container.decode([HeistTrait].self, forKey: .traits)
        self.frameX = try container.decode(Double.self, forKey: .frameX)
        self.frameY = try container.decode(Double.self, forKey: .frameY)
        self.frameWidth = try container.decode(Double.self, forKey: .frameWidth)
        self.frameHeight = try container.decode(Double.self, forKey: .frameHeight)
        self.activationPointX = try container.decode(Double.self, forKey: .activationPointX)
        self.activationPointY = try container.decode(Double.self, forKey: .activationPointY)
        self.respondsToUserInteraction = try container.decode(Bool.self, forKey: .respondsToUserInteraction)
        self.customContent = try container.decodeIfPresent([HeistCustomContent].self, forKey: .customContent)
        self.rotors = try container.decodeIfPresent([HeistRotor].self, forKey: .rotors)
        self.actions = try container.decode([ElementAction].self, forKey: .actions)
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
        try container.encode(respondsToUserInteraction, forKey: .respondsToUserInteraction)
        try container.encodeIfPresent(customContent, forKey: .customContent)
        try container.encodeIfPresent(rotors, forKey: .rotors)
        try container.encode(actions, forKey: .actions)
    }
}

public extension HeistElement {
    init(
        accessibilityElement element: AccessibilityElement,
        annotation: InterfaceElementAnnotation? = nil
    ) {
        let frame = accessibilityFrame(for: element.shape)
        let projectedFrame = contentSpaceFrame(for: frame, annotation: annotation)
        let activationPoint = accessibilityActivationPoint(
            for: element,
            sourceFrame: frame,
            projectedFrame: projectedFrame
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
            frameX: sanitizedDouble(projectedFrame.origin.x),
            frameY: sanitizedDouble(projectedFrame.origin.y),
            frameWidth: sanitizedDouble(projectedFrame.size.width),
            frameHeight: sanitizedDouble(projectedFrame.size.height),
            activationPointX: sanitizedDouble(activationPoint.x),
            activationPointY: sanitizedDouble(activationPoint.y),
            respondsToUserInteraction: element.respondsToUserInteraction,
            customContent: validCustomContent.isEmpty ? nil : validCustomContent.map {
                HeistCustomContent(label: $0.label, value: $0.value, isImportant: $0.isImportant)
            },
            rotors: validRotors.isEmpty ? nil : validRotors.map { HeistRotor(name: $0.name) },
            actions: annotation?.actions ?? []
        )
    }
}

private func contentSpaceFrame(for frame: CGRect, annotation: InterfaceElementAnnotation?) -> CGRect {
    guard let contentSpaceOrigin = annotation?.contentSpaceOrigin else { return frame }
    return CGRect(
        x: CGFloat(contentSpaceOrigin.x),
        y: CGFloat(contentSpaceOrigin.y),
        width: frame.size.width,
        height: frame.size.height
    )
}

private func accessibilityActivationPoint(
    for element: AccessibilityElement,
    sourceFrame: CGRect,
    projectedFrame: CGRect
) -> CGPoint {
    if element.usesDefaultActivationPoint {
        return CGPoint(x: projectedFrame.midX, y: projectedFrame.midY)
    }
    let sourceActivationPoint = CGPoint(
        x: CGFloat(element.activationPoint.x),
        y: CGFloat(element.activationPoint.y)
    )
    return CGPoint(
        x: sourceActivationPoint.x + projectedFrame.origin.x - sourceFrame.origin.x,
        y: sourceActivationPoint.y + projectedFrame.origin.y - sourceFrame.origin.y
    )
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

import Foundation
import ThePlans

package struct ElementDiagnosticSummary: Equatable, Sendable {
    package struct Geometry: Equatable, Sendable {
        package let frameX: Double
        package let frameY: Double
        package let frameWidth: Double
        package let frameHeight: Double
        package let activationPointX: Double
        package let activationPointY: Double

        package init(
            frameX: Double,
            frameY: Double,
            frameWidth: Double,
            frameHeight: Double,
            activationPointX: Double,
            activationPointY: Double
        ) {
            self.frameX = frameX
            self.frameY = frameY
            self.frameWidth = frameWidth
            self.frameHeight = frameHeight
            self.activationPointX = activationPointX
            self.activationPointY = activationPointY
        }
    }

    package enum Availability: Equatable, Sendable {
        case visible
        case offscreen(isReachable: Bool)
    }

    package enum Field: Equatable, Sendable {
        case label
        case identifier
        case value
        case hint
    }

    package let label: String?
    package let identifier: String?
    package let value: String?
    package let hint: String?
    package let traits: [HeistTrait]
    package let actions: [ElementAction]
    package let rotors: [String]
    package let geometry: Geometry?
    package let availability: Availability?
    package let liveObjectState: String?

    package init(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [],
        actions: [ElementAction] = [],
        rotors: [String] = [],
        geometry: Geometry? = nil,
        availability: Availability? = nil,
        liveObjectState: String? = nil
    ) {
        self.label = label
        self.identifier = identifier
        self.value = value
        self.hint = hint
        self.traits = traits
        self.actions = actions
        self.rotors = rotors.filter { !$0.isEmpty }
        self.geometry = geometry
        self.availability = availability
        self.liveObjectState = liveObjectState
    }

    package init(
        element: HeistElement,
        actions: [ElementAction]? = nil,
        availability: Availability? = nil,
        liveObjectState: String? = nil
    ) {
        self.init(
            label: element.label,
            identifier: element.identifier,
            value: element.value,
            hint: element.hint,
            traits: element.traits,
            actions: actions ?? element.actions,
            rotors: element.rotors?.compactMap { Self.nonEmpty($0.name) } ?? [],
            geometry: Geometry(
                frameX: element.frameX,
                frameY: element.frameY,
                frameWidth: element.frameWidth,
                frameHeight: element.frameHeight,
                activationPointX: element.activationPointX,
                activationPointY: element.activationPointY
            ),
            availability: availability,
            liveObjectState: liveObjectState
        )
    }

    package func rendered(using profile: RenderProfile) -> String {
        switch profile.body {
        case .actionCapability:
            return renderActionCapability(using: profile)
        case .activationAffordanceEvidence:
            return renderActivationAffordanceEvidence(using: profile)
        case .targetCandidate:
            return renderTargetCandidate(using: profile)
        case .containerCandidate(let type, let isModalBoundary):
            return renderContainerCandidate(type: type, isModalBoundary: isModalBoundary, using: profile)
        case .compactStash:
            return renderCompactStash(using: profile)
        case .failureInterface(let displayIndex):
            return renderFailureInterface(displayIndex: displayIndex, using: profile)
        case .selectedFields(let fields):
            return renderSelectedFields(fields, using: profile)
        case .availability:
            return renderedAvailability(using: profile) ?? ""
        }
    }

    private func renderActionCapability(using profile: RenderProfile) -> String {
        var parts = ["element"]
        if let label = Self.nonEmpty(label) {
            parts.append("label=\(profile.renderString(label))")
        }
        if let identifier = Self.nonEmpty(identifier) {
            parts.append("identifier=\(profile.renderString(identifier))")
        }
        if let value = Self.nonEmpty(value) {
            parts.append("value=\(profile.renderString(value))")
        }
        parts.append("traits=\(profile.renderList(traits.map(\.rawValue)))")
        parts.append("actions=\(profile.renderList(actions.map(\.description)))")
        if profile.includesLiveObjectState, let liveObjectState {
            parts.append("liveObject=\(liveObjectState)")
        }
        return parts.joined(separator: " ")
    }

    private func renderActivationAffordanceEvidence(using profile: RenderProfile) -> String {
        var parts: [String] = []
        if let label = Self.nonEmpty(label) {
            parts.append("label=\(profile.renderString(label))")
        }
        if let identifier = Self.nonEmpty(identifier) {
            parts.append("identifier=\(profile.renderString(identifier))")
        }
        parts.append("traits=\(profile.renderList(traits.map(\.rawValue)))")
        parts.append("actions=\(profile.renderList(actions.map(\.description)))")
        return parts.joined(separator: " ")
    }

    private func renderTargetCandidate(using profile: RenderProfile) -> String {
        var parts: [String] = []
        if let label = Self.nonEmpty(label) {
            parts.append(profile.renderString(label))
        }
        if let identifier = Self.nonEmpty(identifier) {
            parts.append("id=\(identifier)")
        }
        if let value = Self.nonEmpty(value) {
            parts.append("value=\(value)")
        }
        if let availability = renderedAvailability(using: profile) {
            parts.append(availability)
        }
        return parts.joined(separator: " ")
    }

    private func renderContainerCandidate(
        type: String,
        isModalBoundary: Bool,
        using profile: RenderProfile
    ) -> String {
        var parts = ["type=\(type)"]
        if let identifier = Self.nonEmpty(identifier) {
            parts.append("identifier=\(profile.renderString(identifier))")
        }
        if let label = Self.nonEmpty(label) {
            parts.append("label=\(profile.renderString(label))")
        }
        if let value = Self.nonEmpty(value) {
            parts.append("value=\(profile.renderString(value))")
        }
        if isModalBoundary {
            parts.append("modal=true")
        }
        return parts.joined(separator: " ")
    }

    private func renderCompactStash(using profile: RenderProfile) -> String {
        var parts: [String] = []
        if let label = Self.nonEmpty(label) {
            parts.append("label=\(profile.renderString(label))")
        }
        if let identifier = Self.nonEmpty(identifier) {
            parts.append("id=\(profile.renderString(identifier))")
        }
        if let value = Self.nonEmpty(value) {
            parts.append("value=\(profile.renderString(value))")
        }
        if !traits.isEmpty {
            parts.append("[\(traits.map(\.rawValue).joined(separator: ","))]")
        }
        if let availability = renderedAvailability(using: profile) {
            parts.append(availability)
        }
        return parts.joined(separator: " ")
    }

    private func renderFailureInterface(displayIndex: Int?, using profile: RenderProfile) -> String {
        var parts: [String] = []
        if let displayIndex {
            parts.append("[\(displayIndex)]")
        }

        var labelValue = profile.renderString(Self.nonEmpty(label) ?? "")
        if let value = Self.nonEmpty(value) {
            labelValue += ":\(profile.renderString(value))"
        }
        parts.append(labelValue)

        if !traits.isEmpty {
            parts.append(traits.map(\.rawValue).joined(separator: " | "))
        }
        if !actions.isEmpty {
            parts.append("{\(actions.map(\.description).joined(separator: ", "))}")
        }
        if !rotors.isEmpty {
            parts.append("[\(rotors.joined(separator: ", "))]")
        }
        if let hint = Self.nonEmpty(hint) {
            parts.append("hint=\(profile.renderString(hint))")
        }
        if let identifier = Self.nonEmpty(identifier) {
            parts.append("id=\(profile.renderString(identifier))")
        }
        if profile.includesGeometry, let geometry {
            parts.append("frame=(\(Int(geometry.frameX)),\(Int(geometry.frameY)),\(Int(geometry.frameWidth)),\(Int(geometry.frameHeight)))")
            parts.append("activation=(\(Int(geometry.activationPointX)),\(Int(geometry.activationPointY)))")
        }

        return parts.joined(separator: " ")
    }

    private func renderSelectedFields(_ fields: [Field], using profile: RenderProfile) -> String {
        fields.compactMap { field -> String? in
            switch field {
            case .label:
                return Self.nonEmpty(label).map { "label=\(profile.renderString($0))" }
            case .identifier:
                return Self.nonEmpty(identifier).map { "id=\(profile.renderString($0))" }
            case .value:
                return Self.nonEmpty(value).map { "value=\(profile.renderString($0))" }
            case .hint:
                return Self.nonEmpty(hint).map { "hint=\(profile.renderString($0))" }
            }
        }.joined(separator: " ")
    }

    private func renderedAvailability(using profile: RenderProfile) -> String? {
        guard profile.includesAvailability, let availability else { return nil }
        switch availability {
        case .visible:
            return "(visible)"
        case .offscreen(let isReachable):
            var details = ["offscreen"]
            if !isReachable {
                details.append("unreachable")
            }
            return "(\(details.joined(separator: ", ")))"
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private enum ElementDiagnosticSummaryRenderBody: Equatable, Sendable {
    case actionCapability
    case activationAffordanceEvidence
    case targetCandidate
    case containerCandidate(type: String, isModalBoundary: Bool)
    case compactStash
    case failureInterface(displayIndex: Int?)
    case selectedFields([ElementDiagnosticSummary.Field])
    case availability
}

private enum ElementDiagnosticSummaryStringStyle: Equatable, Sendable {
    case actionCapability
    case json
    case plainQuoted
}

package extension ElementDiagnosticSummary {
    enum ListItemStyle: Equatable, Sendable {
        case raw
        case quoted
    }

    struct RenderProfile: Equatable, Sendable {
        fileprivate let body: ElementDiagnosticSummaryRenderBody
        private let stringStyle: ElementDiagnosticSummaryStringStyle
        fileprivate let includesGeometry: Bool
        fileprivate let includesAvailability: Bool
        fileprivate let includesLiveObjectState: Bool

        private init(
            body: ElementDiagnosticSummaryRenderBody,
            stringStyle: ElementDiagnosticSummaryStringStyle,
            includesGeometry: Bool = false,
            includesAvailability: Bool = false,
            includesLiveObjectState: Bool = false
        ) {
            self.body = body
            self.stringStyle = stringStyle
            self.includesGeometry = includesGeometry
            self.includesAvailability = includesAvailability
            self.includesLiveObjectState = includesLiveObjectState
        }

        package static let actionCapability = RenderProfile(
            body: .actionCapability,
            stringStyle: .actionCapability
        )

        package static let activationAffordanceEvidence = RenderProfile(
            body: .activationAffordanceEvidence,
            stringStyle: .actionCapability
        )

        package static func actionCapability(includeLiveState: Bool) -> RenderProfile {
            RenderProfile(
                body: .actionCapability,
                stringStyle: .actionCapability,
                includesLiveObjectState: includeLiveState
            )
        }

        package static let targetCandidate = RenderProfile(
            body: .targetCandidate,
            stringStyle: .plainQuoted,
            includesAvailability: true
        )

        package static func containerCandidate(type: String, isModalBoundary: Bool) -> RenderProfile {
            RenderProfile(
                body: .containerCandidate(type: type, isModalBoundary: isModalBoundary),
                stringStyle: .plainQuoted
            )
        }

        package static let compactStash = RenderProfile(
            body: .compactStash,
            stringStyle: .plainQuoted,
            includesAvailability: true
        )

        package static func failureInterface(displayIndex: Int? = nil, includeGeometry: Bool = false) -> RenderProfile {
            RenderProfile(
                body: .failureInterface(displayIndex: displayIndex),
                stringStyle: .json,
                includesGeometry: includeGeometry
            )
        }

        package static func selectedFields(_ fields: [Field]) -> RenderProfile {
            RenderProfile(
                body: .selectedFields(fields),
                stringStyle: .plainQuoted
            )
        }

        package static let availability = RenderProfile(
            body: .availability,
            stringStyle: .plainQuoted,
            includesAvailability: true
        )

        package func renderString(_ value: String) -> String {
            switch stringStyle {
            case .actionCapability:
                let escaped = value
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: " ")
                return "\"\(escaped)\""
            case .json:
                return CanonicalValueDescription.quoted(value)
            case .plainQuoted:
                return "\"\(value)\""
            }
        }

        package func renderList(
            _ values: [String],
            itemStyle: ElementDiagnosticSummary.ListItemStyle = .raw
        ) -> String {
            let renderedValues = values.map { value in
                switch itemStyle {
                case .raw:
                    return value
                case .quoted:
                    return renderString(value)
                }
            }
            return "[\(renderedValues.joined(separator: ", "))]"
        }
    }
}

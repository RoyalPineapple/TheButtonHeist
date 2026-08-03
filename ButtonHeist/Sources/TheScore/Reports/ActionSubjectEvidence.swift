import ThePlans
import Foundation

/// Typed account of how the runtime produced the live subject used for dispatch.
public struct ActionSubjectResolution: Codable, Sendable, Equatable, Hashable {
    public enum Origin: String, Codable, Sendable, Equatable, Hashable {
        case visible
        case known
        case discovered
    }

    public enum Adjustment: String, CaseIterable, Codable, Sendable, Equatable, Hashable {
        case semanticReveal
        case activationPointPlacement
        case objectDeallocationRefresh
        case staleTargetRefresh
    }

    public let origin: Origin
    public let adjustments: Set<Adjustment>

    public init(origin: Origin, adjustments: Set<Adjustment> = []) {
        self.origin = origin
        self.adjustments = adjustments
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case origin
        case adjustments
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionSubjectResolution")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedAdjustments = try container.decode([Adjustment].self, forKey: .adjustments)
        let adjustments = Set(decodedAdjustments)
        guard adjustments.count == decodedAdjustments.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .adjustments,
                in: container,
                debugDescription: "ActionSubjectResolution adjustments must be unique"
            )
        }
        self.init(
            origin: try container.decode(Origin.self, forKey: .origin),
            adjustments: adjustments
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin, forKey: .origin)
        try container.encode(
            Adjustment.allCases.filter(adjustments.contains),
            forKey: .adjustments
        )
    }
}

/// Semantic subject the runtime resolved immediately before dispatching an action.
///
/// This is result evidence, not a replay selector. Offline suggestion tooling can
/// combine it with observed before/after state to choose a minimum matcher later.
public struct ActionSubjectEvidence: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case resolvedSemanticTarget
        case textInputTarget
        case elementGestureTarget
    }

    public enum Phase: String, Codable, Sendable {
        case resolvedBeforeDispatch
    }

    public let source: Source
    public let phase: Phase
    package let target: ResolvedAccessibilityTarget
    public let element: HeistElement
    public let resolution: ActionSubjectResolution

    package init(
        source: Source,
        phase: Phase = .resolvedBeforeDispatch,
        target: ResolvedAccessibilityTarget,
        element: HeistElement,
        resolution: ActionSubjectResolution
    ) {
        self.source = source
        self.phase = phase
        self.target = target
        self.element = element
        self.resolution = resolution
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case source
        case phase
        case target
        case element
        case resolution
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionSubjectEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            source: try container.decode(Source.self, forKey: .source),
            phase: try container.decode(Phase.self, forKey: .phase),
            target: try container.decode(ResolvedAccessibilityTarget.self, forKey: .target),
            element: try container.decode(HeistElement.self, forKey: .element),
            resolution: try container.decode(ActionSubjectResolution.self, forKey: .resolution)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(phase, forKey: .phase)
        try container.encode(target, forKey: .target)
        try container.encode(element, forKey: .element)
        try container.encode(resolution, forKey: .resolution)
    }
}

/// Dispatch-path diagnostics for semantic `activate`.
///
/// `Activate` refreshes semantic and live geometry first, then calls
/// `accessibilityActivate()` once. UIKit defines `false` as “not activated,” so
/// the runtime then sends one tap at the refreshed activation point.
public enum ActivationTracePhase: Sendable, Equatable {
    case refreshFailed
    case accessibilityActivate(axActivateReturned: Bool)
    case activationPointFallback(
        axActivateReturned: Bool?,
        tapActivationPoint: ScreenPoint,
        tapActivationSucceeded: Bool
    )
}

public struct ActivationTrace: Codable, Sendable, Equatable {
    private let phase: ActivationTracePhase
    /// Runtime implementation evidence captured only after semantic activation
    /// declined. This is diagnostic X-ray evidence, never dispatch permission.
    public let implementsAccessibilityActivation: Bool?

    public var axActivateReturned: Bool? {
        switch phase {
        case .refreshFailed:
            return nil
        case .accessibilityActivate(let axActivateReturned):
            return axActivateReturned
        case .activationPointFallback(let axActivateReturned, _, _):
            return axActivateReturned
        }
    }

    public var tapActivationDispatched: Bool {
        if case .activationPointFallback = phase {
            return true
        }
        return false
    }

    public var tapActivationPoint: ScreenPoint? {
        guard case .activationPointFallback(_, let point, _) = phase else {
            return nil
        }
        return point
    }

    public var tapActivationSucceeded: Bool? {
        guard case .activationPointFallback(_, _, let succeeded) = phase else {
            return nil
        }
        return succeeded
    }

    public init(
        _ phase: ActivationTracePhase,
        implementsAccessibilityActivation: Bool? = nil
    ) {
        self.phase = phase
        self.implementsAccessibilityActivation = implementsAccessibilityActivation
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case axActivateReturned
        case implementsAccessibilityActivation
        case tapActivationDispatched
        case tapActivationPoint
        case tapActivationSucceeded
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActivationTrace")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let axActivateReturned = try container.decodeIfPresent(Bool.self, forKey: .axActivateReturned)
        let implementsAccessibilityActivation = try container.decodeIfPresent(
            Bool.self,
            forKey: .implementsAccessibilityActivation
        )
        let tapActivationDispatched = try container.decode(Bool.self, forKey: .tapActivationDispatched)
        let tapActivationPoint = try container.decodeIfPresent(ScreenPoint.self, forKey: .tapActivationPoint)
        let tapActivationSucceeded = try container.decodeIfPresent(Bool.self, forKey: .tapActivationSucceeded)

        if tapActivationDispatched {
            guard let tapActivationPoint, let tapActivationSucceeded else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "tapActivationDispatched requires tapActivationPoint and tapActivationSucceeded"
                ))
            }
            self.init(.activationPointFallback(
                axActivateReturned: axActivateReturned,
                tapActivationPoint: tapActivationPoint,
                tapActivationSucceeded: tapActivationSucceeded
            ), implementsAccessibilityActivation: implementsAccessibilityActivation)
        } else {
            guard implementsAccessibilityActivation == nil,
                  tapActivationPoint == nil,
                  tapActivationSucceeded == nil else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "tapActivationPoint and tapActivationSucceeded require tapActivationDispatched"
                ))
            }
            self = if let axActivateReturned {
                Self(.accessibilityActivate(axActivateReturned: axActivateReturned))
            } else {
                Self(.refreshFailed)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(axActivateReturned, forKey: .axActivateReturned)
        try container.encodeIfPresent(
            implementsAccessibilityActivation,
            forKey: .implementsAccessibilityActivation
        )
        try container.encode(tapActivationDispatched, forKey: .tapActivationDispatched)
        try container.encodeIfPresent(tapActivationPoint, forKey: .tapActivationPoint)
        try container.encodeIfPresent(tapActivationSucceeded, forKey: .tapActivationSucceeded)
    }
}

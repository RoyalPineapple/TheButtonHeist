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
/// combine it with settled before/after traces to choose a minimum matcher later.
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
    public let target: ResolvedAccessibilityTarget
    public let element: HeistElement
    public let resolution: ActionSubjectResolution
    public let settledObservationSequence: SettledObservationSequence?

    public init(
        source: Source,
        phase: Phase = .resolvedBeforeDispatch,
        target: ResolvedAccessibilityTarget,
        element: HeistElement,
        resolution: ActionSubjectResolution,
        settledObservationSequence: SettledObservationSequence? = nil
    ) {
        self.source = source
        self.phase = phase
        self.target = target
        self.element = element
        self.resolution = resolution
        self.settledObservationSequence = settledObservationSequence
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case source
        case phase
        case target
        case element
        case resolution
        case settledObservationSequence
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionSubjectEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            source: try container.decode(Source.self, forKey: .source),
            phase: try container.decode(Phase.self, forKey: .phase),
            target: try container.decode(ResolvedAccessibilityTarget.self, forKey: .target),
            element: try container.decode(HeistElement.self, forKey: .element),
            resolution: try container.decode(ActionSubjectResolution.self, forKey: .resolution),
            settledObservationSequence: try container.decodeIfPresent(SettledObservationSequence.self, forKey: .settledObservationSequence)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(phase, forKey: .phase)
        try container.encode(target, forKey: .target)
        try container.encode(element, forKey: .element)
        try container.encode(resolution, forKey: .resolution)
        try container.encodeIfPresent(settledObservationSequence, forKey: .settledObservationSequence)
    }
}

/// Dispatch-path diagnostics for semantic `activate`.
///
/// `Activate` refreshes semantic and live geometry first, then calls
/// `accessibilityActivate()` once. A `true` result is treated as the semantic
/// action completing, so activation-point tap dispatch is not sent. When the
/// accessibility action declines, the runtime dispatches at the fresh activation
/// point if needed.
public enum ActivationTracePhase: Sendable, Equatable {
    case refreshFailed
    case accessibilityActivate
    case activationPointFallback(
        axActivateReturned: Bool?,
        tapActivationPoint: ScreenPoint,
        tapActivationSucceeded: Bool
    )
}

public struct ActivationTrace: Codable, Sendable, Equatable {
    private let phase: ActivationTracePhase

    public var axActivateReturned: Bool? {
        switch phase {
        case .refreshFailed:
            return nil
        case .accessibilityActivate:
            return true
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

    public init(_ phase: ActivationTracePhase) {
        self.phase = phase
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case axActivateReturned
        case tapActivationDispatched
        case tapActivationPoint
        case tapActivationSucceeded
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActivationTrace")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let axActivateReturned = try container.decodeIfPresent(Bool.self, forKey: .axActivateReturned)
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
            ))
        } else {
            guard tapActivationPoint == nil, tapActivationSucceeded == nil else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "tapActivationPoint and tapActivationSucceeded require tapActivationDispatched"
                ))
            }
            switch axActivateReturned {
            case .some(true):
                self.init(.accessibilityActivate)
            case .some(false):
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "axActivateReturned=false requires activation-point fallback fields"
                ))
            case nil:
                self.init(.refreshFailed)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(axActivateReturned, forKey: .axActivateReturned)
        try container.encode(tapActivationDispatched, forKey: .tapActivationDispatched)
        try container.encodeIfPresent(tapActivationPoint, forKey: .tapActivationPoint)
        try container.encodeIfPresent(tapActivationSucceeded, forKey: .tapActivationSucceeded)
    }
}

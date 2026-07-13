import Foundation

/// Optional local timing breakdown for one observed action pipeline.
public struct ActionPerformanceTiming: Codable, Sendable, Equatable {
    public let beforeObservationMs: Int?
    public let targetResolutionMs: Int?
    public let actionDispatchMs: Int?
    public let interactionMs: Int?
    public let settleMs: Int?
    public let finalSemanticEvidenceMs: Int?
    public let receiptGenerationMs: Int?
    public let totalMs: Int?

    public init(
        beforeObservationMs: Int? = nil,
        targetResolutionMs: Int? = nil,
        actionDispatchMs: Int? = nil,
        interactionMs: Int? = nil,
        settleMs: Int? = nil,
        finalSemanticEvidenceMs: Int? = nil,
        receiptGenerationMs: Int? = nil,
        totalMs: Int? = nil
    ) {
        self.beforeObservationMs = beforeObservationMs
        self.targetResolutionMs = targetResolutionMs
        self.actionDispatchMs = actionDispatchMs
        self.interactionMs = interactionMs
        self.settleMs = settleMs
        self.finalSemanticEvidenceMs = finalSemanticEvidenceMs
        self.receiptGenerationMs = receiptGenerationMs
        self.totalMs = totalMs
    }

    public func merging(_ other: ActionPerformanceTiming?) -> ActionPerformanceTiming {
        guard let other else { return self }
        return ActionPerformanceTiming(
            beforeObservationMs: other.beforeObservationMs ?? beforeObservationMs,
            targetResolutionMs: other.targetResolutionMs ?? targetResolutionMs,
            actionDispatchMs: other.actionDispatchMs ?? actionDispatchMs,
            interactionMs: other.interactionMs ?? interactionMs,
            settleMs: other.settleMs ?? settleMs,
            finalSemanticEvidenceMs: other.finalSemanticEvidenceMs ?? finalSemanticEvidenceMs,
            receiptGenerationMs: other.receiptGenerationMs ?? receiptGenerationMs,
            totalMs: other.totalMs ?? totalMs
        )
    }

}

public enum ActionResultObservationEvidence: Codable, Sendable, Equatable {
    case none
    case announcement(String)
    case trace(AccessibilityTrace)
    case settledTrace(AccessibilityTrace, ActionSettlementEvidence)

    public var accessibilityTrace: AccessibilityTrace? {
        switch self {
        case .trace(let trace), .settledTrace(let trace, _):
            return trace
        case .none, .announcement:
            return nil
        }
    }

    public var settlement: ActionSettlementEvidence? {
        guard case .settledTrace(_, let settlement) = self else { return nil }
        return settlement
    }

    public var announcement: String? {
        switch self {
        case .none:
            return nil
        case .announcement(let text):
            return text
        case .trace(let trace), .settledTrace(let trace, _):
            return trace.capturedAnnouncements.first?.text
        }
    }

    private enum Kind: String, Codable {
        case none
        case announcement
        case trace
        case settledTrace
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case announcement
        case accessibilityTrace
        case settlement
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionResultObservationEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .none:
            try Self.rejectFields(except: [.kind], in: container, kind: .none)
            self = .none
        case .announcement:
            try Self.rejectFields(except: [.kind, .announcement], in: container, kind: .announcement)
            let text = try container.decode(String.self, forKey: .announcement)
            guard !text.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .announcement,
                    in: container,
                    debugDescription: "action announcement must not be empty"
                )
            }
            self = .announcement(text)
        case .trace:
            try Self.rejectFields(except: [.kind, .accessibilityTrace], in: container, kind: .trace)
            self = .trace(try container.decode(AccessibilityTrace.self, forKey: .accessibilityTrace))
        case .settledTrace:
            try Self.rejectFields(
                except: [.kind, .accessibilityTrace, .settlement],
                in: container,
                kind: .settledTrace
            )
            self = .settledTrace(
                try container.decode(AccessibilityTrace.self, forKey: .accessibilityTrace),
                try container.decode(ActionSettlementEvidence.self, forKey: .settlement)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case .announcement(let text):
            try container.encode(Kind.announcement, forKey: .kind)
            try container.encode(text, forKey: .announcement)
        case .trace(let trace):
            try container.encode(Kind.trace, forKey: .kind)
            try container.encode(trace, forKey: .accessibilityTrace)
        case .settledTrace(let trace, let settlement):
            try container.encode(Kind.settledTrace, forKey: .kind)
            try container.encode(trace, forKey: .accessibilityTrace)
            try container.encode(settlement, forKey: .settlement)
        }
    }

    private static func rejectFields(
        except allowed: Set<CodingKeys>,
        in container: KeyedDecodingContainer<CodingKeys>,
        kind: Kind
    ) throws {
        for key in CodingKeys.allCases where !allowed.contains(key) && container.contains(key) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(kind.rawValue) action observation cannot include \(key.stringValue)"
            )
        }
    }
}

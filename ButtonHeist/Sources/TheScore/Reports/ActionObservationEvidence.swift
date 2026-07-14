import Foundation
import ThePlans

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
    case trace(AccessibilityTraceEvidence)
    case settledTrace(AccessibilityTraceEvidence, ActionSettlementEvidence)

    public var traceEvidence: AccessibilityTraceEvidence? {
        switch self {
        case .trace(let evidence), .settledTrace(let evidence, _):
            return evidence
        case .none, .announcement:
            return nil
        }
    }

    public var accessibilityTrace: AccessibilityTrace? {
        traceEvidence?.trace
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
        case .trace(let evidence), .settledTrace(let evidence, _):
            return evidence.trace.capturedAnnouncements.first?.text
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
        case traceEvidence
        case settlement
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionResultObservationEvidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .none:
            try container.rejectIncompatibleFields(
                allowing: [.kind],
                typeName: "none action observation"
            )
            self = .none
        case .announcement:
            try container.rejectIncompatibleFields(
                allowing: [.kind, .announcement],
                typeName: "announcement action observation"
            )
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
            try container.rejectIncompatibleFields(
                allowing: [.kind, .traceEvidence],
                typeName: "trace action observation"
            )
            self = .trace(try container.decode(AccessibilityTraceEvidence.self, forKey: .traceEvidence))
        case .settledTrace:
            try container.rejectIncompatibleFields(
                allowing: [.kind, .traceEvidence, .settlement],
                typeName: "settledTrace action observation"
            )
            self = .settledTrace(
                try container.decode(AccessibilityTraceEvidence.self, forKey: .traceEvidence),
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
        case .trace(let evidence):
            try container.encode(Kind.trace, forKey: .kind)
            try container.encode(evidence, forKey: .traceEvidence)
        case .settledTrace(let evidence, let settlement):
            try container.encode(Kind.settledTrace, forKey: .kind)
            try container.encode(evidence, forKey: .traceEvidence)
            try container.encode(settlement, forKey: .settlement)
        }
    }

}

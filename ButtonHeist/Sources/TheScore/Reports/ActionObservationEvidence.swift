import Foundation
import ThePlans

/// Optional local timing breakdown for one observed action pipeline.
public struct ActionPerformanceTiming: Codable, Sendable, Equatable {
    public let beforeObservationMs: ElapsedMilliseconds?
    public let targetResolutionMs: ElapsedMilliseconds?
    public let actionDispatchMs: ElapsedMilliseconds?
    public let interactionMs: ElapsedMilliseconds?
    public let finalSemanticEvidenceMs: ElapsedMilliseconds?
    public let resultAssemblyMs: ElapsedMilliseconds?
    public let totalMs: ElapsedMilliseconds?

    public init(
        beforeObservationMs: ElapsedMilliseconds? = nil,
        targetResolutionMs: ElapsedMilliseconds? = nil,
        actionDispatchMs: ElapsedMilliseconds? = nil,
        interactionMs: ElapsedMilliseconds? = nil,
        finalSemanticEvidenceMs: ElapsedMilliseconds? = nil,
        resultAssemblyMs: ElapsedMilliseconds? = nil,
        totalMs: ElapsedMilliseconds? = nil
    ) {
        self.beforeObservationMs = beforeObservationMs
        self.targetResolutionMs = targetResolutionMs
        self.actionDispatchMs = actionDispatchMs
        self.interactionMs = interactionMs
        self.finalSemanticEvidenceMs = finalSemanticEvidenceMs
        self.resultAssemblyMs = resultAssemblyMs
        self.totalMs = totalMs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case beforeObservationMs
        case targetResolutionMs
        case actionDispatchMs
        case interactionMs
        case finalSemanticEvidenceMs
        case resultAssemblyMs
        case totalMs
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ActionPerformanceTiming")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            beforeObservationMs: try container.decodeIfPresent(ElapsedMilliseconds.self, forKey: .beforeObservationMs),
            targetResolutionMs: try container.decodeIfPresent(ElapsedMilliseconds.self, forKey: .targetResolutionMs),
            actionDispatchMs: try container.decodeIfPresent(ElapsedMilliseconds.self, forKey: .actionDispatchMs),
            interactionMs: try container.decodeIfPresent(ElapsedMilliseconds.self, forKey: .interactionMs),
            finalSemanticEvidenceMs: try container.decodeIfPresent(
                ElapsedMilliseconds.self,
                forKey: .finalSemanticEvidenceMs
            ),
            resultAssemblyMs: try container.decodeIfPresent(ElapsedMilliseconds.self, forKey: .resultAssemblyMs),
            totalMs: try container.decodeIfPresent(ElapsedMilliseconds.self, forKey: .totalMs)
        )
    }
}

public struct ActionAnnouncementText: Codable, Sendable, Equatable, CustomStringConvertible {
    private let value: String

    public init(validating value: String) throws {
        self.value = try requireNonEmpty(
            value,
            or: ReportAdmissionError(description: "action announcement must not be empty")
        )
    }

    public init(from decoder: Decoder) throws {
        self = try decodeSingleValue(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValue(value, to: encoder)
    }

    public var description: String { value }
}

extension ActionAnnouncementText: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = requireValidLiteralPayload { try Self(validating: value) }
    }
}

public enum ActionResultObservationEvidence: Codable, Sendable, Equatable {
    case none
    case announcement(ActionAnnouncementText)
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
            return text.description
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
            self = .announcement(try container.decode(ActionAnnouncementText.self, forKey: .announcement))
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

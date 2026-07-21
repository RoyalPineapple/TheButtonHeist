import Foundation
import ThePlans

private enum HistoricalWaitDiagnosticsSemanticCandidateCodingKey: String, CodingKey, CaseIterable {
    case label
    case value
    case hint
    case traits
}

private enum HistoricalWaitDiagnosticsCandidateProvenanceCodingKey: String, CodingKey, CaseIterable {
    case firstObservationSequence
    case lastObservationSequence
}

private enum HistoricalWaitDiagnosticsPredicateMismatchCodingKey: String, CodingKey, CaseIterable {
    case exactPredicate
    case candidate
    case provenance
}

private enum HistoricalWaitDiagnosticsEvidenceCodingKey: String, CodingKey, CaseIterable {
    case predicateMismatches
}

public enum HistoricalWaitDiagnostics: Sendable {}

extension HistoricalWaitDiagnostics {
    public enum Request: String, Codable, Sendable, Equatable {
        case predicateMismatches = "predicate_mismatches"
    }

    public struct SemanticCandidate: Codable, Sendable, Equatable {
        public let label: String?
        public let value: String?
        public let hint: String?
        public let traits: [HeistTrait]

        public init?(
            label: String?,
            value: String?,
            hint: String?,
            traits: [HeistTrait]
        ) {
            guard label != nil || value != nil || hint != nil || !traits.isEmpty else { return nil }
            self.label = label
            self.value = value
            self.hint = hint
            self.traits = traits
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(
                allowed: HistoricalWaitDiagnosticsSemanticCandidateCodingKey.self,
                typeName: "historical wait semantic candidate"
            )
            let container = try decoder.container(
                keyedBy: HistoricalWaitDiagnosticsSemanticCandidateCodingKey.self
            )
            guard let candidate = Self(
                label: try container.decodeIfPresent(String.self, forKey: .label),
                value: try container.decodeIfPresent(String.self, forKey: .value),
                hint: try container.decodeIfPresent(String.self, forKey: .hint),
                traits: try container.decode([HeistTrait].self, forKey: .traits)
            ) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .traits,
                    in: container,
                    debugDescription: "historical wait candidates require accessibility-visible semantics"
                )
            }
            self = candidate
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(
                keyedBy: HistoricalWaitDiagnosticsSemanticCandidateCodingKey.self
            )
            try container.encodeIfPresent(label, forKey: .label)
            try container.encodeIfPresent(value, forKey: .value)
            try container.encodeIfPresent(hint, forKey: .hint)
            try container.encode(traits, forKey: .traits)
        }
    }

    public struct CandidateProvenance: Codable, Sendable, Equatable {
        public let firstObservationSequence: UInt64
        public let lastObservationSequence: UInt64

        public init?(
            firstObservationSequence: UInt64,
            lastObservationSequence: UInt64
        ) {
            guard firstObservationSequence <= lastObservationSequence else { return nil }
            self.firstObservationSequence = firstObservationSequence
            self.lastObservationSequence = lastObservationSequence
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(
                allowed: HistoricalWaitDiagnosticsCandidateProvenanceCodingKey.self,
                typeName: "historical wait candidate provenance"
            )
            let container = try decoder.container(
                keyedBy: HistoricalWaitDiagnosticsCandidateProvenanceCodingKey.self
            )
            let first = try container.decode(UInt64.self, forKey: .firstObservationSequence)
            let last = try container.decode(UInt64.self, forKey: .lastObservationSequence)
            guard let provenance = Self(
                firstObservationSequence: first,
                lastObservationSequence: last
            ) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .lastObservationSequence,
                    in: container,
                    debugDescription: "last observation sequence cannot precede the first"
                )
            }
            self = provenance
        }
    }

    public struct PredicateMismatch: Codable, Sendable, Equatable {
        public let exactPredicate: AccessibilityPredicate
        public let candidate: SemanticCandidate
        public let provenance: CandidateProvenance

        public init(
            exactPredicate: AccessibilityPredicate,
            candidate: SemanticCandidate,
            provenance: CandidateProvenance
        ) {
            self.exactPredicate = exactPredicate
            self.candidate = candidate
            self.provenance = provenance
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(
                allowed: HistoricalWaitDiagnosticsPredicateMismatchCodingKey.self,
                typeName: "historical wait predicate mismatch"
            )
            let container = try decoder.container(
                keyedBy: HistoricalWaitDiagnosticsPredicateMismatchCodingKey.self
            )
            self.init(
                exactPredicate: try container.decode(AccessibilityPredicate.self, forKey: .exactPredicate),
                candidate: try container.decode(SemanticCandidate.self, forKey: .candidate),
                provenance: try container.decode(CandidateProvenance.self, forKey: .provenance)
            )
        }
    }

    public struct Evidence: Codable, Sendable, Equatable {
        public static let maximumCandidateCount = 8

        public let predicateMismatches: [PredicateMismatch]

        public init?(predicateMismatches: [PredicateMismatch]) {
            guard !predicateMismatches.isEmpty,
                  predicateMismatches.count <= Self.maximumCandidateCount else {
                return nil
            }
            self.predicateMismatches = predicateMismatches
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(
                allowed: HistoricalWaitDiagnosticsEvidenceCodingKey.self,
                typeName: "historical wait diagnostic evidence"
            )
            let container = try decoder.container(
                keyedBy: HistoricalWaitDiagnosticsEvidenceCodingKey.self
            )
            let mismatches = try container.decode([PredicateMismatch].self, forKey: .predicateMismatches)
            guard let evidence = Self(predicateMismatches: mismatches) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .predicateMismatches,
                    in: container,
                    debugDescription: "historical wait evidence requires 1 through "
                        + "\(Self.maximumCandidateCount) predicate mismatches"
                )
            }
            self = evidence
        }
    }
}

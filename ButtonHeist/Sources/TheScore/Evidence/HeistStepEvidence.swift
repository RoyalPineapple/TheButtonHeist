import Foundation

public enum HeistStepEvidence: Codable, Sendable, Equatable {
    case action(HeistActionEvidence)
    case wait(HeistWaitEvidence)
    case caseSelection(HeistCaseSelectionEvidence)
    case forEachString(HeistForEachStringEvidence)
    case forEachElement(HeistForEachElementEvidence)
    case repeatUntil(HeistRepeatUntilEvidence)
    case invocation(HeistInvocationEvidence)
    case warning(HeistExecutionWarning)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case action
        case wait
        case caseSelection
        case forEachString
        case forEachElement
        case repeatUntil
        case invocation
        case warning
    }

    private enum PayloadCodingKeys: String, CodingKey, CaseIterable {
        case value = "_0"
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist step evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cases = CodingKeys.allCases.filter(container.contains)
        guard cases.count == 1, let evidenceCase = cases.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "heist step evidence must contain exactly one evidence case"
            ))
        }

        switch evidenceCase {
        case .action:
            self = .action(try Self.decodePayload(HeistActionEvidence.self, forKey: .action, in: container))
        case .wait:
            self = .wait(try Self.decodePayload(HeistWaitEvidence.self, forKey: .wait, in: container))
        case .caseSelection:
            self = .caseSelection(
                try Self.decodePayload(HeistCaseSelectionEvidence.self, forKey: .caseSelection, in: container)
            )
        case .forEachString:
            self = .forEachString(
                try Self.decodePayload(HeistForEachStringEvidence.self, forKey: .forEachString, in: container)
            )
        case .forEachElement:
            self = .forEachElement(
                try Self.decodePayload(HeistForEachElementEvidence.self, forKey: .forEachElement, in: container)
            )
        case .repeatUntil:
            self = .repeatUntil(
                try Self.decodePayload(HeistRepeatUntilEvidence.self, forKey: .repeatUntil, in: container)
            )
        case .invocation:
            self = .invocation(
                try Self.decodePayload(HeistInvocationEvidence.self, forKey: .invocation, in: container)
            )
        case .warning:
            self = .warning(
                try Self.decodePayload(HeistExecutionWarning.self, forKey: .warning, in: container)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let evidence):
            try Self.encodePayload(evidence, forKey: .action, in: &container)
        case .wait(let evidence):
            try Self.encodePayload(evidence, forKey: .wait, in: &container)
        case .caseSelection(let evidence):
            try Self.encodePayload(evidence, forKey: .caseSelection, in: &container)
        case .forEachString(let evidence):
            try Self.encodePayload(evidence, forKey: .forEachString, in: &container)
        case .forEachElement(let evidence):
            try Self.encodePayload(evidence, forKey: .forEachElement, in: &container)
        case .repeatUntil(let evidence):
            try Self.encodePayload(evidence, forKey: .repeatUntil, in: &container)
        case .invocation(let evidence):
            try Self.encodePayload(evidence, forKey: .invocation, in: &container)
        case .warning(let evidence):
            try Self.encodePayload(evidence, forKey: .warning, in: &container)
        }
    }

    private static func decodePayload<Payload: Decodable>(
        _ type: Payload.Type,
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Payload {
        let decoder = try container.superDecoder(forKey: key)
        try decoder.rejectUnknownKeys(allowed: PayloadCodingKeys.self, typeName: "heist step evidence payload")
        let payload = try decoder.container(keyedBy: PayloadCodingKeys.self)
        return try payload.decode(type, forKey: .value)
    }

    private static func encodePayload<Payload: Encodable>(
        _ payload: Payload,
        forKey key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        var payloadContainer = container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: key)
        try payloadContainer.encode(payload, forKey: .value)
    }
}

public enum HeistPredicateEvidenceOutcome: String, Codable, Sendable, Equatable {
    case matched
    case continued
    case handledElse = "handled_else"
    case failed
}

import Foundation
@testable import ButtonHeist

struct PublicHeistReportResponseDTO: Decodable, Equatable {
    let report: PublicHeistReportDTO
}

struct PublicHeistReportDTO: Decodable, Equatable {
    let summary: PublicHeistReportSummaryDTO
    let nodes: [PublicHeistReportNodeDTO]
}

struct PublicHeistReportSummaryDTO: Decodable, Equatable {
    let executedTopLevelStepCount: Int
    let executedNodeCount: Int
    let outputReceiptNodeCount: Int
    let durationMs: Int
    let abortedAtPath: String?
}

struct PublicHeistReportNodeDTO: Decodable, Equatable {
    let path: String
    let kind: String
    let status: String
    let message: String?
    let durationMs: Int
    let evidence: PublicHeistReportEvidenceDTO?
    let children: [PublicHeistReportNodeDTO]

    private let jsonKeys: Set<String>

    init(
        path: String,
        kind: String,
        status: String,
        message: String? = nil,
        durationMs: Int,
        evidence: PublicHeistReportEvidenceDTO? = nil,
        children: [PublicHeistReportNodeDTO] = []
    ) {
        self.path = path
        self.kind = kind
        self.status = status
        self.message = message
        self.durationMs = durationMs
        self.evidence = evidence
        self.children = children
        self.jsonKeys = []
    }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        let presence = try decoder.container(keyedBy: AnyJSONCodingKey.self)
        self.path = try keyed.decode(String.self, forKey: .path)
        self.kind = try keyed.decode(String.self, forKey: .kind)
        self.status = try keyed.decode(String.self, forKey: .status)
        self.message = try keyed.decodeIfPresent(String.self, forKey: .message)
        self.durationMs = try keyed.decode(Int.self, forKey: .durationMs)
        self.evidence = try keyed.decodeIfPresent(PublicHeistReportEvidenceDTO.self, forKey: .evidence)
        self.children = try keyed.decodeIfPresent([PublicHeistReportNodeDTO].self, forKey: .children) ?? []
        self.jsonKeys = Set(presence.allKeys.map(\.stringValue))
    }

    func containsKey(_ key: String) -> Bool {
        jsonKeys.contains(key)
    }

    static func == (lhs: PublicHeistReportNodeDTO, rhs: PublicHeistReportNodeDTO) -> Bool {
        lhs.path == rhs.path
            && lhs.kind == rhs.kind
            && lhs.status == rhs.status
            && lhs.message == rhs.message
            && lhs.durationMs == rhs.durationMs
            && lhs.evidence == rhs.evidence
            && lhs.children == rhs.children
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case kind
        case status
        case message
        case durationMs
        case evidence
        case children
    }
}

struct PublicHeistReportEvidenceDTO: Decodable, Equatable {
    let action: PublicHeistActionEvidenceDTO?

    init(action: PublicHeistActionEvidenceDTO? = nil) {
        self.action = action
    }
}

struct PublicHeistActionEvidenceDTO: Decodable, Equatable {
    let commandName: String?
    let result: PublicHeistActionResultDTO?

    init(
        commandName: String? = nil,
        result: PublicHeistActionResultDTO? = nil
    ) {
        self.commandName = commandName
        self.result = result
    }
}

struct PublicHeistActionResultDTO: Decodable, Equatable {
    let status: String
    let method: String
    let message: String?
    let screenId: String?
    let delta: PublicHeistDeltaDTO?
    let omitted: PublicHeistActionResultOmissionsDTO?

    init(
        status: String,
        method: String,
        message: String? = nil,
        screenId: String? = nil,
        delta: PublicHeistDeltaDTO? = nil,
        omitted: PublicHeistActionResultOmissionsDTO? = nil
    ) {
        self.status = status
        self.method = method
        self.message = message
        self.screenId = screenId
        self.delta = delta
        self.omitted = omitted
    }
}

struct PublicHeistActionResultOmissionsDTO: Decodable, Equatable {
    let accessibilityTrace: PublicHeistProjectionOmissionDTO?
    let subjectEvidence: PublicHeistProjectionOmissionDTO?

    init(
        accessibilityTrace: PublicHeistProjectionOmissionDTO? = nil,
        subjectEvidence: PublicHeistProjectionOmissionDTO? = nil
    ) {
        self.accessibilityTrace = accessibilityTrace
        self.subjectEvidence = subjectEvidence
    }
}

extension PublicHeistActionResultOmissionsDTO {
    static func accessibilityTraceProjectedAsDelta(omittedCount: Int) -> Self {
        Self(
            accessibilityTrace: PublicHeistProjectionOmissionDTO(
                reason: "raw accessibility trace omitted from public heist report",
                projectedAs: "delta",
                omittedCount: omittedCount
            )
        )
    }
}

struct PublicHeistProjectionOmissionDTO: Decodable, Equatable {
    let reason: String
    let projectedAs: String?
    let omittedCount: Int?
}

struct PublicHeistDeltaDTO: Decodable, Equatable {
    let kind: String
    let elementCount: Int
    let interactionDigest: PublicHeistInteractionDigestDTO?
    let edits: PublicHeistElementEditsDTO?
    let screen: PublicHeistScreenDTO?

    private let jsonKeys: Set<String>

    init(
        kind: String,
        elementCount: Int,
        interactionDigest: PublicHeistInteractionDigestDTO? = nil,
        edits: PublicHeistElementEditsDTO? = nil,
        screen: PublicHeistScreenDTO? = nil
    ) {
        self.kind = kind
        self.elementCount = elementCount
        self.interactionDigest = interactionDigest
        self.edits = edits
        self.screen = screen
        self.jsonKeys = []
    }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        let presence = try decoder.container(keyedBy: AnyJSONCodingKey.self)
        self.kind = try keyed.decode(String.self, forKey: .kind)
        self.elementCount = try keyed.decode(Int.self, forKey: .elementCount)
        self.interactionDigest = try keyed.decodeIfPresent(
            PublicHeistInteractionDigestDTO.self,
            forKey: .interactionDigest
        )
        self.edits = try keyed.decodeIfPresent(PublicHeistElementEditsDTO.self, forKey: .edits)
        self.screen = try keyed.decodeIfPresent(PublicHeistScreenDTO.self, forKey: .screen)
        self.jsonKeys = Set(presence.allKeys.map(\.stringValue))
    }

    func containsKey(_ key: String) -> Bool {
        jsonKeys.contains(key)
    }

    static func == (lhs: PublicHeistDeltaDTO, rhs: PublicHeistDeltaDTO) -> Bool {
        lhs.kind == rhs.kind
            && lhs.elementCount == rhs.elementCount
            && lhs.interactionDigest == rhs.interactionDigest
            && lhs.edits == rhs.edits
            && lhs.screen == rhs.screen
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case elementCount
        case interactionDigest
        case edits
        case screen
    }
}

struct PublicHeistInteractionDigestDTO: Decodable, Equatable {
    let elementCountBefore: Int
    let elementCountAfter: Int
    let elementCountChanged: Bool
    let elementSetChanged: Bool
    let screenIdBefore: String?
    let screenIdAfter: String?
    let screenIdChanged: Bool
    let firstResponderChanged: Bool

    init(
        elementCountBefore: Int,
        elementCountAfter: Int,
        elementCountChanged: Bool,
        elementSetChanged: Bool,
        screenIdBefore: String? = nil,
        screenIdAfter: String? = nil,
        screenIdChanged: Bool,
        firstResponderChanged: Bool
    ) {
        self.elementCountBefore = elementCountBefore
        self.elementCountAfter = elementCountAfter
        self.elementCountChanged = elementCountChanged
        self.elementSetChanged = elementSetChanged
        self.screenIdBefore = screenIdBefore
        self.screenIdAfter = screenIdAfter
        self.screenIdChanged = screenIdChanged
        self.firstResponderChanged = firstResponderChanged
    }
}

struct PublicHeistElementEditsDTO: Decodable, Equatable {
    let added: [PublicHeistElementDTO]?
    let omitted: PublicHeistElementEditOmissionsDTO?

    init(
        added: [PublicHeistElementDTO]? = nil,
        omitted: PublicHeistElementEditOmissionsDTO? = nil
    ) {
        self.added = added
        self.omitted = omitted
    }
}

struct PublicHeistElementEditOmissionsDTO: Decodable, Equatable {
    let added: Int?
    let addedKeys: [String]?

    init(
        added: Int? = nil,
        addedKeys: [String]? = nil
    ) {
        self.added = added
        self.addedKeys = addedKeys
    }
}

struct PublicHeistScreenDTO: Decodable, Equatable {
    let screenId: String?
    let elementCount: Int
    let elements: [PublicHeistElementDTO]?
    let omittedElementCount: Int?

    init(
        screenId: String? = nil,
        elementCount: Int,
        elements: [PublicHeistElementDTO]? = nil,
        omittedElementCount: Int? = nil
    ) {
        self.screenId = screenId
        self.elementCount = elementCount
        self.elements = elements
        self.omittedElementCount = omittedElementCount
    }
}

struct PublicHeistElementDTO: Decodable, Equatable {
    let traits: [String]
    let label: String?
    let value: String?
    let identifier: String?

    init(
        traits: [String],
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil
    ) {
        self.traits = traits
        self.label = label
        self.value = value
        self.identifier = identifier
    }
}

func publicHeistReportResponseDTO(_ response: FenceResponse) throws -> PublicHeistReportResponseDTO {
    try publicJSONProbe(response).decode(PublicHeistReportResponseDTO.self)
}

private struct AnyJSONCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

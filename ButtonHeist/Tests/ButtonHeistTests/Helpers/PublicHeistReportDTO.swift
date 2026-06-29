import ButtonHeistTestSupport
import Foundation
@_spi(ButtonHeistTooling) @testable import ButtonHeist

struct PublicHeistReportResponseDTO: Decodable, Equatable {
    let report: PublicHeistReportDTO
}

struct PublicHeistReportDTO: Decodable, Equatable {
    let summary: PublicHeistReportSummaryDTO
    let nodes: [PublicHeistReportNodeDTO]
    let netDelta: PublicHeistDeltaDTO?

    init(
        summary: PublicHeistReportSummaryDTO,
        nodes: [PublicHeistReportNodeDTO],
        netDelta: PublicHeistDeltaDTO? = nil
    ) {
        self.summary = summary
        self.nodes = nodes
        self.netDelta = netDelta
    }
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
    let failure: PublicHeistFailureDetailDTO?
    let children: [PublicHeistReportNodeDTO]

    private let jsonKeys: Set<String>

    init(
        path: String,
        kind: String,
        status: String,
        message: String? = nil,
        durationMs: Int,
        evidence: PublicHeistReportEvidenceDTO? = nil,
        failure: PublicHeistFailureDetailDTO? = nil,
        children: [PublicHeistReportNodeDTO] = []
    ) {
        self.path = path
        self.kind = kind
        self.status = status
        self.message = message
        self.durationMs = durationMs
        self.evidence = evidence
        self.failure = failure
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
        self.failure = try keyed.decodeIfPresent(PublicHeistFailureDetailDTO.self, forKey: .failure)
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
            && lhs.failure == rhs.failure
            && lhs.children == rhs.children
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case kind
        case status
        case message
        case durationMs
        case evidence
        case failure
        case children
    }
}

struct PublicHeistFailureDetailDTO: Decodable, Equatable {
    let category: String
    let contract: String
    let observed: String
    let expected: String?
    let code: String
    let kind: String
    let errorCode: String
    let phase: String
    let retryable: Bool
    let hint: String?
}

struct PublicHeistReportEvidenceDTO: Decodable, Equatable {
    let action: PublicHeistActionEvidenceDTO?
    let wait: PublicHeistWaitEvidenceDTO?
    let caseSelection: PublicHeistCaseSelectionEvidenceDTO?
    let forEachString: PublicHeistForEachStringEvidenceDTO?
    let forEachElement: PublicHeistForEachElementEvidenceDTO?
    let repeatUntil: PublicHeistRepeatUntilEvidenceDTO?
    let invocation: PublicHeistInvocationEvidenceDTO?
    let warning: PublicHeistWarningEvidenceDTO?

    private let jsonKeys: Set<String>

    init(
        action: PublicHeistActionEvidenceDTO? = nil,
        wait: PublicHeistWaitEvidenceDTO? = nil,
        caseSelection: PublicHeistCaseSelectionEvidenceDTO? = nil,
        forEachString: PublicHeistForEachStringEvidenceDTO? = nil,
        forEachElement: PublicHeistForEachElementEvidenceDTO? = nil,
        repeatUntil: PublicHeistRepeatUntilEvidenceDTO? = nil,
        invocation: PublicHeistInvocationEvidenceDTO? = nil,
        warning: PublicHeistWarningEvidenceDTO? = nil
    ) {
        self.action = action
        self.wait = wait
        self.caseSelection = caseSelection
        self.forEachString = forEachString
        self.forEachElement = forEachElement
        self.repeatUntil = repeatUntil
        self.invocation = invocation
        self.warning = warning
        self.jsonKeys = Set([
            action.map { _ in CodingKeys.action.rawValue },
            wait.map { _ in CodingKeys.wait.rawValue },
            caseSelection.map { _ in CodingKeys.caseSelection.rawValue },
            forEachString.map { _ in CodingKeys.forEachString.rawValue },
            forEachElement.map { _ in CodingKeys.forEachElement.rawValue },
            repeatUntil.map { _ in CodingKeys.repeatUntil.rawValue },
            invocation.map { _ in CodingKeys.invocation.rawValue },
            warning.map { _ in CodingKeys.warning.rawValue },
        ].compactMap { $0 })
    }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        let presence = try decoder.container(keyedBy: AnyJSONCodingKey.self)
        self.action = try keyed.decodeIfPresent(PublicHeistActionEvidenceDTO.self, forKey: .action)
        self.wait = try keyed.decodeIfPresent(PublicHeistWaitEvidenceDTO.self, forKey: .wait)
        self.caseSelection = try keyed.decodeIfPresent(
            PublicHeistCaseSelectionEvidenceDTO.self,
            forKey: .caseSelection
        )
        self.forEachString = try keyed.decodeIfPresent(
            PublicHeistForEachStringEvidenceDTO.self,
            forKey: .forEachString
        )
        self.forEachElement = try keyed.decodeIfPresent(
            PublicHeistForEachElementEvidenceDTO.self,
            forKey: .forEachElement
        )
        self.repeatUntil = try keyed.decodeIfPresent(PublicHeistRepeatUntilEvidenceDTO.self, forKey: .repeatUntil)
        self.invocation = try keyed.decodeIfPresent(PublicHeistInvocationEvidenceDTO.self, forKey: .invocation)
        self.warning = try keyed.decodeIfPresent(PublicHeistWarningEvidenceDTO.self, forKey: .warning)
        self.jsonKeys = Set(presence.allKeys.map(\.stringValue))
    }

    var encodedVariantKeys: Set<String> {
        jsonKeys
    }

    static func == (lhs: PublicHeistReportEvidenceDTO, rhs: PublicHeistReportEvidenceDTO) -> Bool {
        lhs.action == rhs.action
            && lhs.wait == rhs.wait
            && lhs.caseSelection == rhs.caseSelection
            && lhs.forEachString == rhs.forEachString
            && lhs.forEachElement == rhs.forEachElement
            && lhs.repeatUntil == rhs.repeatUntil
            && lhs.invocation == rhs.invocation
            && lhs.warning == rhs.warning
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case wait
        case caseSelection
        case forEachString
        case forEachElement
        case repeatUntil
        case invocation
        case warning
    }
}

struct PublicHeistActionEvidenceDTO: Decodable, Equatable {
    let commandName: String?
    let result: PublicHeistActionResultDTO?
    let expectationResult: PublicHeistActionResultDTO?
    let expectation: PublicExpectationResultDTO?

    init(
        commandName: String? = nil,
        result: PublicHeistActionResultDTO? = nil,
        expectationResult: PublicHeistActionResultDTO? = nil,
        expectation: PublicExpectationResultDTO? = nil
    ) {
        self.commandName = commandName
        self.result = result
        self.expectationResult = expectationResult
        self.expectation = expectation
    }
}

struct PublicHeistWaitEvidenceDTO: Decodable, Equatable {
    let outcome: String
    let result: PublicHeistActionResultDTO
    let expectation: PublicExpectationResultDTO
    let baselineSummary: String?
    let finalSummary: String?
}

struct PublicHeistCaseSelectionEvidenceDTO: Decodable, Equatable {
    let outcome: JSONValue
    let elapsedMs: Int
    let timeout: Double?
    let lastObservedSummary: String?
    let caseCount: Int
    let cases: [PublicHeistCaseMatchResultDTO]?
    let omittedCaseCount: Int?
}

struct PublicHeistCaseMatchResultDTO: Decodable, Equatable {
    let predicate: JSONValue
    let met: Bool
    let actual: String?
}

struct PublicHeistForEachStringEvidenceDTO: Decodable, Equatable {
    let parameter: String
    let count: Int
    let iterationCount: Int
    let iterationOrdinal: Int?
    let value: String?
    let failureReason: String?
}

struct PublicHeistForEachElementEvidenceDTO: Decodable, Equatable {
    let parameter: String
    let matching: JSONValue
    let limit: Int
    let matchedCount: Int
    let iterationCount: Int
    let iterationOrdinal: Int?
    let targetOrdinal: Int?
    let targetSummary: String?
    let failureReason: String?
}

struct PublicHeistRepeatUntilEvidenceDTO: Decodable, Equatable {
    let outcome: String
    let predicate: JSONValue
    let timeout: Double
    let iterationCount: Int
    let iterationOrdinal: Int?
    let expectation: PublicExpectationResultDTO
    let result: PublicHeistActionResultDTO?
    let lastObservedSummary: String?
    let failureReason: String?
}

struct PublicHeistInvocationEvidenceDTO: Decodable, Equatable {
    let capability: String?
    let name: String?
    let argument: String?
    let childFailedPath: String?
    let expectationResult: PublicHeistActionResultDTO?
    let expectation: PublicExpectationResultDTO?
}

struct PublicHeistWarningEvidenceDTO: Decodable, Equatable {
    let path: String
    let message: String
}

struct PublicExpectationResultDTO: Decodable, Equatable {
    let met: Bool?
    let actual: String?
    let expected: JSONValue?
    let hint: String?
}

struct PublicHeistActionResultDTO: Decodable, Equatable {
    let status: String
    let method: String
    let message: String?
    let value: String?
    let rotor: PublicRotorResultDTO?
    let screenId: String?
    let errorClass: String?
    let errorCode: String?
    let kind: String?
    let phase: String?
    let retryable: Bool?
    let hint: String?
    let expectation: PublicExpectationResultDTO?
    let delta: PublicHeistDeltaDTO?
    let omitted: PublicHeistActionResultOmissionsDTO?

    init(
        status: String,
        method: String,
        message: String? = nil,
        value: String? = nil,
        rotor: PublicRotorResultDTO? = nil,
        screenId: String? = nil,
        errorClass: String? = nil,
        errorCode: String? = nil,
        kind: String? = nil,
        phase: String? = nil,
        retryable: Bool? = nil,
        hint: String? = nil,
        expectation: PublicExpectationResultDTO? = nil,
        delta: PublicHeistDeltaDTO? = nil,
        omitted: PublicHeistActionResultOmissionsDTO? = nil
    ) {
        self.status = status
        self.method = method
        self.message = message
        self.value = value
        self.rotor = rotor
        self.screenId = screenId
        self.errorClass = errorClass
        self.errorCode = errorCode
        self.kind = kind
        self.phase = phase
        self.retryable = retryable
        self.hint = hint
        self.expectation = expectation
        self.delta = delta
        self.omitted = omitted
    }
}

struct PublicRotorResultDTO: Decodable, Equatable {
    let name: String
    let direction: String
    let textRange: PublicRotorTextRangeDTO?
}

struct PublicRotorTextRangeDTO: Decodable, Equatable {
    let rangeDescription: String
    let text: String?
    let startOffset: Int?
    let endOffset: Int?
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
    let transient: [PublicHeistElementDTO]?
    let omitted: PublicHeistDeltaOmissionsDTO?

    private let jsonKeys: Set<String>

    init(
        kind: String,
        elementCount: Int,
        interactionDigest: PublicHeistInteractionDigestDTO? = nil,
        edits: PublicHeistElementEditsDTO? = nil,
        screen: PublicHeistScreenDTO? = nil,
        transient: [PublicHeistElementDTO]? = nil,
        omitted: PublicHeistDeltaOmissionsDTO? = nil
    ) {
        self.kind = kind
        self.elementCount = elementCount
        self.interactionDigest = interactionDigest
        self.edits = edits
        self.screen = screen
        self.transient = transient
        self.omitted = omitted
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
        self.transient = try keyed.decodeIfPresent([PublicHeistElementDTO].self, forKey: .transient)
        self.omitted = try keyed.decodeIfPresent(PublicHeistDeltaOmissionsDTO.self, forKey: .omitted)
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
            && lhs.transient == rhs.transient
            && lhs.omitted == rhs.omitted
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case elementCount
        case interactionDigest
        case edits
        case screen
        case transient
        case omitted
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

struct PublicHeistDeltaOmissionsDTO: Decodable, Equatable {
    let transient: Int?
    let transientKeys: [String]?

    init(
        transient: Int? = nil,
        transientKeys: [String]? = nil
    ) {
        self.transient = transient
        self.transientKeys = transientKeys
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

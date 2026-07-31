import Foundation
import ThePlans

import AccessibilitySnapshotModel
import TheScore

private enum PublicActionResultCodingKey: String, CodingKey {
    case status
    case method
    case message
    case screenActionHandler
    case warning
    case announcement
    case value
    case rotor
    case screenshot
    case delta
    case screenName
    case screenId
    case errorClass
    case code
    case kind
    case phase
    case retryable
    case hint
    case expectation
    case activationTrace
    case timing
    case omitted
}

struct PublicActionResponse: Encodable {
    private let projection: ActionProjection

    init(command: TheFence.Command, result: ActionResult, expectation: ExpectationResult?) {
        self.init(projection: ActionProjection(
            method: command.rawValue,
            result: result,
            expectation: expectation,
            expectationHint: expectation.flatMap {
                FenceResponse.expectationFailureHint($0, command: command, result: result)
            },
            profile: .summary
        ))
    }

    init(projection: ActionProjection) {
        self.projection = projection
    }

    func encode(to encoder: Encoder) throws {
        try projection.encode(to: encoder)
    }

}

enum PublicActionResultContext: Sendable, Equatable {
    case standaloneAction
    case heistReportEvidence

    var includesOmissions: Bool {
        self == .heistReportEvidence
    }

    var deltaScreenPolicy: PublicDeltaScreenPolicy {
        switch self {
        case .standaloneAction:
            return .newInterface
        case .heistReportEvidence:
            return .screenSummary
        }
    }
}

extension ActionProjection: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PublicActionResultCodingKey.self)
        try container.encode(status, forKey: .status)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(screenActionHandler, forKey: .screenActionHandler)
        try container.encodeIfPresent(warning, forKey: .warning)
        try container.encodeIfPresent(announcement, forKey: .announcement)
        try encodePayload(to: &container)
        try container.encodeIfPresent(
            delta.map { PublicDelta(projection: $0, screenPolicy: publicContext.deltaScreenPolicy) },
            forKey: .delta
        )
        try container.encodeIfPresent(screenName, forKey: .screenName)
        try container.encodeIfPresent(screenId, forKey: .screenId)
        try encodeFailure(to: &container)
        try container.encodeIfPresent(expectation, forKey: .expectation)
        try container.encodeIfPresent(activationTrace, forKey: .activationTrace)
        try container.encodeIfPresent(timing, forKey: .timing)
        if publicContext.includesOmissions {
            let omitted = omitted.flatMap { $0.isEmpty ? nil : $0 }
            try container.encodeIfPresent(omitted, forKey: .omitted)
        }
    }

    private func encodePayload(to container: inout KeyedEncodingContainer<PublicActionResultCodingKey>) throws {
        switch payload {
        case .value(let value):
            try container.encode(value, forKey: .value)
        case .rotor(let rotor):
            try container.encode(PublicRotorResult(result: rotor), forKey: .rotor)
        case .screenshot(let width, let height):
            try container.encode(PublicScreenshotResult(width: width, height: height), forKey: .screenshot)
        case .none:
            break
        }
    }

    private func encodeFailure(to container: inout KeyedEncodingContainer<PublicActionResultCodingKey>) throws {
        guard let failure else { return }
        try container.encode(failure.errorClass, forKey: .errorClass)
        try container.encode(failure.code, forKey: .code)
        try container.encode(failure.kind, forKey: .kind)
        try container.encode(failure.phase, forKey: .phase)
        try container.encode(failure.retryable, forKey: .retryable)
        try container.encodeIfPresent(failure.hint, forKey: .hint)
    }
}

struct PublicScreenshotResult: Encodable {
    let width: Double
    let height: Double
}

/// Status vocabulary for public command responses.
enum PublicResponseStatus: String, Encodable, Sendable, Equatable {
    case ok
    case error
    case expectationFailed = "expectation_failed"
    case partial
}

extension ActionResult {
    /// Status for this action result and its optional expectation. The
    /// expectation only influences status on an otherwise successful action.
    func publicStatus(expectation: ExpectationResult?) -> PublicResponseStatus {
        if !outcome.isSuccess { return .error }
        if let expectation, !expectation.met { return .expectationFailed }
        return .ok
    }

    /// Canonical public failure projection shared by JSON and compact renderers.
    func diagnosticFailureProjection(fallbackMessage: String) -> ActionFailureProjection? {
        guard !outcome.isSuccess else { return nil }
        let resolvedErrorKind = outcome.failureKind ?? .actionFailed
        return ActionFailureProjection(
            message: message ?? fallbackMessage,
            errorClass: resolvedErrorKind.rawValue,
            diagnosticFailure: DiagnosticFailure(
                failureKind: resolvedErrorKind,
                message: message ?? fallbackMessage
            )
        )
    }
}

struct ActionFailureProjection {
    let message: String
    let errorClass: String
    let diagnosticFailure: DiagnosticFailure

    var code: String { diagnosticFailure.code }
    var kind: String { diagnosticFailure.kind.rawValue }
    var phase: String { diagnosticFailure.phase.rawValue }
    var retryable: Bool { diagnosticFailure.retryable }
    var hint: String? { diagnosticFailure.hint }
    var compactCode: String { code }
}

struct PublicRotorResult: Encodable {
    let name: String
    let direction: String
    let found: HeistElement?
    let textRange: PublicRotorTextRange?

    init(result: RotorResult) {
        self.name = result.rotor.description
        self.direction = result.direction.rawValue
        self.found = result.foundElement
        self.textRange = result.textRange.map { PublicRotorTextRange(range: $0) }
    }
}

struct PublicRotorTextRange: Encodable {
    let rangeDescription: String
    let text: String?
    let startOffset: Int?
    let endOffset: Int?

    init(range: RotorTextRange) {
        self.rangeDescription = range.rangeDescription
        self.text = range.text
        self.startOffset = range.startOffset
        self.endOffset = range.endOffset
    }
}

enum PublicDeltaScreenPolicy: Sendable {
    case newInterface
    case screenSummary
}

struct PublicDelta: Encodable {
    let projection: DeltaProjection
    let screenPolicy: PublicDeltaScreenPolicy

    private enum CodingKeys: String, CodingKey {
        case kind
        case elementCount
        case edits
        case newInterface
        case screen
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch projection {
        case .noChange(let elementCount):
            try encodeHeader(kind: .noChange, elementCount: elementCount, to: &container)

        case .elementsChanged(let elementCount, let edits):
            try encodeHeader(kind: .elementsChanged, elementCount: elementCount, to: &container)
            let edits = PublicElementEdits(projection: edits)
            try container.encodeIfPresent(edits.isEmpty ? nil : edits, forKey: .edits)

        case .screenChanged(let elementCount, let screen):
            try encodeHeader(kind: .screenChanged, elementCount: elementCount, to: &container)
            switch screenPolicy {
            case .newInterface:
                try container.encodeIfPresent(
                    screen.interface,
                    forKey: .newInterface
                )
            case .screenSummary:
                try container.encode(PublicHeistScreenProjection(projection: screen), forKey: .screen)
            }
        }
    }

    private func encodeHeader(
        kind: DeltaProjectionKind,
        elementCount: Int,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(elementCount, forKey: .elementCount)
    }
}

struct PublicElementEdits: Encodable {
    let added: [PublicElement]?
    let removed: [PublicElement]?
    let updated: [PublicElementUpdate]?
    let omitted: PublicHeistElementEditOmissions?

    var isEmpty: Bool {
        added == nil && removed == nil && updated == nil && omitted == nil
    }

    init(projection: DeltaEditsProjection) {
        self.added = projection.added.values.isEmpty
            ? nil
            : projection.added.values.map { PublicElement(element: $0, detail: .summary) }
        self.removed = projection.removed.values.isEmpty
            ? nil
            : projection.removed.values.map { PublicElement(element: $0, detail: .summary) }
        self.updated = projection.updated.values.isEmpty
            ? nil
            : projection.updated.values.compactMap(PublicElementUpdate.init(update:))
        let omitted = PublicHeistElementEditOmissions(projection: projection)
        self.omitted = omitted.isEmpty ? nil : omitted
    }
}

struct PublicElementUpdate: Encodable {
    let before: PublicElement
    let after: PublicElement
    let changes: [PublicPropertyChange]

    init?(update: ElementUpdate) {
        let meaningfulChanges = update.changes.filter { !$0.property.isGeometry }
        guard !meaningfulChanges.isEmpty else { return nil }
        self.before = PublicElement(element: update.before, detail: .summary)
        self.after = PublicElement(element: update.after, detail: .summary)
        self.changes = meaningfulChanges.map(PublicPropertyChange.init(change:))
    }
}

struct PublicPropertyChange: Encodable {
    let property: ElementProperty
    let old: String?
    let new: String?

    init(change: PropertyChange) {
        self.property = change.property
        self.old = change.oldValue?.displayText
        self.new = change.newValue?.displayText
    }
}

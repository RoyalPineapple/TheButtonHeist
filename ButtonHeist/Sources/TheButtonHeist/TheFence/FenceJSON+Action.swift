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
    case heistExecution
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
            actionMethod: .fence(command),
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

    var includesExpectation: Bool {
        self == .standaloneAction
    }

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
        try container.encode(actionMethod.rawValue, forKey: .method)
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
        case .heistExecutionStepCount(let stepCount):
            try container.encode(PublicHeistExecutionActionResult(stepCount: stepCount), forKey: .heistExecution)
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

struct PublicHeistExecutionActionResult: Encodable {
    let stepCount: Int
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
        case captureEdge
        case interactionDigest
        case accessibilityNotifications
        case transient
        case edits
        case newInterface
        case screen
        case omitted
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch projection {
        case .noChange(let metadata):
            try encodeMetadata(metadata, kind: .noChange, to: &container)
            try encodeTransientOmissions(metadata.transient, to: &container)

        case .elementsChanged(let delta):
            try encodeMetadata(delta.metadata, kind: .elementsChanged, to: &container)
            let edits = PublicElementEdits(projection: delta.edits)
            try container.encodeIfPresent(edits.isEmpty ? nil : edits, forKey: .edits)
            try encodeTransientOmissions(delta.metadata.transient, to: &container)

        case .screenChanged(let delta):
            try encodeMetadata(delta.metadata, kind: .screenChanged, to: &container)
            switch screenPolicy {
            case .newInterface:
                try container.encodeIfPresent(
                    delta.screen.interface,
                    forKey: .newInterface
                )
            case .screenSummary:
                try container.encode(PublicHeistScreenProjection(projection: delta.screen), forKey: .screen)
            }
            try encodeTransientOmissions(delta.metadata.transient, to: &container)
        }
    }

    private func encodeMetadata(
        _ metadata: DeltaProjectionMetadata,
        kind: DeltaProjectionKind,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(metadata.elementCount, forKey: .elementCount)
        try container.encodeIfPresent(metadata.captureEdge, forKey: .captureEdge)
        try container.encodeIfPresent(metadata.interactionDigest, forKey: .interactionDigest)
        if !metadata.accessibilityNotifications.isEmpty {
            try container.encode(metadata.accessibilityNotifications, forKey: .accessibilityNotifications)
        }
        try container.encodeIfPresent(Self.elements(metadata.transient.elements), forKey: .transient)
    }

    private func encodeTransientOmissions(
        _ transient: ElementProjectionBucket,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        let transientOmissions = PublicHeistDeltaOmissions(projection: transient)
        try container.encodeIfPresent(transientOmissions.isEmpty ? nil : transientOmissions, forKey: .omitted)
    }

    private static func elements(_ elements: [HeistElement]) -> [PublicElement]? {
        guard !elements.isEmpty else { return nil }
        return elements.map { PublicElement(element: $0, detail: .summary) }
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
        self.added = projection.added.elements.isEmpty
            ? nil
            : projection.added.elements.map { PublicElement(element: $0, detail: .summary) }
        self.removed = projection.removed.elements.isEmpty
            ? nil
            : projection.removed.elements.map { PublicElement(element: $0, detail: .summary) }
        self.updated = projection.updated.updates.isEmpty
            ? nil
            : projection.updated.updates.compactMap(PublicElementUpdate.init(update:))
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

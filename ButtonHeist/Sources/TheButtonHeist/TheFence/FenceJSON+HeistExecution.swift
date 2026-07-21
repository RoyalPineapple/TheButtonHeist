import Foundation
import ThePlans

import AccessibilitySnapshotModel
import TheScore

private enum PublicHeistExecutionResponseKey: String, CodingKey {
    case status, report
}

/// The sole public JSON projection of the canonical `HeistReport`.
struct PublicHeistExecutionResponse: Encodable {
    private let report: HeistReport
    private let profile: ProjectionProfile

    init(report: HeistReport, profile: ProjectionProfile) {
        self.report = report
        self.profile = profile.heistReport
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PublicHeistExecutionResponseKey.self)
        try container.encode(report.failure == nil ? PublicResponseStatus.ok : .partial, forKey: .status)
        try container.encode(PublicHeistReportJSON(report: report, profile: profile), forKey: .report)
    }
}

private struct PublicHeistReportJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case summary, metrics, nodes, netDelta
    }

    let report: HeistReport
    let profile: ProjectionProfile

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(PublicHeistReportSummaryJSON(summary: report.summary), forKey: .summary)
        try container.encode(report.metrics, forKey: .metrics)
        try container.encode(
            report.nodes.map { PublicHeistReportNodeJSON(node: $0, profile: profile) },
            forKey: .nodes
        )
        guard case .changed(let trace) = report.accessibilityChange,
              let delta = DeltaProjection(
                  trace: trace,
                  isComplete: true,
                  profile: profile,
                  includeScreenInterface: true
              ) else { return }
        try container.encode(
            PublicDelta(projection: delta, screenPolicy: .screenSummary),
            forKey: .netDelta
        )
    }
}

private struct PublicHeistReportSummaryJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case executedTopLevelStepCount, executedNodeCount, outputNodeCount, abortedAtPath, durationMs, expectations
    }

    let summary: HeistReport.Summary

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summary.executedTopLevelStepCount, forKey: .executedTopLevelStepCount)
        try container.encode(summary.executedNodeCount, forKey: .executedNodeCount)
        try container.encode(summary.outputNodeCount, forKey: .outputNodeCount)
        try container.encodeIfPresent(summary.abortedAtPath?.description, forKey: .abortedAtPath)
        try container.encode(summary.durationMs, forKey: .durationMs)
        try container.encodeIfPresent(
            summary.expectations.map(PublicHeistExpectationSummaryJSON.init),
            forKey: .expectations
        )
    }
}

private struct PublicHeistExpectationSummaryJSON: Encodable {
    let checked: Int
    let met: Int
    let allMet: Bool

    init(_ summary: HeistReport.Expectations) {
        self.checked = summary.checked
        self.met = summary.met
        self.allMet = summary.allMet
    }
}

private struct PublicHeistReportNodeJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case path, kind, capability, status, message, durationMs, evidence, failure
        case abortedAtChildPath, expectation, children
    }

    let node: HeistReport.Node
    let profile: ProjectionProfile

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(node.path.description, forKey: .path)
        try container.encode(node.kind.rawValue, forKey: .kind)
        try container.encodeIfPresent(node.capability?.description, forKey: .capability)
        try container.encode(node.status.rawValue, forKey: .status)
        try container.encodeIfPresent(node.message, forKey: .message)
        try container.encode(node.durationMs, forKey: .durationMs)
        if let evidence = node.evidence {
            try container.encode(
                PublicHeistReportEvidenceJSON(
                    evidence: evidence,
                    continuity: node.continuity,
                    profile: profile
                ),
                forKey: .evidence
            )
        }
        if let failure = node.failure {
            try container.encode(PublicHeistReportFailureJSON(failure: failure), forKey: .failure)
        }
        try container.encodeIfPresent(node.abortedAtChildPath?.description, forKey: .abortedAtChildPath)
        try container.encodeIfPresent(
            node.expectation.map { PublicExpectationResult(projection: ExpectationProjection(result: $0)) },
            forKey: .expectation
        )
        try container.encode(
            node.children.map { PublicHeistReportNodeJSON(node: $0, profile: profile) },
            forKey: .children
        )
    }
}

private struct PublicHeistReportFailureJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case category, contract, observed, expected, code, kind, phase, retryable, hint
    }

    let failure: HeistReport.Failure

    func encode(to encoder: Encoder) throws {
        let diagnostic = failure.actionKind.map {
            DiagnosticFailureMapper.map(failureKind: $0, message: failure.diagnosticMessage)
        } ?? DiagnosticFailureMapper.map(
            reportFailure: failure.detail,
            message: failure.diagnosticMessage
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(failure.detail.category, forKey: .category)
        try container.encode(failure.detail.contract, forKey: .contract)
        try container.encode(failure.detail.observed, forKey: .observed)
        try container.encodeIfPresent(failure.detail.expected, forKey: .expected)
        try container.encode(diagnostic.code, forKey: .code)
        try container.encode(diagnostic.kind.rawValue, forKey: .kind)
        try container.encode(diagnostic.phase.rawValue, forKey: .phase)
        try container.encode(diagnostic.retryable, forKey: .retryable)
        try container.encodeIfPresent(diagnostic.hint, forKey: .hint)
    }
}

struct PublicHeistActionResultOmissions: Encodable {
    let accessibilityTrace: PublicProjectionOmission?
    let subjectEvidence: PublicProjectionOmission?

    var isEmpty: Bool {
        accessibilityTrace == nil && subjectEvidence == nil
    }

    init(projection: ActionResultOmissionsProjection) {
        self.accessibilityTrace = projection.accessibilityTrace.map { PublicProjectionOmission(projection: $0) }
        self.subjectEvidence = projection.subjectEvidence.map { PublicProjectionOmission(projection: $0) }
    }
}

struct PublicProjectionOmission: Encodable {
    let reason: String
    let projectedAs: String?
    let omittedCount: Int?

    init(projection: ProjectionOmission) {
        self.reason = projection.reason.rawValue
        self.projectedAs = projection.projectedAs
        self.omittedCount = projection.omittedCount
    }
}

struct PublicHeistElementEditOmissions: Encodable {
    let added: Int?
    let removed: Int?
    let updated: Int?
    let addedKeys: [String]?
    let removedKeys: [String]?
    let updatedKeys: [String]?

    init(
        added: Int?,
        removed: Int?,
        updated: Int?,
        addedKeys: [String]?,
        removedKeys: [String]?,
        updatedKeys: [String]?
    ) {
        self.added = added
        self.removed = removed
        self.updated = updated
        self.addedKeys = addedKeys
        self.removedKeys = removedKeys
        self.updatedKeys = updatedKeys
    }

    init(projection: DeltaEditsProjection) {
        self.init(
            added: projection.added.omittedCount,
            removed: projection.removed.omittedCount,
            updated: projection.updated.omittedCount,
            addedKeys: projection.added.omittedKeys,
            removedKeys: projection.removed.omittedKeys,
            updatedKeys: projection.updated.omittedKeys
        )
    }

    var isEmpty: Bool {
        added == nil
            && removed == nil
            && updated == nil
            && addedKeys == nil
            && removedKeys == nil
            && updatedKeys == nil
    }
}

struct PublicHeistDeltaOmissions: Encodable {
    let transient: Int?
    let transientKeys: [String]?

    init(projection: ElementProjectionBucket) {
        self.transient = projection.omittedCount
        self.transientKeys = projection.omittedKeys
    }

    var isEmpty: Bool {
        transient == nil && transientKeys == nil
    }
}

struct PublicHeistScreenProjection: Encodable {
    let screenDescription: String
    let screenId: String?
    let elementCount: Int
    let elements: [PublicElement]?
    let omittedElementCount: Int?

    init(projection: DeltaScreenProjection) {
        self.screenDescription = projection.screenDescription
        self.screenId = projection.screenId
        self.elementCount = projection.elementCount
        self.elements = projection.elements.isEmpty
            ? nil
            : projection.elements.map { PublicElement(element: $0, detail: .summary) }
        self.omittedElementCount = projection.omittedElementCount
    }
}

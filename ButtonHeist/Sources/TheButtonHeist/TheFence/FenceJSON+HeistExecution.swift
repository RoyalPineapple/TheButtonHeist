import Foundation
import ThePlans

import AccessibilitySnapshotModel
import TheScore

private enum PublicHeistExecutionResponseKey: String, CodingKey {
    case status, report
}

private enum PublicHeistReportCodingKey: String, CodingKey {
    case summary, metrics, nodes, netDelta
}

private enum PublicHeistReportSummaryCodingKey: String, CodingKey {
    case executedTopLevelStepCount, executedNodeCount, outputNodeCount, abortedAtPath, durationMs, expectations
}

private enum PublicHeistExpectationSummaryCodingKey: String, CodingKey {
    case checked, met, allMet
}

private enum PublicHeistReportNodeCodingKey: String, CodingKey {
    case path, kind, capability, status, message, durationMs, evidence, failure
    case abortedAtChildPath, expectation, settlement, children
}

private enum PublicHeistReportFailureCodingKey: String, CodingKey {
    case category, contract, observed, expected, code, kind, phase, retryable, hint
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
        try encodeReport(to: container.superEncoder(forKey: .report))
    }

    private func encodeReport(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PublicHeistReportCodingKey.self)
        try encode(report.summary, to: container.superEncoder(forKey: .summary))
        try container.encode(report.metrics, forKey: .metrics)
        var nodes = container.nestedUnkeyedContainer(forKey: .nodes)
        for node in report.nodes {
            try encode(node, to: nodes.superEncoder())
        }
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

    private func encode(_ summary: HeistReport.Summary, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PublicHeistReportSummaryCodingKey.self)
        try container.encode(summary.executedTopLevelStepCount, forKey: .executedTopLevelStepCount)
        try container.encode(summary.executedNodeCount, forKey: .executedNodeCount)
        try container.encode(summary.outputNodeCount, forKey: .outputNodeCount)
        try container.encodeIfPresent(summary.abortedAtPath?.description, forKey: .abortedAtPath)
        try container.encode(summary.durationMs, forKey: .durationMs)
        if let expectations = summary.expectations {
            try encode(expectations, to: container.superEncoder(forKey: .expectations))
        }
    }

    private func encode(_ summary: HeistReport.Expectations, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PublicHeistExpectationSummaryCodingKey.self)
        try container.encode(summary.checked, forKey: .checked)
        try container.encode(summary.met, forKey: .met)
        try container.encode(summary.allMet, forKey: .allMet)
    }

    private func encode(_ node: HeistReport.Node, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PublicHeistReportNodeCodingKey.self)
        try container.encode(node.path.description, forKey: .path)
        try container.encode(node.kind.rawValue, forKey: .kind)
        try container.encodeIfPresent(node.capability?.description, forKey: .capability)
        try container.encode(node.status.rawValue, forKey: .status)
        try container.encodeIfPresent(node.message, forKey: .message)
        try container.encode(node.durationMs, forKey: .durationMs)
        if let evidence = node.evidence {
            try container.encode(PublicHeistReportEvidenceJSON(evidence: evidence, profile: profile), forKey: .evidence)
        }
        if let failure = node.failure {
            try encode(failure, to: container.superEncoder(forKey: .failure))
        }
        try container.encodeIfPresent(node.abortedAtChildPath?.description, forKey: .abortedAtChildPath)
        try container.encodeIfPresent(
            node.expectation.map { ExpectationProjection(result: $0) },
            forKey: .expectation
        )
        if node.settlement?.settled == false {
            try container.encodeIfPresent(node.settlement, forKey: .settlement)
        }
        var children = container.nestedUnkeyedContainer(forKey: .children)
        for child in node.children {
            try encode(child, to: children.superEncoder())
        }
    }

    private func encode(_ failure: HeistReport.Failure, to encoder: Encoder) throws {
        let diagnostic = failure.actionKind.map {
            DiagnosticFailure(failureKind: $0, message: failure.diagnosticMessage)
        } ?? DiagnosticFailure(
            reportFailure: failure.detail,
            message: failure.diagnosticMessage
        )
        var container = encoder.container(keyedBy: PublicHeistReportFailureCodingKey.self)
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

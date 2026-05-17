import Foundation

// MARK: - Accessibility Change Journal

public struct AccessibilityChangeJournal: Codable, Sendable, Equatable {
    public let changes: [AccessibilityChange]

    public init(changes: [AccessibilityChange]) {
        self.changes = changes
    }

    public init(backgroundDelta: InterfaceDelta, sequence: Int = 1) {
        self.init(changes: [AccessibilityChange(sequence: sequence, delta: backgroundDelta)])
    }
}

public struct AccessibilityChange: Codable, Sendable, Equatable {
    public let sequence: Int
    public let kind: AccessibilityChangeKind
    public let summary: String
    public let samples: [AccessibilityChangeSample]
    public let omittedCount: Int?

    public init(
        sequence: Int,
        kind: AccessibilityChangeKind,
        summary: String,
        samples: [AccessibilityChangeSample] = [],
        omittedCount: Int? = nil
    ) {
        self.sequence = sequence
        self.kind = kind
        self.summary = summary
        self.samples = samples
        self.omittedCount = omittedCount
    }

    public init(sequence: Int, delta: InterfaceDelta) {
        let receipt = Self.receiptPayload(for: delta)
        self.init(
            sequence: sequence,
            kind: AccessibilityChangeKind(delta),
            summary: receipt.summary,
            samples: receipt.samples,
            omittedCount: receipt.omittedCount
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sequence
        case kind
        case summary
        case samples
        case omittedCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sequence = try container.decode(Int.self, forKey: .sequence)
        kind = try container.decode(AccessibilityChangeKind.self, forKey: .kind)
        summary = try container.decode(String.self, forKey: .summary)
        samples = try container.decodeIfPresent([AccessibilityChangeSample].self, forKey: .samples) ?? []
        omittedCount = try container.decodeIfPresent(Int.self, forKey: .omittedCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(kind, forKey: .kind)
        try container.encode(summary, forKey: .summary)
        if !samples.isEmpty {
            try container.encode(samples, forKey: .samples)
        }
        try container.encodeIfPresent(omittedCount, forKey: .omittedCount)
    }
}

public enum AccessibilityChangeKind: String, Codable, Sendable, Equatable {
    case noChange
    case elementsChanged
    case screenChanged

    public init(_ delta: InterfaceDelta) {
        switch delta {
        case .noChange:
            self = .noChange
        case .elementsChanged:
            self = .elementsChanged
        case .screenChanged:
            self = .screenChanged
        }
    }
}

public struct AccessibilityChangeSample: Codable, Sendable, Equatable {
    public let heistId: String?
    public let summary: String

    public init(heistId: String? = nil, summary: String) {
        self.heistId = heistId
        self.summary = summary
    }
}

// MARK: - Delta Conversion

private extension AccessibilityChange {
    static let maxSamples = 5
    static let maxSummaryLength = 120
    static let maxSampleLength = 80

    typealias ReceiptPayload = (
        summary: String,
        samples: [AccessibilityChangeSample],
        omittedCount: Int?
    )

    static func receiptPayload(for delta: InterfaceDelta) -> ReceiptPayload {
        switch delta {
        case .noChange(let payload):
            let transientPart = payload.transient.isEmpty ? "" : "; transient\(payload.transient.count)"
            let summary = "no change (\(payload.elementCount) elements\(transientPart))"
            return limitedPayload(summary: summary, candidates: transientSamples(payload.transient))

        case .elementsChanged(let payload):
            let parts = editCountParts(payload.edits, transientCount: payload.transient.count)
            let detail = parts.isEmpty ? "" : "; " + parts.joined(separator: " ")
            let summary = "elements changed (\(payload.elementCount) elements\(detail))"
            return limitedPayload(
                summary: summary,
                candidates: editSamples(payload.edits) + transientSamples(payload.transient)
            )

        case .screenChanged(let payload):
            var parts = ["\(payload.elementCount) elements"]
            if let screenDescription = screenDescription(payload.newInterface, elementCount: payload.elementCount) {
                parts.insert(screenDescription, at: 0)
            }
            if let postEdits = payload.postEdits {
                parts.append(contentsOf: editCountParts(postEdits, transientCount: 0))
            }
            if !payload.transient.isEmpty {
                parts.append("transient\(payload.transient.count)")
            }
            let summary = "screen changed (" + parts.joined(separator: "; ") + ")"
            let postSamples = payload.postEdits.map(editSamples) ?? []
            return limitedPayload(
                summary: summary,
                candidates: postSamples + transientSamples(payload.transient)
            )
        }
    }

    static func limitedPayload(
        summary: String,
        candidates: [AccessibilityChangeSample]
    ) -> ReceiptPayload {
        let samples = Array(candidates.prefix(maxSamples))
        let omitted = candidates.count > samples.count ? candidates.count - samples.count : nil
        return (truncate(summary, to: maxSummaryLength), samples, omitted)
    }

    static func editCountParts(_ edits: ElementEdits, transientCount: Int) -> [String] {
        var parts: [String] = []
        if !edits.added.isEmpty { parts.append("+\(edits.added.count)") }
        if !edits.removed.isEmpty { parts.append("-\(edits.removed.count)") }
        if !edits.updated.isEmpty { parts.append("~\(edits.updated.count)") }
        if !edits.treeInserted.isEmpty { parts.append("tree+\(edits.treeInserted.count)") }
        if !edits.treeRemoved.isEmpty { parts.append("tree-\(edits.treeRemoved.count)") }
        if !edits.treeMoved.isEmpty { parts.append("move\(edits.treeMoved.count)") }
        if transientCount > 0 { parts.append("transient\(transientCount)") }
        return parts
    }

    static func editSamples(_ edits: ElementEdits) -> [AccessibilityChangeSample] {
        var samples: [AccessibilityChangeSample] = []
        samples.append(contentsOf: edits.added.map { element in
            AccessibilityChangeSample(
                heistId: element.heistId,
                summary: "added \(elementSummary(element))"
            )
        })
        samples.append(contentsOf: edits.removed.map { heistId in
            AccessibilityChangeSample(heistId: heistId, summary: "removed \(heistId)")
        })
        samples.append(contentsOf: edits.updated.map { update in
            AccessibilityChangeSample(
                heistId: update.heistId,
                summary: "updated \(propertySummary(update.changes))"
            )
        })
        samples.append(contentsOf: edits.treeInserted.map { insertion in
            AccessibilityChangeSample(
                heistId: nodeId(insertion.node),
                summary: "tree inserted at \(locationSummary(insertion.location))"
            )
        })
        samples.append(contentsOf: edits.treeRemoved.map { removal in
            AccessibilityChangeSample(
                heistId: removal.ref.id,
                summary: "tree removed from \(locationSummary(removal.location))"
            )
        })
        samples.append(contentsOf: edits.treeMoved.map { move in
            AccessibilityChangeSample(
                heistId: move.ref.id,
                summary: "tree moved \(locationSummary(move.from)) -> \(locationSummary(move.to))"
            )
        })
        return samples.map { sample in
            AccessibilityChangeSample(
                heistId: nonEmpty(sample.heistId),
                summary: truncate(sample.summary, to: maxSampleLength)
            )
        }
    }

    static func transientSamples(_ elements: [HeistElement]) -> [AccessibilityChangeSample] {
        elements.map { element in
            AccessibilityChangeSample(
                heistId: nonEmpty(element.heistId),
                summary: truncate("transient \(elementSummary(element))", to: maxSampleLength)
            )
        }
    }

    static func screenDescription(_ interface: Interface, elementCount: Int) -> String? {
        let fallback = "\(interface.elements.count) elements"
        let description = normalized(interface.screenDescription)
        guard let description, description != fallback else { return nil }
        if description == "\(elementCount) elements" { return nil }
        return truncate(description, to: 80)
    }

    static func elementSummary(_ element: HeistElement) -> String {
        let role = element.traits.first?.rawValue ?? nonEmpty(element.description) ?? "element"
        if let label = nonEmpty(element.label) {
            return truncate("\(role) \"\(label)\"", to: maxSampleLength)
        }
        if let value = nonEmpty(element.value) {
            return truncate("\(role) = \"\(value)\"", to: maxSampleLength)
        }
        return truncate(role, to: maxSampleLength)
    }

    static func propertySummary(_ changes: [PropertyChange]) -> String {
        let properties = changes.map(\.property.rawValue).sorted()
        guard !properties.isEmpty else { return "element" }
        return properties.joined(separator: ",")
    }

    static func nodeId(_ node: InterfaceNode) -> String? {
        switch node {
        case .element(let element):
            return nonEmpty(element.heistId)
        case .container(let info, _):
            return nonEmpty(info.stableId)
        }
    }

    static func locationSummary(_ location: TreeLocation) -> String {
        let parent = location.parentId.flatMap(nonEmpty) ?? "root"
        return "\(parent)[\(location.index)]"
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let normalized = normalized(value), !normalized.isEmpty else { return nil }
        return normalized
    }

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func truncate(_ value: String, to limit: Int) -> String {
        guard limit > 3, value.count > limit else { return value }
        return String(value.prefix(limit - 3)) + "..."
    }
}

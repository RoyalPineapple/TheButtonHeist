import ThePlans
import Foundation
import AccessibilitySnapshotModel

/// Same-screen element edits projected from two interfaces.
public struct ElementEdits: Codable, Sendable, Equatable {
    public let added: [HeistElement]
    public let removed: [HeistElement]
    public let updated: [ElementUpdate]

    public init(
        added: [HeistElement] = [],
        removed: [HeistElement] = [],
        updated: [ElementUpdate] = []
    ) {
        self.added = added
        self.removed = removed
        self.updated = updated
    }

    public var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && updated.isEmpty
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case added
        case removed
        case updated
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ElementEdits")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        added = try container.decodeIfPresent([HeistElement].self, forKey: .added) ?? []
        removed = try container.decodeIfPresent([HeistElement].self, forKey: .removed) ?? []
        updated = try container.decodeIfPresent([ElementUpdate].self, forKey: .updated) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !added.isEmpty {
            try container.encode(added, forKey: .added)
        }
        if !removed.isEmpty {
            try container.encode(removed, forKey: .removed)
        }
        if !updated.isEmpty {
            try container.encode(updated, forKey: .updated)
        }
    }
}

public extension ElementEdits {

    /// Compare two single-element hierarchies.
    static func between(_ before: HeistElement, _ after: HeistElement) -> ElementEdits {
        ElementEditProjection.projectElementEdits(beforeElements: [before], afterElements: [after])
    }

    /// Compare two flat root element lists.
    static func between(_ before: [HeistElement], _ after: [HeistElement]) -> ElementEdits {
        ElementEditProjection.projectElementEdits(beforeElements: before, afterElements: after)
    }

    /// Compare two full interfaces.
    static func between(_ before: Interface, _ after: Interface) -> ElementEdits {
        ElementEditProjection.projectElementEdits(
            beforeRecords: before.projectedElementRecords.map(ElementDiffRecord.init),
            afterRecords: after.projectedElementRecords.map(ElementDiffRecord.init)
        )
    }

    static func between(
        beforeElements: [HeistElement],
        afterElements: [HeistElement]
    ) -> ElementEdits {
        ElementEditProjection.projectElementEdits(
            beforeElements: beforeElements,
            afterElements: afterElements
        )
    }

}

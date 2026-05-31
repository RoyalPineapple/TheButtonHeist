import Foundation

// MARK: - Container Matching

/// Stable names for parser accessibility container categories.
public enum ContainerTypeName: String, Codable, CaseIterable, Sendable {
    case semanticGroup
    case list
    case landmark
    case dataTable
    case tabBar
    case scrollable
}

/// Exact selector for container nodes in an interface tree.
///
/// This is intentionally separate from `ElementMatcher`: elements and
/// containers have different identity fields and are matched in different tree
/// positions.
public struct ContainerMatcher: Codable, Sendable, Equatable {
    public let stableId: HeistContainer?
    public let type: ContainerTypeName?
    public let label: String?
    public let value: String?
    public let identifier: String?
    public let isModalBoundary: Bool?

    public init(
        stableId: HeistContainer? = nil,
        type: ContainerTypeName? = nil,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        isModalBoundary: Bool? = nil
    ) {
        self.stableId = stableId
        self.type = type
        self.label = label
        self.value = value
        self.identifier = identifier
        self.isModalBoundary = isModalBoundary
    }

    public var hasPredicates: Bool {
        stableId?.isEmpty == false || type != nil || label?.isEmpty == false ||
            value?.isEmpty == false || identifier?.isEmpty == false || isModalBoundary != nil
    }
}

extension ContainerMatcher: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("containerMatcher", [
            ScoreDescription.stringField("stableId", stableId),
            ScoreDescription.valueField("type", type),
            ScoreDescription.stringField("label", label),
            ScoreDescription.stringField("value", value),
            ScoreDescription.stringField("identifier", identifier),
            ScoreDescription.valueField("modal", isModalBoundary),
        ].compactMap { $0 })
    }
}

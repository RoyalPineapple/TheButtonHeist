import ThePlans
import Foundation

// MARK: - Container Matching

/// Canonical names for parser accessibility container categories.
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
    public let containerName: ContainerName?
    public let type: ContainerTypeName?
    public let label: String?
    public let value: String?
    public let identifier: String?
    public let isModalBoundary: Bool?

    public init(
        containerName: ContainerName? = nil,
        type: ContainerTypeName? = nil,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        isModalBoundary: Bool? = nil
    ) {
        self.containerName = containerName
        self.type = type
        self.label = label
        self.value = value
        self.identifier = identifier
        self.isModalBoundary = isModalBoundary
    }

    public var hasPredicates: Bool {
        containerName?.isEmpty == false || type != nil || label?.isEmpty == false ||
            value?.isEmpty == false || identifier?.isEmpty == false || isModalBoundary != nil
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case containerName
        case type
        case label
        case value
        case identifier
        case isModalBoundary
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "container matcher")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            containerName: try container.decodeIfPresent(ContainerName.self, forKey: .containerName),
            type: try container.decodeIfPresent(ContainerTypeName.self, forKey: .type),
            label: try container.decodeIfPresent(String.self, forKey: .label),
            value: try container.decodeIfPresent(String.self, forKey: .value),
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier),
            isModalBoundary: try container.decodeIfPresent(Bool.self, forKey: .isModalBoundary)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(containerName, forKey: .containerName)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(identifier, forKey: .identifier)
        try container.encodeIfPresent(isModalBoundary, forKey: .isModalBoundary)
    }
}

extension ContainerMatcher: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("containerMatcher", [
            ScoreDescription.stringField("containerName", containerName?.rawValue),
            ScoreDescription.valueField("type", type),
            ScoreDescription.stringField("label", label),
            ScoreDescription.stringField("value", value),
            ScoreDescription.stringField("identifier", identifier),
            ScoreDescription.valueField("modal", isModalBoundary),
        ].compactMap { $0 })
    }
}

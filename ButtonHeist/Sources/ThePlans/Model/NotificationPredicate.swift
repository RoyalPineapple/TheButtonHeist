import Foundation

/// What one published accessibility notification event must contain.
///
/// Text and element constraints, when present, are evaluated against the same
/// event. An empty predicate matches any published notification event.
public struct NotificationPredicate: Codable, Sendable, Equatable, Hashable {
    public let text: StringMatch?
    public let element: ElementPredicate?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case element
    }

    public init(
        text: StringMatch? = nil,
        element: ElementPredicate? = nil
    ) {
        self.text = text
        self.element = element
    }

    package func resolve(
        in environment: HeistExecutionEnvironment
    ) throws -> Execution {
        Execution(
            text: try text?.resolve(in: environment),
            element: try element?.resolve(in: environment)
        )
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "notification predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(StringMatch.self, forKey: .text)
        element = try container.decodeIfPresent(ElementPredicate.self, forKey: .element)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(element, forKey: .element)
    }

    package struct Execution: Sendable, Equatable, Hashable {
        package let text: ResolvedStringMatch?
        package let element: ResolvedElementPredicate?

        package init(
            text: ResolvedStringMatch?,
            element: ResolvedElementPredicate?
        ) {
            self.text = text
            self.element = element
        }
    }
}

extension NotificationPredicate: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("notification", [
            text.map { "text=\($0)" },
            element.map { "element=\($0)" },
        ].compactMap { $0 })
    }
}

extension NotificationPredicate.Execution: CustomStringConvertible {
    package var description: String {
        CanonicalValueDescription.call("notification", [
            text.map { "text=\($0)" },
            element.map { "element=\($0)" },
        ].compactMap { $0 })
    }
}

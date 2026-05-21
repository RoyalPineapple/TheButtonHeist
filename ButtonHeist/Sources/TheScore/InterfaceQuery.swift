import Foundation

public struct InterfaceQuery: Codable, Sendable, Equatable {
    public let subtree: SubtreeSelector?
    public let matcher: ElementMatcher
    public let elementIds: [String]?

    public init(
        subtree: SubtreeSelector? = nil,
        matcher: ElementMatcher = ElementMatcher(),
        elementIds: [String]? = nil
    ) {
        self.subtree = subtree
        self.matcher = matcher
        self.elementIds = elementIds
    }
}

extension InterfaceQuery: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("interfaceQuery", [
            subtree?.description,
            matcher.hasPredicates ? matcher.description : nil,
            ScoreDescription.quotedListField("elementIds", elementIds),
        ].compactMap { $0 })
    }
}

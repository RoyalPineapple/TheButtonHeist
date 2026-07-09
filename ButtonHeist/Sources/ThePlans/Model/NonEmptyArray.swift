import Foundation

/// A small collection wrapper for DSL constructs where an empty list would be
/// a malformed shape rather than an empty condition.
public struct NonEmptyArray<Element: Sendable>: Sendable {
    private let storage: [Element]

    public init(_ first: Element, _ rest: Element...) {
        self.storage = [first] + rest
    }

    public init(_ first: Element, rest: [Element]) {
        self.storage = [first] + rest
    }

    public var first: Element {
        storage[0]
    }

    public var rest: [Element] {
        Array(storage.dropFirst())
    }

    public var elements: [Element] {
        storage
    }

    public func mapNonEmpty<NewElement: Sendable>(
        _ transform: (Element) throws -> NewElement
    ) rethrows -> NonEmptyArray<NewElement> {
        try NonEmptyArray<NewElement>(
            transform(first),
            rest: rest.map(transform)
        )
    }
}

extension NonEmptyArray: RandomAccessCollection {
    public typealias Index = Array<Element>.Index

    public var startIndex: Index {
        storage.startIndex
    }

    public var endIndex: Index {
        storage.endIndex
    }

    public subscript(position: Index) -> Element {
        storage[position]
    }
}

extension NonEmptyArray: Equatable where Element: Equatable {}
extension NonEmptyArray: Hashable where Element: Hashable {}

extension NonEmptyArray: Codable where Element: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard !container.isAtEnd else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "non-empty array requires at least one element"
            ))
        }

        var values: [Element] = []
        while !container.isAtEnd {
            values.append(try container.decode(Element.self))
        }
        self.storage = values
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for element in storage {
            try container.encode(element)
        }
    }
}

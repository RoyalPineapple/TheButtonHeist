import Foundation

/// A small collection wrapper for DSL constructs where an empty list would be
/// a malformed shape rather than an empty condition.
package struct NonEmptyArray<Element: Sendable>: Sendable {
    private let storage: [Element]

    package init(_ first: Element, _ rest: Element...) {
        self.storage = [first] + rest
    }

    package init(_ first: Element, rest: [Element]) {
        self.storage = [first] + rest
    }

    package var first: Element {
        storage[0]
    }

    package var rest: [Element] {
        Array(storage.dropFirst())
    }

    package var elements: [Element] {
        storage
    }

    package func mapNonEmpty<NewElement: Sendable>(
        _ transform: (Element) throws -> NewElement
    ) rethrows -> NonEmptyArray<NewElement> {
        try NonEmptyArray<NewElement>(
            transform(first),
            rest: rest.map(transform)
        )
    }
}

extension NonEmptyArray: RandomAccessCollection {
    package typealias Index = Array<Element>.Index

    package var startIndex: Index {
        storage.startIndex
    }

    package var endIndex: Index {
        storage.endIndex
    }

    package subscript(position: Index) -> Element {
        storage[position]
    }
}

extension NonEmptyArray: Equatable where Element: Equatable {}
extension NonEmptyArray: Hashable where Element: Hashable {}

extension NonEmptyArray: Codable where Element: Codable {
    package init(from decoder: Decoder) throws {
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

    package func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for element in storage {
            try container.encode(element)
        }
    }
}

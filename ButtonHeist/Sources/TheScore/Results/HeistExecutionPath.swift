import Foundation

/// A canonical path to one node in a heist execution tree.
public struct HeistExecutionPath: Sendable, Equatable, Hashable, Codable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    private enum Component: Sendable, Equatable, Hashable {
        case field(Field)
        case index(Int)
    }

    private enum Field: String, Sendable, Equatable, Hashable, CaseIterable {
        case actions
        case body
        case cases
        case conditional
        case elseBody = "else_body"
        case failure
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
        case heist
        case invoke
        case iterations
        case repeatUntil = "repeat_until"
        case wait
    }

    private let components: [Component]

    private init(components: [Component]) {
        self.components = components
    }

    public init(validating description: String) throws {
        components = try Self.parse(description)
    }

    public init(stringLiteral value: String) {
        do {
            try self.init(validating: value)
        } catch {
            preconditionFailure(String(describing: error))
        }
    }

    public var description: String {
        components.reduce(into: "$") { result, component in
            switch component {
            case .field(let field):
                result += ".\(field.rawValue)"
            case .index(let index):
                result += "[\(index)]"
            }
        }
    }

    package static let body = Self(components: [.field(.body)])

    package func step(at index: Int) -> Self {
        appending(.index(index))
    }

    package func heistBody() -> Self {
        appending(.field(.heist), .field(.body))
    }

    package func invocationBody() -> Self {
        appending(.field(.invoke), .field(.body))
    }

    package func conditionalCaseBody(at index: Int) -> Self {
        appending(.field(.conditional), .field(.cases), .index(index), .field(.body))
    }

    package func conditionalElseBody() -> Self {
        appending(.field(.conditional), .field(.elseBody))
    }

    package func waitElseBody() -> Self {
        appending(.field(.wait), .field(.elseBody))
    }

    package func forEachElementIteration(at index: Int) -> Self {
        appending(.field(.forEachElement), .field(.iterations), .index(index))
    }

    package func forEachStringIteration(at index: Int) -> Self {
        appending(.field(.forEachString), .field(.iterations), .index(index))
    }

    package func repeatUntilIteration(at index: Int) -> Self {
        appending(.field(.repeatUntil), .field(.iterations), .index(index))
    }

    package func iterationBody() -> Self {
        appending(.field(.body))
    }

    package func repeatUntilElseBody() -> Self {
        appending(.field(.repeatUntil), .field(.elseBody))
    }

    package func failureAction(at index: Int) -> Self {
        appending(.field(.failure), .field(.actions), .index(index))
    }

    package func isDescendant(of ancestor: Self) -> Bool {
        components.count > ancestor.components.count
            && components.starts(with: ancestor.components)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let description = try container.decode(String.self)
        do {
            try self.init(validating: description)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "invalid heist execution path \(description): \(error)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private func appending(_ additions: Component...) -> Self {
        Self(components: components + additions)
    }

    private static func parse(_ description: String) throws -> [Component] {
        guard description.first == "$" else {
            throw ValidationError.missingRoot
        }

        var components: [Component] = []
        var index = description.index(after: description.startIndex)
        while index < description.endIndex {
            switch description[index] {
            case ".":
                index = description.index(after: index)
                let start = index
                while index < description.endIndex, description[index] != ".", description[index] != "[" {
                    index = description.index(after: index)
                }
                let name = String(description[start..<index])
                guard let field = Field(rawValue: name) else {
                    throw ValidationError.unknownField(name)
                }
                components.append(.field(field))
            case "[":
                index = description.index(after: index)
                let start = index
                while index < description.endIndex, description[index].isNumber {
                    index = description.index(after: index)
                }
                guard start < index,
                      index < description.endIndex,
                      description[index] == "]",
                      let value = Int(description[start..<index])
                else {
                    throw ValidationError.invalidIndex
                }
                components.append(.index(value))
                index = description.index(after: index)
            default:
                throw ValidationError.invalidSeparator
            }
        }
        return components
    }
}

private extension HeistExecutionPath {
    enum ValidationError: Error, CustomStringConvertible {
        case missingRoot
        case unknownField(String)
        case invalidIndex
        case invalidSeparator

        var description: String {
            switch self {
            case .missingRoot:
                return "path must start with $"
            case .unknownField(let field):
                return "unknown field \(field)"
            case .invalidIndex:
                return "indexes must be non-negative integers"
            case .invalidSeparator:
                return "components must start with . or ["
            }
        }
    }
}

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

    private enum ComponentPattern {
        case field(Field)
        case index(Int)
        case anyIndex
    }

    package enum ChildBranch: Sendable, Hashable {
        case waitElseBody
        case conditionalCase(Int)
        case conditionalElse
        case forEachElementIterations
        case forEachStringIterations
        case repeatUntilIterations
        case repeatUntilElse
        case body
        case heistBody
        case invocationBody
        case failureActions
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

    package func isRootStepPath() -> Bool {
        rootStepIndex != nil
    }

    package var rootStepIndex: Int? {
        guard components.count == 2,
              case .field(.body) = components[0],
              case .index(let index) = components[1]
        else { return nil }
        return index
    }

    package var failureActionAncestor: (path: Self, actionIndex: Int)? {
        guard components.count > 3,
              case .field(.failure) = components[components.count - 3],
              case .field(.actions) = components[components.count - 2],
              case .index(let actionIndex) = components[components.count - 1]
        else { return nil }
        return (
            Self(components: Array(components.dropLast(3))),
            actionIndex
        )
    }

    package func isLegalChild(
        of parent: HeistExecutionStepResult,
        child: HeistExecutionStepResult,
        childOrdinal: Int
    ) -> Bool {
        let regularChild = switch parent.kind {
        case .action, .warn, .fail:
            false
        case .wait:
            childSuffix(after: parent.path, matches: [.field(.wait), .field(.elseBody), .index(childOrdinal)])
        case .conditional:
            childSuffix(
                after: parent.path,
                matches: [.field(.conditional), .field(.cases), .anyIndex, .field(.body), .index(childOrdinal)]
            ) || childSuffix(after: parent.path, matches: [.field(.conditional), .field(.elseBody), .index(childOrdinal)])
        case .forEachElement:
            child.isForEachElementIteration
                && childSuffix(after: parent.path, matches: [.field(.forEachElement), .field(.iterations), .index(childOrdinal)])
        case .forEachString:
            child.isForEachStringIteration
                && childSuffix(after: parent.path, matches: [.field(.forEachString), .field(.iterations), .index(childOrdinal)])
        case .forEachIteration, .repeatUntilIteration:
            childSuffix(after: parent.path, matches: [.field(.body), .index(childOrdinal)])
        case .repeatUntil:
            (child.kind == .repeatUntilIteration
                && childSuffix(after: parent.path, matches: [.field(.repeatUntil), .field(.iterations), .index(childOrdinal)]))
                || childSuffix(after: parent.path, matches: [.field(.repeatUntil), .field(.elseBody), .index(childOrdinal)])
        case .heist:
            childSuffix(after: parent.path, matches: [.field(.heist), .field(.body), .index(childOrdinal)])
        case .invoke:
            childSuffix(after: parent.path, matches: [.field(.invoke), .field(.body), .index(childOrdinal)])
        }

        return regularChild || parent.status == .failed
            && child.kind == .action
            && childSuffix(after: parent.path, matches: [.field(.failure), .field(.actions), .index(childOrdinal)])
    }

    package func childBranch(after parent: Self) -> ChildBranch? {
        guard isDescendant(of: parent) else { return nil }
        let suffix = Array(components.dropFirst(parent.components.count))
        if Self.components(suffix, match: [.field(.wait), .field(.elseBody), .anyIndex]) {
            return .waitElseBody
        }
        if suffix.count == 5,
           case .field(.conditional) = suffix[0],
           case .field(.cases) = suffix[1],
           case .index(let caseIndex) = suffix[2],
           case .field(.body) = suffix[3],
           case .index = suffix[4] {
            return .conditionalCase(caseIndex)
        }
        if Self.components(suffix, match: [.field(.conditional), .field(.elseBody), .anyIndex]) {
            return .conditionalElse
        }
        if Self.components(suffix, match: [.field(.forEachElement), .field(.iterations), .anyIndex]) {
            return .forEachElementIterations
        }
        if Self.components(suffix, match: [.field(.forEachString), .field(.iterations), .anyIndex]) {
            return .forEachStringIterations
        }
        if Self.components(suffix, match: [.field(.repeatUntil), .field(.iterations), .anyIndex]) {
            return .repeatUntilIterations
        }
        if Self.components(suffix, match: [.field(.repeatUntil), .field(.elseBody), .anyIndex]) {
            return .repeatUntilElse
        }
        if Self.components(suffix, match: [.field(.body), .anyIndex]) {
            return .body
        }
        if Self.components(suffix, match: [.field(.heist), .field(.body), .anyIndex]) {
            return .heistBody
        }
        if Self.components(suffix, match: [.field(.invoke), .field(.body), .anyIndex]) {
            return .invocationBody
        }
        if Self.components(suffix, match: [.field(.failure), .field(.actions), .anyIndex]) {
            return .failureActions
        }
        return nil
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

    private func childSuffix(after parent: Self, matches patterns: [ComponentPattern]) -> Bool {
        isDescendant(of: parent)
            && Self.components(components.dropFirst(parent.components.count), match: patterns)
    }

    private func matches(_ patterns: [ComponentPattern]) -> Bool {
        Self.components(components, match: patterns)
    }

    private static func components<Components>(
        _ components: Components,
        match patterns: [ComponentPattern]
    ) -> Bool where Components: Collection, Components.Element == Component {
        components.count == patterns.count && zip(components, patterns).allSatisfy { component, pattern in
            switch (component, pattern) {
            case (.field(let componentField), .field(let patternField)):
                componentField == patternField
            case (.index(let componentIndex), .index(let patternIndex)):
                componentIndex == patternIndex
            case (.index, .anyIndex):
                true
            default:
                false
            }
        }
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

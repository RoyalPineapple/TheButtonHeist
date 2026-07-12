import Foundation

// MARK: - State Predicate Expressions

public enum StatePredicateExpr: Codable, Sendable, Equatable {
    case exists(ElementPredicateTemplate)
    case missing(ElementPredicateTemplate)
    case existsTarget(ElementTargetExpr)
    case missingTarget(ElementTargetExpr)
    case existsContainer(ContainerPredicateExpr)
    case missingContainer(ContainerPredicateExpr)
    case all(NonEmptyArray<StatePredicateExpr>)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, element, target, targetRef = "target_ref", container, states
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> AccessibilityPredicate.State {
        switch self {
        case .exists(let predicate):
            return .exists(try predicate.resolve(in: environment))
        case .missing(let predicate):
            return .missing(try predicate.resolve(in: environment))
        case .existsTarget(let target):
            return .existsTarget(try target.resolve(in: environment))
        case .missingTarget(let target):
            return .missingTarget(try target.resolve(in: environment))
        case .existsContainer(let container):
            return .existsContainer(try container.resolve(in: environment))
        case .missingContainer(let container):
            return .missingContainer(try container.resolve(in: environment))
        case .all(let states):
            return .all(try states.mapNonEmpty { try $0.resolve(in: environment) })
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = AccessibilityPredicateContract.StateWireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown state predicate type: \"\(typeString)\". Valid: \(AccessibilityPredicateContract.StateWireType.validDescription)"
            )
        }
        switch wireType {
        case .exists:
            self = try Self.decodeElementState(
                decoder,
                container,
                predicateState: Self.exists,
                targetState: Self.existsTarget,
                containerState: Self.existsContainer
            )
        case .missing:
            self = try Self.decodeElementState(
                decoder,
                container,
                predicateState: Self.missing,
                targetState: Self.missingTarget,
                containerState: Self.missingContainer
            )
        case .all:
            try decoder.rejectUnknownKeys(allowed: ["type", "states"], typeName: "all predicate expression")
            let states = try container.decode([StatePredicateExpr].self, forKey: .states)
            guard let first = states.first else {
                throw DecodingError.dataCorruptedError(
                    forKey: .states,
                    in: container,
                    debugDescription: "all predicate requires at least one child state"
                )
            }
            self = .all(NonEmptyArray(first, rest: Array(states.dropFirst())))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .exists(let predicate):
            try container.encode(AccessibilityPredicateContract.StateWireType.exists.rawValue, forKey: .type)
            try container.encode(predicate, forKey: .element)
        case .missing(let predicate):
            try container.encode(AccessibilityPredicateContract.StateWireType.missing.rawValue, forKey: .type)
            try container.encode(predicate, forKey: .element)
        case .existsTarget(let target):
            try container.encode(AccessibilityPredicateContract.StateWireType.exists.rawValue, forKey: .type)
            try Self.encode(target, into: &container)
        case .missingTarget(let target):
            try container.encode(AccessibilityPredicateContract.StateWireType.missing.rawValue, forKey: .type)
            try Self.encode(target, into: &container)
        case .existsContainer(let containerPredicate):
            try container.encode(AccessibilityPredicateContract.StateWireType.exists.rawValue, forKey: .type)
            try container.encode(containerPredicate, forKey: .container)
        case .missingContainer(let containerPredicate):
            try container.encode(AccessibilityPredicateContract.StateWireType.missing.rawValue, forKey: .type)
            try container.encode(containerPredicate, forKey: .container)
        case .all(let states):
            try container.encode(AccessibilityPredicateContract.StateWireType.all.rawValue, forKey: .type)
            try container.encode(states, forKey: .states)
        }
    }

    private static func decodeElementState(
        _ decoder: Decoder,
        _ container: KeyedDecodingContainer<CodingKeys>,
        predicateState: (ElementPredicateTemplate) -> Self,
        targetState: (ElementTargetExpr) -> Self,
        containerState: (ContainerPredicateExpr) -> Self
    ) throws -> Self {
        try decoder.rejectUnknownKeys(
            allowed: ["type", "element", "target", "target_ref", "container"],
            typeName: "state predicate expression"
        )
        let hasElement = container.contains(.element)
        let hasTarget = container.contains(.target)
        let hasTargetRef = container.contains(.targetRef)
        let hasContainer = container.contains(.container)
        let intentCount = [hasElement, hasTarget, hasTargetRef, hasContainer].filter { $0 }.count
        guard intentCount == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .element,
                in: container,
                debugDescription: "state predicate expression requires exactly one of element, target, target_ref, or container"
            )
        }
        if hasElement {
            return predicateState(try container.decode(ElementPredicateTemplate.self, forKey: .element))
        }
        if hasTarget {
            return targetState(try container.decode(ElementTargetExpr.self, forKey: .target))
        }
        if hasTargetRef {
            return targetState(.ref(try HeistReferenceName.decode(from: container, forKey: .targetRef)))
        }
        return containerState(try container.decode(ContainerPredicateExpr.self, forKey: .container))
    }

    private static func encode(
        _ target: ElementTargetExpr,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch target {
        case .target(let target):
            try container.encode(target, forKey: .target)
        case .predicate:
            try container.encode(target, forKey: .target)
        case .ref(let reference):
            try container.encode(reference, forKey: .targetRef)
        case .within:
            try container.encode(target, forKey: .target)
        }
    }
}

extension StatePredicateExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exists(let predicate): return ScoreDescription.call("exists", [predicate.description])
        case .missing(let predicate): return ScoreDescription.call("missing", [predicate.description])
        case .existsTarget(let target): return ScoreDescription.call("exists", [target.description])
        case .missingTarget(let target): return ScoreDescription.call("missing", [target.description])
        case .existsContainer(let container): return ScoreDescription.call("exists", [container.description])
        case .missingContainer(let container): return ScoreDescription.call("missing", [container.description])
        case .all(let states): return ScoreDescription.call("all", states.map(\.description))
        }
    }
}

public extension StatePredicateExpr {
    init(_ state: AccessibilityPredicate.State) {
        switch state {
        case .exists(let predicate):
            self = .exists(ElementPredicateTemplate(predicate))
        case .missing(let predicate):
            self = .missing(ElementPredicateTemplate(predicate))
        case .existsTarget(let target):
            self = .existsTarget(ElementTargetExpr(target))
        case .missingTarget(let target):
            self = .missingTarget(ElementTargetExpr(target))
        case .existsContainer(let container):
            self = .existsContainer(ContainerPredicateExpr(container))
        case .missingContainer(let container):
            self = .missingContainer(ContainerPredicateExpr(container))
        case .all(let states):
            self = .all(states.mapNonEmpty(StatePredicateExpr.init))
        }
    }
}

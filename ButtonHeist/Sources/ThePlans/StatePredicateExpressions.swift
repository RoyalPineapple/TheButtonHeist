import Foundation

// MARK: - State Predicate Expressions

public enum StatePredicateExpr: Codable, Sendable, Equatable {
    case present(ElementPredicateTemplate)
    case absent(ElementPredicateTemplate)
    case presentTarget(ElementTargetExpr)
    case absentTarget(ElementTargetExpr)
    case all([StatePredicateExpr])

    private enum WireType: String {
        case present, absent, all
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, element, target, targetRef = "target_ref", states
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> AccessibilityPredicate.State {
        switch self {
        case .present(let predicate):
            return .present(try predicate.resolve(in: environment))
        case .absent(let predicate):
            return .absent(try predicate.resolve(in: environment))
        case .presentTarget(let target):
            return .presentTarget(try target.resolve(in: environment))
        case .absentTarget(let target):
            return .absentTarget(try target.resolve(in: environment))
        case .all(let states):
            return .all(try states.map { try $0.resolve(in: environment) })
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown state predicate type: \"\(typeString)\". Valid: present, absent, all"
            )
        }
        switch wireType {
        case .present:
            self = try Self.decodeElementState(decoder, container, predicateState: Self.present, targetState: Self.presentTarget)
        case .absent:
            self = try Self.decodeElementState(decoder, container, predicateState: Self.absent, targetState: Self.absentTarget)
        case .all:
            try decoder.rejectUnknownKeys(allowed: ["type", "states"], typeName: "all predicate expression")
            let states = try container.decode([StatePredicateExpr].self, forKey: .states)
            guard !states.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .states,
                    in: container,
                    debugDescription: "all predicate requires at least one child state"
                )
            }
            self = .all(states)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .present(let predicate):
            try container.encode(WireType.present.rawValue, forKey: .type)
            try container.encode(predicate, forKey: .element)
        case .absent(let predicate):
            try container.encode(WireType.absent.rawValue, forKey: .type)
            try container.encode(predicate, forKey: .element)
        case .presentTarget(let target):
            try container.encode(WireType.present.rawValue, forKey: .type)
            try Self.encode(target, into: &container)
        case .absentTarget(let target):
            try container.encode(WireType.absent.rawValue, forKey: .type)
            try Self.encode(target, into: &container)
        case .all(let states):
            try container.encode(WireType.all.rawValue, forKey: .type)
            try container.encode(states, forKey: .states)
        }
    }

    private static func decodeElementState(
        _ decoder: Decoder,
        _ container: KeyedDecodingContainer<CodingKeys>,
        predicateState: (ElementPredicateTemplate) -> Self,
        targetState: (ElementTargetExpr) -> Self
    ) throws -> Self {
        try decoder.rejectUnknownKeys(
            allowed: ["type", "element", "target", "target_ref"],
            typeName: "state predicate expression"
        )
        let hasElement = container.contains(.element)
        let hasTarget = container.contains(.target)
        let hasTargetRef = container.contains(.targetRef)
        let intentCount = [hasElement, hasTarget, hasTargetRef].filter { $0 }.count
        guard intentCount == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .element,
                in: container,
                debugDescription: "state predicate expression requires exactly one of element, target, or target_ref"
            )
        }
        if hasElement {
            return predicateState(try container.decode(ElementPredicateTemplate.self, forKey: .element))
        }
        if hasTarget {
            return targetState(try container.decode(ElementTargetExpr.self, forKey: .target))
        }
        return targetState(.ref(try HeistReferenceName.decode(from: container, forKey: .targetRef)))
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
        }
    }
}

extension StatePredicateExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .present(let predicate): return ScoreDescription.call("present", [predicate.description])
        case .absent(let predicate): return ScoreDescription.call("absent", [predicate.description])
        case .presentTarget(let target): return ScoreDescription.call("present", [target.description])
        case .absentTarget(let target): return ScoreDescription.call("absent", [target.description])
        case .all(let states): return ScoreDescription.call("all", states.map(\.description))
        }
    }
}

public extension StatePredicateExpr {
    init(_ state: AccessibilityPredicate.State) {
        switch state {
        case .present(let predicate):
            self = .present(ElementPredicateTemplate(predicate))
        case .absent(let predicate):
            self = .absent(ElementPredicateTemplate(predicate))
        case .presentTarget(let target):
            self = .presentTarget(ElementTargetExpr(target))
        case .absentTarget(let target):
            self = .absentTarget(ElementTargetExpr(target))
        case .all(let states):
            self = .all(states.map(StatePredicateExpr.init))
        }
    }
}

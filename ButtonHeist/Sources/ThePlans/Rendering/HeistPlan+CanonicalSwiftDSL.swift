import Foundation

public enum HeistCanonicalSwiftDSLError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedAction(String)
    case unsupportedPredicate(String)
    case unresolvedTargetReference(String)
    case unresolvedStringReference(String)

    public var description: String {
        switch self {
        case .unsupportedAction(let action):
            return "unsupported canonical Swift DSL action: \(action)"
        case .unsupportedPredicate(let predicate):
            return "unsupported canonical Swift DSL predicate: \(predicate)"
        case .unresolvedTargetReference(let reference):
            return "unresolved canonical Swift target reference: \(reference)"
        case .unresolvedStringReference(let reference):
            return "unresolved canonical Swift string reference: \(reference)"
        }
    }
}

public extension HeistPlan {
    func canonicalSwiftDSL() throws -> String {
        try HeistCanonicalSwiftDSLRenderer().render(self)
    }
}

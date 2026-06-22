import Foundation

public enum HeistCanonicalSwiftDSLError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedAction(String)
    case unresolvedTargetReference(String)
    case unresolvedStringReference(String)
    case invalidParameter(String)

    public var description: String {
        switch self {
        case .unsupportedAction(let action):
            return "unsupported canonical Swift DSL action: \(action)"
        case .unresolvedTargetReference(let reference):
            return "unresolved canonical Swift target reference: \(reference)"
        case .unresolvedStringReference(let reference):
            return "unresolved canonical Swift string reference: \(reference)"
        case .invalidParameter(let parameter):
            return "invalid canonical Swift DSL parameter: \(parameter)"
        }
    }
}

public extension HeistPlan {
    func canonicalSwiftDSL() throws -> String {
        try HeistCanonicalSwiftDSLRenderer().render(self)
    }
}

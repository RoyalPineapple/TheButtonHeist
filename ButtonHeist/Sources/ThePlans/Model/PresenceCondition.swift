import Foundation

/// A branch condition: is this element on screen right now?
///
/// This is not an expectation and nothing waits on it. `If` and `Case` ask it
/// once, against the tree as it is, and take a branch. It carries no notion of
/// change, of a boundary, or of before and after — those belong to
/// `AccessibilityPredicate`, which is what an `expect` takes.
///
/// It used to be spelled `ChangeDeclaration.ScreenAssertion`, which said
/// "screen" for something that only ever asked about an element and never
/// consulted a screen at all.
public enum PresenceCondition: Codable, Sendable, Equatable {
    case exists(AccessibilityTarget)
    case missing(AccessibilityTarget)

    package var rootPredicate: AccessibilityPredicate {
        switch self {
        case .exists(let target): return .exists(target)
        case .missing(let target): return .missing(target)
        }
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedPresenceCondition {
        switch self {
        case .exists(let target): return .exists(try target.resolve(in: environment))
        case .missing(let target): return .missing(try target.resolve(in: environment))
        }
    }
}

extension PresenceCondition: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exists(let target): return CanonicalValueDescription.call("exists", [target.description])
        case .missing(let target): return CanonicalValueDescription.call("missing", [target.description])
        }
    }
}

package enum ResolvedPresenceCondition: Sendable, Equatable {
    case exists(ResolvedAccessibilityTarget)
    case missing(ResolvedAccessibilityTarget)

    package var rootPredicate: ResolvedAccessibilityPredicate {
        switch self {
        case .exists(let target): return .exists(target)
        case .missing(let target): return .missing(target)
        }
    }
}

extension ResolvedPresenceCondition: CustomStringConvertible {
    package var description: String {
        switch self {
        case .exists(let target): return CanonicalValueDescription.call("exists", [target.description])
        case .missing(let target): return CanonicalValueDescription.call("missing", [target.description])
        }
    }
}

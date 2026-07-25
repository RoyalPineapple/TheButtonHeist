import Foundation

/// What a caller asks of a screen boundary.
///
/// A screen boundary is a tick like any other, so it takes a predicate like any
/// other. This one reads screen facts — the identity the run was on and the one
/// it arrived at — and never a tree. Which elements left and which arrived are
/// element questions, answered by the snapshots on either side of the boundary.
///
/// An empty predicate matches any boundary: `changed(.screen())` asks only that
/// a screen change happened, the same way `announcement` with no match asks only
/// that something was spoken.
public struct ScreenPredicate: Codable, Sendable, Equatable, Hashable {
    /// The screen arrived at. Nil asks nothing of it.
    public let match: StringMatch?

    private enum CodingKeys: String, CodingKey, CaseIterable { case match }

    public init(match: StringMatch? = nil) {
        self.match = match
    }

    public init(_ name: String) {
        self.init(match: .exact(name))
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedScreenPredicate {
        ResolvedScreenPredicate(match: try match?.resolve(in: environment))
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "screen predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        match = try container.decodeIfPresent(StringMatch.self, forKey: .match)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(match, forKey: .match)
    }
}

extension ScreenPredicate: CustomStringConvertible {
    public var description: String {
        guard let match else { return "the screen to change" }
        return "the screen to change to \(match)"
    }
}

/// The facts a screen boundary carries.
///
/// Identity only: no tree, which is what keeps an element question out of this
/// lane. Both sides are named because a boundary is a crossing, and which screen
/// was left is as much a fact about it as which was arrived at.
public struct ScreenFacts: Sendable, Equatable {
    public let idBefore: String?
    public let idAfter: String?

    public init(idBefore: String?, idAfter: String?) {
        self.idBefore = idBefore
        self.idAfter = idAfter
    }
}

package struct ResolvedScreenPredicate: Sendable, Equatable {
    package let match: ResolvedStringMatch?

    package init(match: ResolvedStringMatch?) {
        self.match = match
    }

    /// Whether this boundary is the one the caller asked for.
    ///
    /// With no match, any boundary answers: the question was whether a screen
    /// changed at all.
    package func matches(_ facts: ScreenFacts) -> Bool {
        guard let match else { return true }
        guard let idAfter = facts.idAfter else { return false }
        return match.matches(idAfter)
    }
}

extension ResolvedScreenPredicate: CustomStringConvertible {
    package var description: String {
        guard let match else { return "the screen to change" }
        return "the screen to change to \(match)"
    }
}

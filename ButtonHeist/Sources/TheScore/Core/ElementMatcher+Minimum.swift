import ThePlans
import Foundation

// MARK: - Minimum Predicate Selection

public enum CandidateTier: Int, Sendable, Equatable, Comparable {
    case identityOnly
    case identityWithState
    case stateOnly
    case ordinalDisambiguation

    public static func < (lhs: CandidateTier, rhs: CandidateTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct MatcherAtom: Sendable, Equatable {
    public let predicate: ResolvedElementPredicate
    public let stability: AccessibilityFactStability
    public let priority: Int

    public init(
        predicate: ResolvedElementPredicate,
        stability: AccessibilityFactStability,
        priority: Int
    ) {
        self.predicate = predicate
        self.stability = stability
        self.priority = priority
    }
}

private struct MatcherAtomSortKey: Sendable, Equatable, Comparable {
    let priority: Int
    let predicateDescription: String

    static func < (lhs: MatcherAtomSortKey, rhs: MatcherAtomSortKey) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.predicateDescription < rhs.predicateDescription
    }
}

private extension MatcherAtom {
    var sortKey: MatcherAtomSortKey {
        MatcherAtomSortKey(
            priority: priority,
            predicateDescription: predicate.description
        )
    }
}

package protocol PredicateSelectionSubject: ElementPredicateSubject {
    var predicateMatcherFacts: [AccessibilityMatcherFact] { get }
}

package struct PredicateSelectionSubjectElement<Subject: PredicateSelectionSubject>: ElementPredicateSubjectBacked {
    package let id: PredicateSelectionElementId
    package let element: Subject

    package init(id: PredicateSelectionElementId, element: Subject) {
        self.id = id
        self.element = element
    }

    package var predicateSubject: Subject { element }
}

public struct PredicateCandidate: Sendable, Equatable {
    public let predicate: ResolvedElementPredicate
    public let atoms: [MatcherAtom]
    public let tier: CandidateTier

    public init(
        predicate: ResolvedElementPredicate,
        atoms: [MatcherAtom],
        tier: CandidateTier
    ) {
        self.predicate = predicate
        self.atoms = atoms
        self.tier = tier
    }
}

extension PredicateCandidate {
    struct Rank: Sendable, Equatable, Comparable {
        let tier: CandidateTier
        let atomCount: Int
        let atomPriorities: [Int]
        let predicateDescription: String

        static func < (lhs: Rank, rhs: Rank) -> Bool {
            if lhs.tier != rhs.tier {
                return lhs.tier < rhs.tier
            }
            if lhs.atomCount != rhs.atomCount {
                return lhs.atomCount < rhs.atomCount
            }
            if lhs.atomPriorities != rhs.atomPriorities {
                return lhs.atomPriorities.lexicographicallyPrecedes(rhs.atomPriorities)
            }
            return lhs.predicateDescription < rhs.predicateDescription
        }
    }

    struct OrdinalBaseRank: Sendable, Equatable, Comparable {
        let matchCount: Int
        let tier: CandidateTier
        let atomCount: Int
        let predicateDescription: String

        static func < (lhs: OrdinalBaseRank, rhs: OrdinalBaseRank) -> Bool {
            if lhs.matchCount != rhs.matchCount {
                return lhs.matchCount < rhs.matchCount
            }
            if lhs.tier != rhs.tier {
                return lhs.tier < rhs.tier
            }
            if lhs.atomCount != rhs.atomCount {
                return lhs.atomCount > rhs.atomCount
            }
            return lhs.predicateDescription < rhs.predicateDescription
        }
    }

    var rank: Rank {
        Rank(
            tier: tier,
            atomCount: atoms.count,
            atomPriorities: atoms.map(\.priority),
            predicateDescription: predicate.description
        )
    }

    func ordinalBaseRank(matchCount: Int) -> OrdinalBaseRank {
        OrdinalBaseRank(
            matchCount: matchCount,
            tier: tier,
            atomCount: atoms.count,
            predicateDescription: predicate.description
        )
    }
}

public struct PredicateSelectionElementId: RawRepresentable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: PredicateSelectionElementId, rhs: PredicateSelectionElementId) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct PredicateSelectionContext: Sendable, Equatable {
    public struct Element: Sendable, Equatable {
        public let id: PredicateSelectionElementId
        public let element: HeistElement

        public init(id: PredicateSelectionElementId, element: HeistElement) {
            self.id = id
            self.element = element
        }
    }

    public enum Scope: String, Sendable, Equatable {
        case visible
        case discovery
    }

    public let elements: [Element]
    public let screenId: String?
    public let semanticHash: String?
    public let scope: Scope

    public init(
        elements: [Element],
        screenId: String? = nil,
        semanticHash: String? = nil,
        scope: Scope = .visible
    ) {
        self.elements = elements
        self.screenId = screenId
        self.semanticHash = semanticHash
        self.scope = scope
    }
}

public struct MinimumPredicateSelection: Sendable, Equatable {
    public let contextElementId: PredicateSelectionElementId
    public let target: AccessibilityTarget
    public let candidate: PredicateCandidate

    public init(
        contextElementId: PredicateSelectionElementId,
        target: AccessibilityTarget,
        candidate: PredicateCandidate
    ) {
        self.contextElementId = contextElementId
        self.target = target
        self.candidate = candidate
    }
}

public enum MinimumPredicateSelector {
    public static func predicateCandidates(for element: HeistElement) -> [PredicateCandidate] {
        predicateCandidates(forSubject: element)
    }

    package static func predicateCandidates(forSubject element: some PredicateSelectionSubject) -> [PredicateCandidate] {
        let atoms = matcherAtoms(for: element)
        guard !atoms.isEmpty else { return [] }

        var candidates: [PredicateCandidate] = []
        candidates.reserveCapacity(atoms.count)

        var accumulated: [MatcherAtom] = []
        var seen = Set<ResolvedElementPredicate>()
        for atom in atoms {
            accumulated.append(atom)
            let predicate = combinedPredicate(from: accumulated)
            guard predicate.hasPredicates, seen.insert(predicate).inserted else { continue }
            candidates.append(PredicateCandidate(
                predicate: predicate,
                atoms: accumulated,
                tier: tier(for: accumulated)
            ))
        }

        return candidates.sorted { $0.rank < $1.rank }
    }

    public static func minimumUniquePredicate(
        for contextElementId: PredicateSelectionElementId,
        in context: PredicateSelectionContext
    ) -> MinimumPredicateSelection? {
        minimumUniquePredicate(
            for: contextElementId,
            in: context.elements.map { PredicateSelectionSubjectElement(id: $0.id, element: $0.element) }
        )
    }

    package static func minimumUniquePredicate<Subject: PredicateSelectionSubject>(
        for contextElementId: PredicateSelectionElementId,
        in elements: [PredicateSelectionSubjectElement<Subject>]
    ) -> MinimumPredicateSelection? {
        guard let targetElement = elements.first(where: { $0.id == contextElementId }) else {
            return nil
        }

        let candidates = predicateCandidates(forSubject: targetElement.element)
        let graph = ElementPredicateGraph(subjects: elements, identity: \.id)
        var bestAmbiguousCandidate: PredicateCandidate?
        var bestAmbiguousRank: PredicateCandidate.OrdinalBaseRank?

        for candidate in candidates {
            let matches = graph.resolve(candidate.predicate).matches
            guard matches.contains(where: { $0.identity == contextElementId }) else { continue }
            if matches.count == 1 {
                return MinimumPredicateSelection(
                    contextElementId: contextElementId,
                    target: .predicate(authoredTemplate(candidate.predicate)),
                    candidate: candidate
                )
            }
            let ordinalBaseRank = candidate.ordinalBaseRank(matchCount: matches.count)
            if bestAmbiguousRank.map({ ordinalBaseRank < $0 }) ?? true {
                bestAmbiguousCandidate = candidate
                bestAmbiguousRank = ordinalBaseRank
            }
        }

        guard let strongestSemanticCandidate = bestAmbiguousCandidate else { return nil }
        let matches = graph.resolve(strongestSemanticCandidate.predicate).matches
        guard let ordinal = matches.firstIndex(where: { $0.identity == contextElementId }) else { return nil }

        let ordinalCandidate = PredicateCandidate(
            predicate: strongestSemanticCandidate.predicate,
            atoms: strongestSemanticCandidate.atoms,
            tier: .ordinalDisambiguation
        )
        return MinimumPredicateSelection(
            contextElementId: contextElementId,
            target: .predicate(authoredTemplate(strongestSemanticCandidate.predicate), ordinal: ordinal),
            candidate: ordinalCandidate
        )
    }

    private static func matcherAtoms(for element: some PredicateSelectionSubject) -> [MatcherAtom] {
        let facts = element.predicateMatcherFacts
        var atoms: [MatcherAtom] = []
        atoms.reserveCapacity(facts.count)

        for fact in facts {
            guard let stability = AccessibilityPolicy.matcherFactStability(fact),
                  let predicate = predicate(for: fact)
            else { continue }
            atoms.append(MatcherAtom(
                predicate: predicate,
                stability: stability,
                priority: AccessibilityPolicy.matcherFactPriority(fact)
            ))
        }

        return atoms.sorted { $0.sortKey < $1.sortKey }
    }

    private static func predicate(for fact: AccessibilityMatcherFact) -> ResolvedElementPredicate? {
        switch fact {
        case .identifier(let identifier):
            return .identifier(identifier)
        case .label(let label):
            return .label(label)
        case .value(let value):
            return .value(value)
        case .trait(let trait):
            return .traits([trait])
        case .excludedTrait(let trait):
            return ResolvedElementPredicate([.exclude(.traits([trait]))])
        }
    }

    private static func combinedPredicate(from atoms: [MatcherAtom]) -> ResolvedElementPredicate {
        ResolvedElementPredicate(atoms.flatMap { $0.predicate.core.checks })
    }

    private static func authoredTemplate(_ predicate: ResolvedElementPredicate) -> ElementPredicate {
        ElementPredicate(core: predicate.core.map { .literal($0) })
    }

    private static func tier(for atoms: [MatcherAtom]) -> CandidateTier {
        let hasIdentity = atoms.contains { $0.stability == .identity }
        let hasState = atoms.contains { $0.stability == .state }
        switch (hasIdentity, hasState) {
        case (true, false):
            return .identityOnly
        case (true, true):
            return .identityWithState
        case (false, true):
            return .stateOnly
        case (false, false):
            return .ordinalDisambiguation
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

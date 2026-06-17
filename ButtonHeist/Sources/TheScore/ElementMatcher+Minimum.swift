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
    public let predicate: ElementPredicate
    public let stability: AccessibilityFactStability
    public let priority: Int

    public init(
        predicate: ElementPredicate,
        stability: AccessibilityFactStability,
        priority: Int
    ) {
        self.predicate = predicate
        self.stability = stability
        self.priority = priority
    }
}

public struct PredicateCandidate: Sendable, Equatable {
    public let predicate: ElementPredicate
    public let atoms: [MatcherAtom]
    public let tier: CandidateTier

    public init(
        predicate: ElementPredicate,
        atoms: [MatcherAtom],
        tier: CandidateTier
    ) {
        self.predicate = predicate
        self.atoms = atoms
        self.tier = tier
    }
}

public struct PredicateSelectionContext: Sendable, Equatable {
    public struct Element: Sendable, Equatable {
        public let id: String
        public let element: HeistElement

        public init(id: String, element: HeistElement) {
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
    public let contextElementId: String
    public let target: ElementTarget
    public let candidate: PredicateCandidate

    public init(
        contextElementId: String,
        target: ElementTarget,
        candidate: PredicateCandidate
    ) {
        self.contextElementId = contextElementId
        self.target = target
        self.candidate = candidate
    }
}

public func predicateCandidates(for element: HeistElement) -> [PredicateCandidate] {
    MinimumPredicateSelector.predicateCandidates(for: element)
}

public func minimumUniquePredicate(
    for contextElementId: String,
    in context: PredicateSelectionContext
) -> MinimumPredicateSelection? {
    MinimumPredicateSelector.minimumUniquePredicate(for: contextElementId, in: context)
}

public enum MinimumPredicateSelector {
    public static func predicateCandidates(for element: HeistElement) -> [PredicateCandidate] {
        let atoms = matcherAtoms(for: element)
        guard !atoms.isEmpty else { return [] }

        var candidates: [PredicateCandidate] = []
        candidates.reserveCapacity(atoms.count)

        var accumulated: [MatcherAtom] = []
        var seen = Set<ElementPredicate>()
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

        return candidates.sorted(by: candidatePrecedes)
    }

    public static func minimumUniquePredicate(
        for contextElementId: String,
        in context: PredicateSelectionContext
    ) -> MinimumPredicateSelection? {
        guard let targetElement = context.elements.first(where: { $0.id == contextElementId }) else {
            return nil
        }

        let candidates = predicateCandidates(for: targetElement.element)
        var bestAmbiguousCandidate: PredicateCandidate?
        var bestAmbiguousMatchCount: Int?

        for candidate in candidates {
            let matches = context.elements.filter { $0.element.matches(candidate.predicate) }
            guard matches.contains(where: { $0.id == contextElementId }) else { continue }
            if matches.count == 1 {
                return MinimumPredicateSelection(
                    contextElementId: contextElementId,
                    target: .predicate(candidate.predicate),
                    candidate: candidate
                )
            }
            if isBetterOrdinalBase(
                candidate,
                matchCount: matches.count,
                than: bestAmbiguousCandidate,
                matchCount: bestAmbiguousMatchCount
            ) {
                bestAmbiguousCandidate = candidate
                bestAmbiguousMatchCount = matches.count
            }
        }

        guard let strongestSemanticCandidate = bestAmbiguousCandidate else { return nil }
        let matches = context.elements.filter { $0.element.matches(strongestSemanticCandidate.predicate) }
        guard let ordinal = matches.firstIndex(where: { $0.id == contextElementId }) else { return nil }

        let ordinalCandidate = PredicateCandidate(
            predicate: strongestSemanticCandidate.predicate,
            atoms: strongestSemanticCandidate.atoms,
            tier: .ordinalDisambiguation
        )
        return MinimumPredicateSelection(
            contextElementId: contextElementId,
            target: .predicate(strongestSemanticCandidate.predicate, ordinal: ordinal),
            candidate: ordinalCandidate
        )
    }

    private static func matcherAtoms(for element: HeistElement) -> [MatcherAtom] {
        let facts = AccessibilityPolicy.matcherFacts(for: element)
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

        return atoms.sorted(by: atomPrecedes)
    }

    private static func predicate(for fact: AccessibilityMatcherFact) -> ElementPredicate? {
        switch fact {
        case .identifier(let identifier):
            return ElementPredicate(identifier: .exact(identifier))
        case .label(let label):
            return ElementPredicate(label: .exact(label))
        case .value(let value):
            return ElementPredicate(value: .exact(value))
        case .trait(let trait):
            return ElementPredicate(traits: [trait])
        case .excludedTrait(let trait):
            return ElementPredicate(excludeTraits: [trait])
        }
    }

    private static func combinedPredicate(from atoms: [MatcherAtom]) -> ElementPredicate {
        var label: StringMatch<String>?
        var identifier: StringMatch<String>?
        var value: StringMatch<String>?
        var traits: [HeistTrait] = []
        var excludeTraits: [HeistTrait] = []

        for atom in atoms {
            let predicate = atom.predicate
            if label == nil { label = predicate.label }
            if identifier == nil { identifier = predicate.identifier }
            if value == nil { value = predicate.value }
            traits.append(contentsOf: predicate.traits)
            excludeTraits.append(contentsOf: predicate.excludeTraits)
        }

        return ElementPredicate(
            label: label,
            identifier: identifier,
            value: value,
            traits: AccessibilityPolicy.orderedMatcherTraits(unique(traits)),
            excludeTraits: AccessibilityPolicy.orderedMatcherTraits(unique(excludeTraits))
        )
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

    private static func atomPrecedes(_ lhs: MatcherAtom, _ rhs: MatcherAtom) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.predicate.description < rhs.predicate.description
    }

    private static func isBetterOrdinalBase(
        _ candidate: PredicateCandidate,
        matchCount: Int,
        than existing: PredicateCandidate?,
        matchCount existingMatchCount: Int?
    ) -> Bool {
        guard let existing, let existingMatchCount else { return true }
        if matchCount != existingMatchCount {
            return matchCount < existingMatchCount
        }
        if candidate.tier != existing.tier {
            return candidate.tier < existing.tier
        }
        if candidate.atoms.count != existing.atoms.count {
            return candidate.atoms.count > existing.atoms.count
        }
        return candidate.predicate.description < existing.predicate.description
    }

    private static func candidatePrecedes(_ lhs: PredicateCandidate, _ rhs: PredicateCandidate) -> Bool {
        if lhs.tier != rhs.tier {
            return lhs.tier < rhs.tier
        }
        if lhs.atoms.count != rhs.atoms.count {
            return lhs.atoms.count < rhs.atoms.count
        }
        let leftPriority = lhs.atoms.map(\.priority)
        let rightPriority = rhs.atoms.map(\.priority)
        if leftPriority != rightPriority {
            return leftPriority.lexicographicallyPrecedes(rightPriority)
        }
        return lhs.predicate.description < rhs.predicate.description
    }

    private static func unique(_ traits: [HeistTrait]) -> [HeistTrait] {
        var seen = Set<HeistTrait>()
        return traits.filter { seen.insert($0).inserted }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

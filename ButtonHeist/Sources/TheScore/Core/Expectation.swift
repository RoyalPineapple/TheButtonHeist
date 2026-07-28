import Foundation
import ThePlans

private extension Observation.Fact {
    var reading: Int {
        var hasher = Hasher()
        switch self {
        case .elementsChanged(let capture):
            capture.interface.hashSemantic(into: &hasher)
        case .screenChanged(let facts):
            hasher.combine(facts.idAfter)
        case .announcement(let announcement):
            hasher.combine(announcement)
        case .noChange:
            hasher.combine("noChange")
        }
        return hasher.finalize()
    }
}

package struct PendingPredicate: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case elementsChanged(ResolvedAccessibilityPredicate?)
        case screenChanged(ResolvedScreenPredicate?)
        case announcement(ResolvedAnnouncementPredicate?)
        case noChange
    }

    let kind: Kind
    let scope: ReadingScope?

    /// The resolved question this predicate is waiting to have answered.
    ///
    /// `nil` for a bare predicate ("any element change") and for the stillness
    /// gate, neither of which names anything.
    package var query: ResolvedAccessibilityPredicate? {
        switch kind {
        case .elementsChanged(let query): return query
        case .screenChanged(let query): return query.map(ResolvedAccessibilityPredicate.screenChanged)
        case .announcement(let query): return query.map(ResolvedAccessibilityPredicate.announcement)
        case .noChange: return .noChange
        }
    }

    static func elementsChanged(
        _ query: ResolvedAccessibilityPredicate? = nil,
        scope: ReadingScope? = nil
    ) -> Self {
        Self(kind: .elementsChanged(query), scope: scope)
    }

    static func screenChanged(_ query: ResolvedScreenPredicate?) -> Self {
        Self(kind: .screenChanged(query), scope: nil)
    }

    static func announcement(_ query: ResolvedAnnouncementPredicate?) -> Self {
        Self(kind: .announcement(query), scope: nil)
    }

    static let noChange = Self(kind: .noChange, scope: nil)

    package var description: String {
        switch kind {
        case .elementsChanged(let query?): return query.description
        case .elementsChanged(nil): return "the elements to change"
        case .screenChanged(let query?): return query.description
        case .screenChanged(nil): return "the screen to change"
        case .announcement(let query?): return query.description
        case .announcement(nil): return "an announcement"
        case .noChange: return "the tree to stop changing"
        }
    }

    /// What evaluating a tick against this predicate found.
    enum Evaluation: Equatable {
        /// The tick is not what this predicate asks about.
        case indifferent
        /// Matched, at this reading.
        ///
        /// The reading is hashed at the scope the assertion named, so a change's
        /// second predicate can be required to differ from what matched its
        /// first.
        case matched(reading: Int)
        /// This predicate's question, put to this tick and not matched.
        case unmatched
    }

    /// Evaluate a tick against this predicate.
    ///
    /// One stream, so every predicate sees every tick and most of them have
    /// nothing to say about most of them. Pattern-matching the tick against the
    /// question is the whole of it: a combination that does not line up is
    /// indifference, not an error.
    func evaluate(_ fact: Observation.Fact) -> Evaluation {
        switch (fact, kind) {
        case (.elementsChanged(let capture), .elementsChanged(let query?)):
            return query.matches(capture.interface)
                ? .matched(reading: reading(of: capture.interface, or: fact))
                : .unmatched
        case (.elementsChanged(let capture), .elementsChanged(nil)):
            return .matched(reading: reading(of: capture.interface, or: fact))
        case (.screenChanged(let facts), .screenChanged(let query?)):
            return query.matches(facts) ? .matched(reading: fact.reading) : .unmatched
        case (.screenChanged, .screenChanged(nil)):
            return .matched(reading: fact.reading)
        case (.announcement(let announcement), .announcement(let query?)):
            return query.matches(announcement.text) ? .matched(reading: fact.reading) : .unmatched
        case (.announcement, .announcement(nil)):
            return .matched(reading: fact.reading)
        case (.noChange, .noChange):
            return .matched(reading: fact.reading)
        case (.elementsChanged, _), (.screenChanged, _), (.announcement, _), (.noChange, _):
            return .indifferent
        }
    }

    /// The reading this predicate compares at, which is the scope its assertion
    /// named or the whole tree when it named none.
    private func reading(of interface: Interface, or fact: Observation.Fact) -> Int {
        scope.map { $0.reading(in: interface) } ?? fact.reading
    }
}

/// One authored assertion, and what is left of it.
///
/// Three cases, because an assertion is one predicate or two and a half-answered
/// pair is neither. A change is two readings that differ, so once the first
/// predicate of a pair matches it is gone and what survives is the reading that
/// matched it beside the predicate still owed.
enum PendingStep: Equatable {
    /// One predicate, about a single reading.
    case single(PendingPredicate)
    /// Two predicates, in order, neither matched.
    case pair(PendingPredicate, PendingPredicate)
    /// The reading the first predicate matched at, and the one still owed, which
    /// has to match at a reading that differs from it.
    case owed(after: Int, PendingPredicate)

    /// Any change at all: two predicates every element tick matches, separated
    /// only by the reading.
    ///
    /// A change is a comparison, and one tick is one reading — it shows a state,
    /// not a change. So this waits for two, exactly as `updated` does when no
    /// property narrows it. The reading is the whole graph, so what counts as
    /// different is anything an assertion could have named, anywhere.
    static let anyChange = Self.pair(.elementsChanged(), .elementsChanged())

    /// The predicates this step is still waiting on, in order.
    var pending: [PendingPredicate] {
        switch self {
        case .single(let predicate): return [predicate]
        case .pair(let first, let second): return [first, second]
        case .owed(_, let predicate): return [predicate]
        }
    }

    /// What evaluating a tick did to this step.
    ///
    /// Only `.unmatched` stops the tick. Indifference and a match both pass it to
    /// the step behind, because a tick can answer one predicate in each of
    /// several consecutive steps.
    enum Evaluation: Equatable {
        /// The tick says nothing this step asked about.
        case indifferent
        /// A predicate matched. What remains, or nothing when the step is done.
        case matched(PendingStep?)
        /// This step's question, put to this tick and not answered. The tick goes
        /// no further, because everything behind this step comes after it.
        case unmatched
    }

    /// Evaluate a tick against the predicate this step is owed.
    ///
    /// Only the owed predicate sees the tick — the one behind it in a pair is
    /// unreachable until this one matches, so a change's second predicate never
    /// sees the tick that matched its first.
    func evaluate(_ fact: Observation.Fact) -> Evaluation {
        switch self {
        case .single(let predicate):
            switch predicate.evaluate(fact) {
            case .indifferent: return .indifferent
            case .matched: return .matched(nil)
            case .unmatched: return .unmatched
            }
        case .pair(let first, let second):
            switch first.evaluate(fact) {
            case .indifferent: return .indifferent
            case .matched(let reading): return .matched(.owed(after: reading, second))
            case .unmatched: return .unmatched
            }
        case .owed(let previous, let predicate):
            switch predicate.evaluate(fact) {
            case .indifferent: return .indifferent
            case .matched(let reading) where reading != previous: return .matched(nil)
            case .matched, .unmatched: return .unmatched
            }
        }
    }
}

/// The authored predicates still waiting.
///
/// Pure data: predicates in, ticks folded over them, an answer out. An
/// expectation is determined entirely by its authored predicates and the ordered
/// ticks it has seen, so it is derived from the tick log rather than a live thing
/// to be synchronized against.
///
/// Scope: what the caller asked for, and then stillness. The stillness predicate
/// is last, and the list is ordered, so nothing evaluates it until what the
/// caller asked for has already happened.
package struct Expectation: Equatable, Sendable {
    private var pending: [PendingStep]

    package init(_ authored: [ResolvedAccessibilityPredicate] = []) {
        pending = authored.flatMap(\.pendingSteps)
    }

    /// This expectation advanced by every tick in order.
    ///
    /// The only way an expectation moves. Given the log, predicate state is
    /// recomputed rather than remembered, so the same ticks always fold to the
    /// same answer.
    package func folding(_ facts: some Sequence<Observation.Fact>) -> Self {
        facts.reduce(into: self) { expectation, fact in
            expectation.pending = Self.remaining(of: expectation.pending, after: fact)
        }
    }

    /// What is left of the list once one tick has flowed through it.
    ///
    /// An authored list is a narrative — this happened, then this happened, then
    /// this happened — so the tick is evaluated against the steps in order. A
    /// step that is indifferent or that matched passes it to the next; one that
    /// did not match keeps it, and the tick goes no further, because everything
    /// behind that step comes after it.
    ///
    /// One tick can therefore match a predicate in several consecutive steps,
    /// which is what keeps the verdict independent of how finely the tripwire
    /// sampled, and is what lets two things swapped in one frame both be read:
    /// the tree still holding the old one matches the arrival's `missing` and
    /// then the departure's `exists` behind it.
    private static func remaining(
        of pending: [PendingStep],
        after fact: Observation.Fact
    ) -> [PendingStep] {
        guard let head = pending.first else { return [] }
        switch head.evaluate(fact) {
        case .unmatched:
            return pending
        case .indifferent:
            return [head] + remaining(of: Array(pending.dropFirst()), after: fact)
        case .matched(let rest):
            return (rest.map { [$0] } ?? []) + remaining(of: Array(pending.dropFirst()), after: fact)
        }
    }

    /// Whether every authored predicate has matched.
    ///
    /// A predicate that matched is gone, so an empty list is the only record that
    /// it happened.
    package var isMet: Bool { pending.isEmpty }

    /// What the caller is still waiting on, head first, in authored order.
    package var outstanding: [PendingPredicate] {
        pending.flatMap(\.pending)
    }

}

enum ReadingScope: Equatable {
    case property(AssertableProperty, of: ResolvedAccessibilityTarget)

    case element(ResolvedAccessibilityTarget)

    case screen

    /// What this scope reads, as a number that only means "same" or "different".
    ///
    /// Every arm hashes the same thing: identity, and the properties in
    /// `AssertableProperty`. Nothing wider, because a reading is what decides
    /// whether a change's second leg found something new, and a leg satisfied
    /// by a frame moving a pixel is a change nobody asserted. The vault hashes
    /// wider — geometry included — and is right to: it is deciding whether to
    /// emit a tick, not whether an assertion came true.
    func reading(in interface: Interface) -> Int {
        var hasher = Hasher()
        switch self {
        case .screen:
            interface.hashSemantic(into: &hasher)
        case .element(let target):
            for element in Self.matches(target, in: interface) {
                element.hashSemantic(into: &hasher)
            }
        case .property(let property, let target):
            for element in Self.matches(target, in: interface) {
                property.combine(element, into: &hasher)
            }
        }
        return hasher.finalize()
    }

    private static func matches(
        _ target: ResolvedAccessibilityTarget,
        in interface: Interface
    ) -> [HeistElement] {
        AccessibilityTargetMatchGraph(interface: interface).resolve(target).elements.elements
    }
}

extension Interface: SemanticallyHashable {
    /// This graph, reduced to what an assertion can say about it.
    ///
    /// The whole graph is what a bare `elementsChanged` asks about, so its
    /// reading is every element's, in projection order.
    public func hashSemantic(into hasher: inout Hasher) {
        for element in projectedElements {
            element.hashSemantic(into: &hasher)
        }
    }
}

extension HeistElement: SemanticallyHashable {
    /// This element, reduced to the part of it that means something.
    ///
    /// What a developer names it by, what a VoiceOver user hears, and every
    /// property an assertion can constrain. Geometry is absent by
    /// construction: it is not in `AssertableProperty`, so a reading can never
    /// be asked to take it.
    public func hashSemantic(into hasher: inout Hasher) {
        hasher.combine(identifier)
        hasher.combine(label)
        for property in AssertableProperty.allCases {
            property.combine(self, into: &hasher)
        }
    }
}

extension AssertableProperty {
    /// This property's contribution to a reading.
    ///
    /// Total, because every assertable property is one the projection carries.
    /// Geometry has no arm here and needs none: it is not in this enum, so a
    /// reading can never be asked to take it.
    func combine(_ element: HeistElement, into hasher: inout Hasher) {
        switch self {
        case .value: hasher.combine(element.value)
        case .hint: hasher.combine(element.hint)
        case .traits: hasher.combine(Set(element.traits))
        case .actions: hasher.combine(Set(element.actions))
        case .customContent: hasher.combine(element.customContent)
        case .rotors: hasher.combine(element.rotors?.map(\.name))
        }
    }
}

extension ResolvedAccessibilityPredicate {
    var pendingSteps: [PendingStep] {
        switch self {
        case .exists, .missing:
            return [.single(.elementsChanged(self))]
        case .announcement(let query):
            return [.single(.announcement(query))]
        case .screenChanged(let query):
            return [.single(.screenChanged(query))]
        case .elementsChanged(let assertions):
            guard !assertions.isEmpty else { return [.anyChange] }
            return assertions.map { assertion in
                let scope = assertion.readingScope
                let composed = assertion.composed.map {
                    PendingPredicate.elementsChanged($0, scope: scope)
                }
                return composed.count == 1
                    ? .single(composed[0])
                    : .pair(composed[0], composed[1])
            }
        case .noChange:
            return [.single(.noChange)]
        }
    }

    func matches(_ interface: Interface) -> Bool {
        switch self {
        case .exists(let target): return target.found(in: interface)
        case .missing(let target): return !target.found(in: interface)
        case .announcement, .screenChanged, .elementsChanged, .noChange: return false
        }
    }
}

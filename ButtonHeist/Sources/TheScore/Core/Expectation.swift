import Foundation
import ThePlans

/// One observation, as the predicate runtime sees it.
///
/// A tick carries the reading it was taken from, so a consumer never asks the
/// live tree anything: a predicate is judged against the moment it was observed.
/// Everything a tick holds is a value, which is why folding them needs no actor.
package enum Tick: Sendable, Equatable {
    /// A reading of the element tree.
    ///
    /// Carries the whole capture, not just its interface: the capture's context
    /// and transition are the run's evidence of focus, keyboard, window stack
    /// and notifications, which a report quotes and no predicate reads. A tick
    /// is what was observed, not the subset predicates ask about.
    case elementsChanged(AccessibilityTrace.Capture)
    case screenChanged(ScreenFacts)
    case announcement(String)
    case noChange

    package enum Kind: Equatable, Sendable {
        case elementsChanged
        case screenChanged
        case announcement
        case noChange
    }

    package var kind: Kind {
        switch self {
        case .elementsChanged: return .elementsChanged
        case .screenChanged: return .screenChanged
        case .announcement: return .announcement
        case .noChange: return .noChange
        }
    }

    /// The tree this tick read, when it read one.
    package var interface: Interface? {
        guard case .elementsChanged(let capture) = self else { return nil }
        return capture.interface
    }

    var reading: Int {
        var hasher = Hasher()
        switch self {
        case .elementsChanged(let capture):
            capture.interface.hashSemantic(into: &hasher)
        case .screenChanged(let facts):
            hasher.combine(facts.idAfter)
        case .announcement(let spoken):
            hasher.combine(spoken)
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

    /// The lane this predicate reads, so a consumer can ask which kind of tick
    /// the run is blocked on without parsing its description.
    package var tick: Tick.Kind { lane }

    /// The resolved question this predicate is waiting to have answered.
    ///
    /// `nil` for a bare lane predicate ("any element change") and for the
    /// stillness gate, neither of which names anything.
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

    var lane: Tick.Kind {
        switch kind {
        case .elementsChanged: return .elementsChanged
        case .screenChanged: return .screenChanged
        case .announcement: return .announcement
        case .noChange: return .noChange
        }
    }

    func reads(_ tick: Tick) -> Bool {
        lane == tick.kind
    }

    func admits(_ tick: Tick) -> Bool {
        reads(tick) && matches(tick)
    }

    func matching(_ tick: Tick) -> Int? {
        guard matches(tick) else { return nil }
        guard let interface = tick.interface, let scope else { return tick.reading }
        return scope.reading(in: interface)
    }

    func matches(_ tick: Tick) -> Bool {
        switch (tick, kind) {
        case (.elementsChanged(let capture), .elementsChanged(let query?)):
            return query.matches(capture.interface)
        case (.elementsChanged, .elementsChanged(nil)):
            return true
        case (.screenChanged(let facts), .screenChanged(let query?)):
            return query.matches(facts)
        case (.screenChanged, .screenChanged(nil)):
            return true
        case (.announcement(let spoken), .announcement(let query?)):
            return query.matches(spoken)
        case (.announcement, .announcement(nil)):
            return true
        case (.noChange, .noChange):
            return true
        default:
            preconditionFailure("\(tick.kind) asked of a predicate that does not read it")
        }
    }
}

/// One authored assertion, and how much of it is left to fulfil.
///
/// Three states, which are the three things a step can be. A `presence` asks
/// about a moment. An `awaitingBefore` asks about a change, which is two
/// predicates fulfilled in order on readings that differ. An `awaitingAfter` is
/// that change with its first predicate fulfilled: it holds the reading that
/// fulfilled it, so the one still owed can be asked to differ from it.
///
/// The pairing is a state rather than an array because it is the meaning. When
/// only the first predicate is fulfilled, the second has to keep its own place,
/// or a leftover `exists(X)` is indistinguishable from an unrelated predicate
/// that happened to land at that index.
struct PendingStep: Equatable {
    private enum State: Equatable {
        case presence(PendingPredicate)
        case awaitingBefore(PendingPredicate, after: PendingPredicate)
        case awaitingAfter(PendingPredicate, fulfilledAt: Int)
    }

    private let state: State

    private init(_ state: State) {
        self.state = state
    }

    static func presence(_ predicate: PendingPredicate) -> Self {
        Self(.presence(predicate))
    }

    static func change(
        before: PendingPredicate,
        after: PendingPredicate
    ) -> Self {
        Self(.awaitingBefore(before, after: after))
    }

    /// Any change at all: two legs every element tick answers, separated only by
    /// the reading.
    ///
    /// A change is a comparison, and one tick is one reading — it shows a state,
    /// not a change. So this waits for two, exactly as `updated` does when no
    /// property narrows it. The reading is the whole graph, so what counts as
    /// different is anything an assertion could have named, anywhere.
    static let anyChange = Self.change(
        before: .elementsChanged(),
        after: .elementsChanged()
    )

    /// The predicates this step is still waiting on, in order.
    var pending: [PendingPredicate] {
        switch state {
        case .presence(let predicate): return [predicate]
        case .awaitingBefore(let before, let after): return [before, after]
        case .awaitingAfter(let after, _): return [after]
        }
    }

    /// What a step says about a tick it was offered.
    ///
    /// Three answers, and only one of them stops the tick. Yes and don't-care
    /// both pass it to the step behind; a no keeps it, because everything behind
    /// this step comes after it.
    enum Answer: Equatable {
        /// Not this step's lane. It has no opinion and the tick carries on.
        case indifferent
        /// The offered predicate is fulfilled and a predicate is still owed.
        /// This is the step waiting on it.
        case awaiting(PendingStep)
        /// Every predicate of the step is fulfilled, so it drains.
        case drained
        /// The offered predicate is not fulfilled. The tick goes no further.
        case unfulfilled
    }

    /// Offer this step a tick.
    ///
    /// Exactly one predicate is offered — the head, because the ones behind it
    /// in a step are unreachable until it is fulfilled. So a change's second leg
    /// is never offered the tick that fulfilled its first.
    ///
    /// What fulfils the first leg is hashed at the scope its assertion named: a
    /// property, an element, or the whole tree. The second leg has to match
    /// something that hashes differently at that same scope, which is the whole
    /// of what makes the pair a change.
    func offered(_ tick: Tick) -> Answer {
        switch state {
        case .presence(let predicate):
            guard predicate.reads(tick) else { return .indifferent }
            guard predicate.matches(tick) else { return .unfulfilled }
            return .drained
        case .awaitingBefore(let before, let after):
            guard before.reads(tick) else { return .indifferent }
            guard let reading = before.matching(tick) else { return .unfulfilled }
            return .awaiting(Self(.awaitingAfter(after, fulfilledAt: reading)))
        case .awaitingAfter(let after, let fulfilledAt):
            guard after.reads(tick) else { return .indifferent }
            guard let arrived = after.matching(tick), arrived != fulfilledAt else {
                return .unfulfilled
            }
            return .drained
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
/// Scope: what the caller asked for. Whether the tree has stopped moving is a
/// property of the observation stream and `TickLog.isStill` answers it, so a run
/// waiting for both a predicate and a settled tree asks each of them.
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
    package func folding(_ ticks: some Sequence<Tick>) -> Self {
        ticks.reduce(into: self) { expectation, tick in
            expectation.pending = Self.draining(expectation.pending, tick)
        }
    }

    /// The list after one tick has flowed through it.
    ///
    /// An authored list is a narrative — this happened, then this happened, then
    /// this happened — so a tick is offered to the steps in order. A step that
    /// is indifferent or fulfilled passes it to the next; one that is not
    /// fulfilled keeps it, and the tick goes no further, because everything
    /// behind that step comes after it. A step with every predicate fulfilled
    /// drains; one with a predicate left waits where it is.
    ///
    /// One tick can therefore fulfil a predicate in several consecutive steps,
    /// which is what keeps the verdict independent of how finely the tripwire
    /// sampled, and is what lets two things swapped in one frame both be read:
    /// the tree still holding the old one fulfils the arrival's `missing` and
    /// then the departure's `exists` behind it.
    private static func draining(_ pending: [PendingStep], _ tick: Tick) -> [PendingStep] {
        guard let next = pending.first else { return [] }
        let behind = { draining(Array(pending.dropFirst()), tick) }
        switch next.offered(tick) {
        case .indifferent: return [next] + behind()
        case .awaiting(let step): return [step] + behind()
        case .drained: return behind()
        case .unfulfilled: return pending
        }
    }

    /// Whether every authored predicate has drained.
    package var isMet: Bool { pending.isEmpty }

    /// What the caller is still waiting on, head first, in authored order.
    package var outstanding: [PendingPredicate] {
        pending.flatMap(\.pending)
    }

}

extension Tick {
    /// The ticks one observation is, in order.
    ///
    /// A reading is ticks before it is anything else, and which ticks it is
    /// follows from the reading alone: the store has already made the one
    /// comparison — semantics and placements against the reading before — so
    /// this only names them.
    package static func observation(
        _ capture: AccessibilityTrace.Capture,
        isChange: Bool,
        isReplacement: Bool,
        screenHeading: String?
    ) -> [Tick] {
        guard isReplacement else {
            return [isChange ? .elementsChanged(capture) : .noChange]
        }
        return TickLog.replacement(
            screen: ScreenFacts(idAfter: screenHeading),
            arriving: capture
        )
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
            return [.presence(.elementsChanged(self))]
        case .announcement(let query):
            return [.presence(.announcement(query))]
        case .screenChanged(let query):
            return [.presence(.screenChanged(query))]
        case .elementsChanged(let assertions):
            guard !assertions.isEmpty else { return [.anyChange] }
            return assertions.map { assertion in
                let scope = assertion.readingScope
                let legs = assertion.composed.map {
                    PendingPredicate.elementsChanged($0, scope: scope)
                }
                return legs.count == 1
                    ? .presence(legs[0])
                    : .change(before: legs[0], after: legs[1])
            }
        case .noChange:
            return []
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

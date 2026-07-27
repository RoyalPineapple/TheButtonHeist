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
            hasher.combine(capture.interface.projectedElements)
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

    /// A predicate that named no element: two legs any element tick answers, so
    /// only the reading separates them.
    ///
    /// A change is a comparison, and one tick is one reading — it shows a state,
    /// not a change. So this waits for two, exactly as `updated` does when no
    /// property narrows it.
    static let nothingNamed = Self.change(
        before: .elementsChanged(),
        after: .elementsChanged()
    )

    /// The predicates this step is still waiting on, in order.
    var pending: [PendingPredicate] {
        switch state {
        case .presence(let predicate):
            return [predicate]
        case .awaitingBefore(let before, let after):
            return [before, after]
        case .awaitingAfter(let after, _):
            return [after]
        }
    }

    func evaluate(_ tick: Tick) -> Self? {
        switch state {
        case .presence(let predicate):
            guard predicate.reads(tick), predicate.matches(tick) else { return self }
            return nil
        case .awaitingBefore(let before, let after):
            guard before.reads(tick), let reading = before.matching(tick) else { return self }
            return Self(.awaitingAfter(after, fulfilledAt: reading))
        case .awaitingAfter(let after, let fulfilledAt):
            guard after.reads(tick),
                  let arrived = after.matching(tick),
                  arrived != fulfilledAt
            else { return self }
            return nil
        }
    }
}

/// The predicates still waiting, and whether the last tick was stillness.
///
/// Pure data: predicates in, ticks folded over them, an answer out. An
/// expectation is determined entirely by its authored predicates and the ordered
/// ticks it has seen, so it is derived from the tick log rather than a live thing
/// to be synchronized against.
package struct Expectation: Equatable, Sendable {
    private var pending: [PendingStep]

    private static let gate = PendingPredicate.noChange

    private var isStill = false

    package init(_ authored: [ResolvedAccessibilityPredicate] = []) {
        pending = authored.flatMap(\.pendingSteps)
    }

    /// This expectation advanced by every tick in order.
    ///
    /// The fold the mutating entry points are written in terms of. Given the
    /// log, predicate state is recomputed rather than remembered.
    func folding(_ ticks: some Sequence<Tick>) -> Self {
        ticks.reduce(into: self) { $0.evaluate($1) }
    }

    package var isMet: Bool { pending.isEmpty && isStill }

    /// What the run is still waiting on, head first.
    ///
    /// The gate is last because stillness is the final thing a run waits for:
    /// every authored predicate drains first, then the tree stops moving.
    package var outstanding: [PendingPredicate] {
        pending.flatMap(\.pending) + (isStill ? [] : [Self.gate])
    }

    /// Fold in the ticks of one observation.
    ///
    /// The store has already made the one comparison — semantics and placements
    /// against the reading before — so this only names the ticks.
    ///
    /// A reading that found no change *is* the proof of stillness, and it is the
    /// only proof there is. Nothing polls a quiet tree to confirm it a second
    /// time: the next reading arrives when the tree moves, so an expectation
    /// whose predicate had already drained would wait forever for a stillness
    /// tick that no one was going to send.
    /// - Returns: the ticks this observation was, in order.
    @discardableResult
    package mutating func observe(
        _ capture: AccessibilityTrace.Capture,
        isChange: Bool,
        isReplacement: Bool,
        screenHeading: String?
    ) -> [Tick] {
        let ticks = if isReplacement {
            TickLog.replacement(
                screen: ScreenFacts(idAfter: screenHeading),
                arriving: capture
            )
        } else {
            [isChange ? Tick.elementsChanged(capture) : .noChange]
        }
        for tick in ticks {
            evaluate(tick)
        }
        return ticks
    }

    @discardableResult
    package mutating func snapshot(_ capture: AccessibilityTrace.Capture) -> Tick {
        evaluate(.elementsChanged(capture))
    }

    @discardableResult
    package mutating func empty(at timestamp: Date) -> Tick {
        evaluate(.elementsChanged(.empty(at: timestamp)))
    }

    @discardableResult
    package mutating func screenChanged(_ facts: ScreenFacts) -> Tick {
        evaluate(.screenChanged(facts))
    }

    @discardableResult
    package mutating func announcement(_ text: String) -> Tick {
        evaluate(.announcement(text))
    }

    @discardableResult
    package mutating func noChange() -> Tick {
        evaluate(.noChange)
    }

    /// The one place a tick is applied.
    ///
    /// Stillness is assigned, not accumulated: it says whether the tick that
    /// just arrived was stillness, so a tree that starts moving again withdraws
    /// it. That makes the whole of this a function of the ticks seen so far.
    ///
    /// - Returns: the tick it just applied.
    @discardableResult
    private mutating func evaluate(_ tick: Tick) -> Tick {
        pending = pending.compactMap { $0.evaluate(tick) }
        isStill = Self.gate.admits(tick)
        return tick
    }
}

enum ReadingScope: Equatable {
    case property(AssertableProperty, of: ResolvedAccessibilityTarget)

    case element(ResolvedAccessibilityTarget)

    case screen

    func reading(in interface: Interface) -> Int {
        var hasher = Hasher()
        switch self {
        case .screen:
            hasher.combine(interface.projectedElements)
        case .element(let target):
            for element in Self.matches(target, in: interface) {
                hasher.combine(element)
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
            guard !assertions.isEmpty else { return [.nothingNamed] }
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

import Foundation
import ThePlans

enum Tick {
    case elementsChanged(Interface)
    case screenChanged(ScreenFacts)
    case announcement(String)
    case noChange

    enum Kind: Equatable {
        case elementsChanged
        case screenChanged
        case announcement
        case noChange
    }

    var kind: Kind {
        switch self {
        case .elementsChanged: return .elementsChanged
        case .screenChanged: return .screenChanged
        case .announcement: return .announcement
        case .noChange: return .noChange
        }
    }

    var reading: Int {
        var hasher = Hasher()
        switch self {
        case .elementsChanged(let interface):
            hasher.combine(interface.projectedElements)
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

struct PendingPredicate: Equatable {
    enum Kind: Equatable {
        case elementsChanged(ResolvedAccessibilityPredicate?)
        case screenChanged(ResolvedScreenPredicate?)
        case announcement(ResolvedAnnouncementPredicate?)
        case noChange
    }

    let kind: Kind
    let scope: ReadingScope?

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

    var description: String {
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
        guard case .elementsChanged(let interface) = tick, let scope else { return tick.reading }
        return scope.reading(in: interface)
    }

    func matches(_ tick: Tick) -> Bool {
        switch (tick, kind) {
        case (.elementsChanged(let interface), .elementsChanged(let query?)):
            return query.matches(interface)
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

    static let nothingNamed = Self.change(
        before: .elementsChanged(),
        after: .elementsChanged()
    )

    var descriptions: [String] {
        switch state {
        case .presence(let predicate):
            return [predicate.description]
        case .awaitingBefore(let before, let after):
            return [before.description, after.description]
        case .awaitingAfter(let after, _):
            return [after.description]
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

package struct Expectation: Equatable {
    private var pending: [PendingStep]

    private static let gate = PendingPredicate.noChange

    private var isStill = false

    package init(_ authored: [ResolvedAccessibilityPredicate] = []) {
        pending = authored.flatMap(\.pendingSteps)
    }

    package var isMet: Bool { pending.isEmpty && isStill }

    package var outstanding: [String] {
        pending.flatMap(\.descriptions) + (isStill ? [] : [Self.gate.description])
    }

    package mutating func snapshot(_ interface: Interface) {
        evaluate(.elementsChanged(interface))
    }

    package mutating func empty(at timestamp: Date) {
        evaluate(.elementsChanged(Interface(timestamp: timestamp, tree: [])))
    }

    package mutating func screenChanged(_ facts: ScreenFacts) {
        evaluate(.screenChanged(facts))
    }

    package mutating func announcement(_ text: String) {
        evaluate(.announcement(text))
    }

    package mutating func noChange() {
        evaluate(.noChange)
    }

    private mutating func evaluate(_ tick: Tick) {
        pending = pending.compactMap { $0.evaluate(tick) }
        isStill = Self.gate.admits(tick)
    }
}

enum ReadingScope: Equatable {
    case property(ElementProperty, of: ResolvedAccessibilityTarget)

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

extension ElementProperty {
    func combine(_ element: HeistElement, into hasher: inout Hasher) {
        switch self {
        case .label: hasher.combine(element.label)
        case .identifier: hasher.combine(element.identifier)
        case .value: hasher.combine(element.value)
        case .hint: hasher.combine(element.hint)
        case .traits: hasher.combine(Set(element.traits))
        case .actions: hasher.combine(Set(element.actions))
        case .customContent: hasher.combine(element.customContent)
        case .rotors: hasher.combine(element.rotors?.map(\.name))
        case .frame, .activationPoint: break
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

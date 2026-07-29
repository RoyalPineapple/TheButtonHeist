import ThePlans

/// An execution-ready predicate program that consumes one event at a time.
///
/// Live execution constructs one expectation, then feeds it each observed event
/// exactly once. Retained evidence can reconstruct the same result by creating a
/// fresh expectation and feeding the recorded events in order.
package struct Expectation: Sendable, Equatable {
    private let pending: [Step]

    package init(
        _ predicates: [ObservationPredicate] = [],
        baseline: Observation.Snapshot? = nil,
        events: [Observation.Event] = []
    ) {
        let initial = Expectation(
            pending: predicates.flatMap(\.expectationSteps)
        )
        let withBaseline = baseline.map {
            initial.evaluating(.baseline($0))
        } ?? initial
        self = events.reduce(withBaseline) { expectation, event in
            expectation.evaluating(.event(event))
        }
    }

    private init(pending: [Step]) {
        self.pending = pending
    }

    /// Returns this expectation advanced by one newly published event.
    ///
    /// The event is never retained here. Observation history owns evidence;
    /// Expectation owns only the ordered predicate state still waiting.
    package func evaluating(_ event: Observation.Event) -> Expectation {
        evaluating(.event(event))
    }

    package func requiringNoChange() -> Expectation {
        guard !pending.contains(where: \.isNoChange) else { return self }
        return Expectation(pending: pending + [.current(.noChange)])
    }

    package enum Result: Sendable, Equatable {
        case satisfied
        case waiting(String)

        package var outstandingDescription: String? {
            guard case .waiting(let description) = self else { return nil }
            return description
        }
    }

    package var result: Result {
        guard let description = pending.first?.description else {
            return .satisfied
        }
        return .waiting(description)
    }

    package var isWaitingOnlyForNoChange: Bool {
        pending.count == 1 && pending[0].isNoChange
    }

    private func evaluating(_ input: Input) -> Expectation {
        var next: [Step] = []
        next.reserveCapacity(pending.count)

        for (index, step) in pending.enumerated() {
            switch step.evaluating(input) {
            case .indifferent:
                next.append(step)
            case .matched(let remainder):
                if let remainder {
                    next.append(remainder)
                }
            case .unmatched(let replacement):
                next.append(replacement ?? step)
                if index + 1 < pending.count {
                    next.append(contentsOf: pending[(index + 1)...])
                }
                return Expectation(pending: next)
            }
        }
        return Expectation(pending: next)
    }
}

private extension Expectation {
    enum Input {
        case baseline(Observation.Snapshot)
        case event(Observation.Event)

        var interface: Interface? {
            switch self {
            case .baseline(let snapshot), .event(.elementsChanged(let snapshot)):
                return snapshot.interface
            case .event(.screenChanged), .event(.notification), .event(.noChange):
                return nil
            }
        }

        var isScreenBoundary: Bool {
            guard case .event(.screenChanged) = self else { return false }
            return true
        }
    }

    /// The semantic slice compared by a temporal element assertion.
    enum Scope: Sendable, Equatable {
        case graph
        case target(ResolvedAccessibilityTarget)
        case property(
            AssertableProperty,
            of: ResolvedAccessibilityElementTarget
        )

        func semanticHash(in input: Input) -> SemanticHash {
            guard let interface = input.interface else {
                preconditionFailure("Expectation scope requires an interface reading")
            }
            return semanticHash(in: interface)
        }

        private func semanticHash(in interface: Interface) -> SemanticHash {
            let graph = AccessibilityTargetMatchGraph(interface: interface)
            switch self {
            case .graph:
                let input = AccessibilityTargetMatchInput(interface: interface)
                return Self.semanticHash(
                    elements: input.elements.lazy.map(\.element.semantics),
                    containers: input.containers.lazy.map(\.facts)
                )
            case .target(let target):
                let matches = graph.resolve(target)
                return Self.semanticHash(
                    elements: matches.elements.elements.lazy.map(\.semantics),
                    containers: matches.containers.lazy.map(\.facts)
                )
            case .property(let property, let target):
                let hashes = graph.resolve(target.accessibilityTarget)
                    .elements.elements.lazy
                    .map { property.semanticHash(of: $0.semantics) }
                return Self.semanticHash(hashes)
            }
        }

        private static func semanticHash(
            elements: some Sequence<HeistElement.Semantics>,
            containers: some Sequence<ContainerPredicateFacts>
        ) -> SemanticHash {
            var hasher = Hasher()
            hasher.combine(0)
            combine(elements.lazy.map(\.semanticHash), into: &hasher)
            hasher.combine(1)
            combine(containers.lazy.map(\.semanticHash), into: &hasher)
            return hasher.finalize()
        }

        private static func semanticHash(
            _ hashes: some Sequence<SemanticHash>
        ) -> SemanticHash {
            var hasher = Hasher()
            combine(hashes, into: &hasher)
            return hasher.finalize()
        }

        private static func combine(
            _ hashes: some Sequence<SemanticHash>,
            into hasher: inout Hasher
        ) {
            let ordered = hashes.sorted()
            hasher.combine(ordered.count)
            for hash in ordered {
                hasher.combine(hash)
            }
        }
    }

    /// One authored assertion and the part of it that remains.
    ///
    /// An event evaluates only the current case. Matching `before` captures its
    /// scoped semantic hash and produces `after`; that same event is never fed
    /// through the new case.
    enum Step: Sendable, Equatable {
        case current(ObservationPredicate)
        case before(
            ObservationPredicate,
            then: ObservationPredicate,
            scope: Scope
        )
        case after(
            ObservationPredicate,
            scope: Scope,
            beforeMatch: SemanticHash,
            restart: Before
        )

        struct Before: Sendable, Equatable {
            let predicate: ObservationPredicate
            let after: ObservationPredicate
            let scope: Scope
        }

        enum Evaluation: Sendable, Equatable {
            case indifferent
            case matched(Step?)
            case unmatched(Step?)
        }

        func evaluating(_ input: Input) -> Evaluation {
            switch self {
            case .current(let predicate):
                return predicate.evaluateCurrent(input)
            case .before(let predicate, let after, let scope):
                switch predicate.evaluateCurrent(input) {
                case .indifferent:
                    return .indifferent
                case .unmatched:
                    return .unmatched(nil)
                case .matched:
                    return .matched(.after(
                        after,
                        scope: scope,
                        beforeMatch: scope.semanticHash(in: input),
                        restart: Before(
                            predicate: predicate,
                            after: after,
                            scope: scope
                        )
                    ))
                }
            case .after(let predicate, let scope, let beforeMatch, let restart):
                if input.isScreenBoundary, case .property = scope {
                    return .unmatched(.before(
                        restart.predicate,
                        then: restart.after,
                        scope: restart.scope
                    ))
                }
                switch predicate.evaluateCurrent(input) {
                case .indifferent:
                    return .indifferent
                case .unmatched:
                    return .unmatched(nil)
                case .matched:
                    return scope.semanticHash(in: input) == beforeMatch
                        ? .unmatched(nil)
                        : .matched(nil)
                }
            }
        }

        var description: String {
            switch self {
            case .current(let predicate), .before(let predicate, _, _):
                return predicate.description
            case .after(let predicate, _, _, _):
                return predicate.description
            }
        }

        var isNoChange: Bool {
            guard case .current(.noChange) = self else { return false }
            return true
        }
    }
}

private extension ObservationPredicate {
    var expectationSteps: [Expectation.Step] {
        switch self {
        case .elementsChanged(let assertions):
            guard !assertions.isEmpty else {
                let anyElementEvent = ObservationPredicate.elementsChanged([])
                return [.before(anyElementEvent, then: anyElementEvent, scope: .graph)]
            }
            return assertions.map(\.expectationStep)
        case .notification, .noChange, .screenChanged:
            return [.current(self)]
        }
    }

    func evaluateCurrent(
        _ input: Expectation.Input
    ) -> Expectation.Step.Evaluation {
        switch (self, input) {
        case (.elementsChanged(let assertions), _):
            guard let interface = input.interface else {
                return .indifferent
            }
            guard let assertion = assertions.first else {
                return .matched(nil)
            }
            guard assertions.count == 1 else {
                preconditionFailure("One expectation step evaluates one element predicate")
            }
            return assertion.matchesCurrent(interface)
                ? .matched(nil)
                : .unmatched(nil)
        case (.notification(let predicate), .event(.notification(let notification))):
            return predicate.matches(notification) ? .matched(nil) : .unmatched(nil)
        case (.noChange, .event(.noChange)):
            return .matched(nil)
        case (.screenChanged(let predicate), .event(.screenChanged(let screen))):
            return predicate.matches(screen) ? .matched(nil) : .unmatched(nil)
        case (.notification, _),
             (.noChange, _),
             (.screenChanged, _):
            return .indifferent
        }
    }
}

private extension ResolvedElementAssertion {
    var expectationStep: Expectation.Step {
        switch self {
        case .exists(let target):
            return .current(.elementsChanged([.exists(target)]))
        case .missing(let target):
            return .current(.elementsChanged([.missing(target)]))
        case .appeared(let target):
            return .before(
                .elementsChanged([.missing(target)]),
                then: .elementsChanged([.exists(target)]),
                scope: .target(target)
            )
        case .disappeared(let target):
            return .before(
                .elementsChanged([.exists(target)]),
                then: .elementsChanged([.missing(target)]),
                scope: .target(target)
            )
        case .updated(let target, let change):
            return .before(
                .elementsChanged([.exists(
                    target.and(change.value.predicateChecks(.before)).accessibilityTarget
                )]),
                then: .elementsChanged([.exists(
                    target.and(change.value.predicateChecks(.after)).accessibilityTarget
                )]),
                scope: .property(change.property, of: target)
            )
        }
    }

    func matchesCurrent(_ interface: Interface) -> Bool {
        let graph = AccessibilityTargetMatchGraph(interface: interface)
        switch self {
        case .exists(let target):
            return !graph.resolve(target).isEmpty
        case .missing(let target):
            return graph.resolve(target).isEmpty
        case .appeared, .disappeared, .updated:
            preconditionFailure("Temporal assertions must decompose before evaluation")
        }
    }
}

private enum ElementPropertyChangeSide {
    case before
    case after

    func pick<Checker>(_ change: PropertyChangeCore<Checker>) -> Checker? {
        switch self {
        case .before: return change.before
        case .after: return change.after
        }
    }
}

private extension ResolvedElementPropertyChangeValue {
    func predicateChecks(
        _ side: ElementPropertyChangeSide
    ) -> [ResolvedElementPredicateCheck] {
        switch self {
        case .value(let change):
            return side.pick(change).map { [.value($0)] } ?? []
        case .hint(let change):
            return side.pick(change).map { [.hint($0)] } ?? []
        case .customContent(let change):
            return side.pick(change).map { [.customContent($0)] } ?? []
        case .traits(let change):
            return side.pick(change).map {
                setPredicateChecks(
                    $0.include,
                    $0.exclude,
                    as: ResolvedElementPredicateCheck.traits
                )
            } ?? []
        case .actions(let change):
            return side.pick(change).map {
                setPredicateChecks(
                    $0.include,
                    $0.exclude,
                    as: ResolvedElementPredicateCheck.actions
                )
            } ?? []
        case .rotors(let change):
            return side.pick(change).map {
                setPredicateChecks(
                    $0.include,
                    $0.exclude,
                    as: ResolvedElementPredicateCheck.rotors
                )
            } ?? []
        }
    }

    private func setPredicateChecks<Values: Collection>(
        _ include: Values,
        _ exclude: Values,
        as check: (Values) -> ResolvedElementPredicateCheck
    ) -> [ResolvedElementPredicateCheck] {
        (include.isEmpty ? [] : [check(include)])
            + (exclude.isEmpty ? [] : [.exclude(check(exclude))])
    }
}

extension NotificationPredicate.Execution {
    package func matches(_ notification: Observation.Notification) -> Bool {
        let textMatches = text.map { match in
            notification.text.map(match.matches) ?? false
        } ?? true
        let elementMatches = element.map { predicate in
            notification.element?.matches(predicate) ?? false
        } ?? true
        return textMatches && elementMatches
    }
}

extension HeistElement.Semantics: SemanticallyHashable {
    public func hashSemantic(into hasher: inout Hasher) {
        hasher.combine(self)
    }
}

extension ContainerPredicateFacts: SemanticallyHashable {
    public func hashSemantic(into hasher: inout Hasher) {
        hasher.combine(self)
    }
}

private extension AssertableProperty {
    func semanticHash(of semantics: HeistElement.Semantics) -> SemanticHash {
        var hasher = Hasher()
        switch self {
        case .value:
            hasher.combine(semantics.assertable.value)
        case .traits:
            hasher.combine(semantics.assertable.traits)
        case .hint:
            hasher.combine(semantics.assertable.hint)
        case .actions:
            hasher.combine(semantics.assertable.actions)
        case .customContent:
            hasher.combine(semantics.assertable.customContent)
        case .rotors:
            hasher.combine(semantics.assertable.rotors)
        }
        return hasher.finalize()
    }
}

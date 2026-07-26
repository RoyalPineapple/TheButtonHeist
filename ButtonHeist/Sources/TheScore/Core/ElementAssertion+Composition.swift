import ThePlans

/// A delta is two presence predicates in a row.
///
/// There is no separate delta evaluator and no baseline: `appeared` is
/// `missing` then `exists`, and what makes the pair a *change* is that the
/// first drained before the second was asked.
///
///     appeared(X)            missing(X)        then  exists(X)
///     disappeared(X)         exists(X)         then  missing(X)
///     updated(X, v1?, v2)    exists(X and v1?) then  exists(X and v2)
///
/// So `disappeared("Ready")` followed by `appeared("Ready")` says what it looks
/// like it says — the same two predicates, ordered — and `updated` is not a
/// third kind of thing: the property is composed onto the target, which is what
/// `and(_:)` already does for the authored form. The before value is optional;
/// without one the first search is the bare anchor, which is exactly what "it
/// was there, in any state" means.
extension ResolvedElementAssertion {
    var composed: [ResolvedAccessibilityPredicate] {
        switch self {
        case .exists(let target):
            return [.exists(target)]
        case .missing(let target):
            return [.missing(target)]
        case .appeared(let target):
            return [.missing(target), .exists(target)]
        case .disappeared(let target):
            return [.exists(target), .missing(target)]
        case .updated(let target, let change):
            return [
                .exists(target.and(change.value.checks(.before))),
                .exists(target.and(change.value.checks(.after))),
            ]
        }
    }
}

extension ResolvedAccessibilityTarget {
    /// Whether anything in this graph matches.
    func found(in interface: Interface) -> Bool {
        !AccessibilityTargetMatchGraph(interface: interface)
            .resolve(self).elements.elements.isEmpty
    }

    /// The same target, carrying more checks.
    ///
    /// The resolved twin of the authored `and(_:)`. This is the whole of what
    /// makes `updated` ordinary: a property is not a change record to be
    /// compared, it is more checks on the target. An empty list is the
    /// identity, which is what makes the optional `before` free — no checks to
    /// add means the anchor alone.
    /// A scoped target carries them on the element it names, not on the scope:
    /// `within(list, .label("Qty")).and(.value("3"))` asks for the Qty *in* the
    /// list whose value is 3. Returning `self` for those would drop the checks
    /// silently and leave `updated` satisfied by any Qty at any value.
    func and(_ checks: [ResolvedElementPredicateCheck]) -> ResolvedAccessibilityTarget {
        guard !checks.isEmpty else { return self }
        switch self {
        case .predicate(let predicate, let ordinal):
            return .predicate(ResolvedElementPredicate(predicate.checks + checks), ordinal: ordinal)
        case .within(let container, let target):
            return .within(container: container, target: target.and(checks))
        case .container:
            return self
        }
    }
}

extension ResolvedElementPropertyChangeValue {
    /// The checks this property constrains on the given side.
    ///
    /// Set-valued properties carry both an include and an exclude, and the
    /// predicate vocabulary already has both — `.exclude` wraps any check — so
    /// each side can turn into two. Empty sets are dropped rather than emitted:
    /// an empty include is vacuously true, so an *excluded* empty set would be
    /// unsatisfiable, and dropping it is what makes "only say what changed"
    /// work.
    ///
    /// `frame` and `activationPoint` yield none: geometry is not something an
    /// element predicate can ask for, so the anchor alone carries that side.
    /// Those two still work as `updated` assertions, they just say no more than
    /// "this element was here, and is still here".
    func checks(_ side: PropertyChangeSide) -> [ResolvedElementPredicateCheck] {
        switch self {
        case .value(let change):
            return side.pick(change).map { [.value($0)] } ?? []
        case .hint(let change):
            return side.pick(change).map { [.hint($0)] } ?? []
        case .customContent(let change):
            return side.pick(change).map { [.customContent($0)] } ?? []
        case .traits(let change):
            return side.pick(change).map { setChecks($0.include, $0.exclude, as: ResolvedElementPredicateCheck.traits) } ?? []
        case .actions(let change):
            return side.pick(change).map { setChecks($0.include, $0.exclude, as: ResolvedElementPredicateCheck.actions) } ?? []
        case .rotors(let change):
            return side.pick(change).map { setChecks($0.include, $0.exclude, as: ResolvedElementPredicateCheck.rotors) } ?? []
        case .frame, .activationPoint:
            return []
        }
    }

    private func setChecks<S: Collection>(
        _ include: S,
        _ exclude: S,
        as check: (S) -> ResolvedElementPredicateCheck
    ) -> [ResolvedElementPredicateCheck] {
        (include.isEmpty ? [] : [check(include)])
            + (exclude.isEmpty ? [] : [.exclude(check(exclude))])
    }
}

enum PropertyChangeSide {
    case before
    case after

    fileprivate func pick<T>(_ change: PropertyChangeCore<T>) -> T? {
        switch self {
        case .before: return change.before
        case .after: return change.after
        }
    }
}

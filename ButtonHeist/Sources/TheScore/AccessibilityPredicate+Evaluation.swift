import ThePlans
import Foundation

// MARK: - Unified Evaluation

/// The single evaluation surface for every predicate kind. `state` matches the
/// current capture; `changed` reads the baseline→current diff. This is the
/// engine a wait (predicate + deadline), an `expect` slot, and a future
/// search/while loop all share.
public extension AccessibilityPredicate {
    /// Evaluate against an observed interface and (for change predicates) a diff.
    /// - Parameters:
    ///   - currentElements: latest observed interface elements (used by `state`).
    ///   - delta: the baseline→current diff (used by `changed`).
    func evaluate(
        currentElements: [HeistElement],
        delta: AccessibilityTrace.Delta? = nil
    ) -> ExpectationResult {
        switch self {
        case .state(let stateClause):
            let outcome = stateClause.evaluate(in: currentElements)
            return ExpectationResult(met: outcome.met, predicate: self, actual: outcome.actual)
        case .changed(let change):
            return change.evaluate(delta: delta)
        }
    }
}

// MARK: - ActionResult Validation

public extension AccessibilityPredicate {
    /// Check this predicate against an `ActionResult`.
    ///
    /// `state` evaluates against the result's final-capture interface;
    /// `changed` evaluates against the result's endpoint delta. Change
    /// predicates read self-describing deltas — `disappeared`/`updated` carry
    /// the affected element directly, so no pre-action element resolution is
    /// needed.
    func validate(against result: ActionResult) -> ExpectationResult {
        guard let trace = result.accessibilityTrace else {
            return ExpectationResult(
                met: false,
                predicate: self,
                actual: "no observed accessibility trace"
            )
        }
        return evaluate(
            currentElements: trace.endpointCurrentElements,
            delta: trace.endpointDelta
        )
    }
}

private extension AccessibilityTrace {
    /// Projected elements of the final capture — the post-action interface.
    var endpointCurrentElements: [HeistElement] {
        captures.last?.interface.projectedElements ?? []
    }
}

// MARK: - State Evaluation

public extension AccessibilityPredicate.State {
    /// Convenience boolean check against an observed interface.
    func evaluatePresence(in elements: [HeistElement]) -> Bool {
        evaluate(in: elements).met
    }

    /// Evaluate this state against a single observed interface. For `.all`,
    /// every child state must hold against the same `elements`.
    func evaluate(in elements: [HeistElement]) -> (met: Bool, actual: String?) {
        switch self {
        case .present(let predicate):
            let met = predicate.anyMatch(in: elements)
            return (met, met ? nil : "no element matches \(predicate)")
        case .absent(let predicate):
            let met = !predicate.anyMatch(in: elements)
            return (met, met ? nil : "still present: \(predicate)")
        case .presentTarget(let target):
            let met = target.isPresent(in: elements)
            return (met, met ? nil : "target not present: \(target)")
        case .absentTarget(let target):
            let met = !target.isPresent(in: elements)
            return (met, met ? nil : "target still present: \(target)")
        case .all(let states):
            guard !states.isEmpty else {
                return (false, "all predicate has no child states")
            }
            let failures = states.compactMap { state -> String? in
                let outcome = state.evaluate(in: elements)
                return outcome.met ? nil : (outcome.actual ?? state.description)
            }
            return (failures.isEmpty, failures.isEmpty ? nil : failures.joined(separator: "; "))
        }
    }
}

private extension ElementTarget {
    func isPresent(in elements: [HeistElement]) -> Bool {
        switch self {
        case .predicate(let predicate, let ordinal):
            let matches = elements.filter { predicate.matches($0) }
            guard let ordinal else { return !matches.isEmpty }
            return matches.indices.contains(ordinal)
        }
    }
}

// MARK: - Change Evaluation

public extension AccessibilityPredicate.Change {
    func evaluate(
        delta: AccessibilityTrace.Delta?
    ) -> ExpectationResult {
        let result: ExpectationResult
        switch self {
        case .screen(let stateClause):
            result = Self.evaluateScreen(where: stateClause, delta: delta)
        case .elements:
            result = ExpectationResult(
                met: delta?.satisfiesElementsChanged == true,
                predicate: nil,
                actual: delta?.kindDescription ?? "noTrace"
            )
        case .appeared(let predicate):
            result = Self.evaluateAppeared(predicate: predicate, delta: delta)
        case .disappeared(let predicate):
            result = Self.evaluateDisappeared(predicate: predicate, delta: delta)
        case .updated(let update):
            result = Self.evaluateUpdated(update: update, delta: delta)
        }
        return ExpectationResult(met: result.met, predicate: .changed(self), actual: result.actual)
    }

    private static func evaluateScreen(
        where stateClause: AccessibilityPredicate.State?,
        delta: AccessibilityTrace.Delta?
    ) -> ExpectationResult {
        guard case .screenChanged(let payload)? = delta else {
            return ExpectationResult(met: false, predicate: nil, actual: delta?.kindDescription ?? "noTrace")
        }
        guard let stateClause else {
            return ExpectationResult(met: true, predicate: nil, actual: AccessibilityTrace.DeltaKind.screenChanged.rawValue)
        }
        let outcome = stateClause.evaluate(in: payload.newInterface.projectedElements)
        return ExpectationResult(
            met: outcome.met,
            predicate: nil,
            actual: outcome.met ? nil : "screen changed but new interface failed: \(outcome.actual ?? stateClause.description)"
        )
    }

    private static func evaluateAppeared(
        predicate: ElementPredicate,
        delta: AccessibilityTrace.Delta?
    ) -> ExpectationResult {
        let added = delta?.elementEdits.added ?? []
        if !added.isEmpty {
            if added.contains(where: { predicate.matches($0) }) {
                return ExpectationResult(met: true, predicate: nil)
            }
            let labels = added.compactMap(\.label).prefix(5).joined(separator: ", ")
            return ExpectationResult(met: false, predicate: nil, actual: "added: [\(labels)]")
        }
        if case .screenChanged(let payload)? = delta {
            if payload.newInterface.projectedElements.contains(where: { predicate.matches($0) }) {
                return ExpectationResult(met: true, predicate: nil)
            }
            return ExpectationResult(met: false, predicate: nil, actual: "screen changed but element not found in new interface")
        }
        return ExpectationResult(met: false, predicate: nil, actual: "no elements added")
    }

    private static func evaluateDisappeared(
        predicate: ElementPredicate,
        delta: AccessibilityTrace.Delta?
    ) -> ExpectationResult {
        let removed = delta?.elementEdits.removed ?? []
        if !removed.isEmpty {
            if removed.contains(where: { predicate.matches($0) }) {
                return ExpectationResult(met: true, predicate: nil)
            }
            let labels = removed.compactMap(\.label).prefix(5).joined(separator: ", ")
            return ExpectationResult(met: false, predicate: nil, actual: "removed: [\(labels)]")
        }
        if case .screenChanged(let payload)? = delta {
            let stillPresent = payload.newInterface.projectedElements.contains { predicate.matches($0) }
            if !stillPresent {
                return ExpectationResult(met: true, predicate: nil)
            }
            return ExpectationResult(
                met: false,
                predicate: nil,
                actual: "screen changed but element still present in new interface"
            )
        }
        return ExpectationResult(met: false, predicate: nil, actual: "no elements removed")
    }

    private static func evaluateUpdated(
        update: ElementUpdatePredicate,
        delta: AccessibilityTrace.Delta?
    ) -> ExpectationResult {
        let updates = delta?.elementEdits.updated ?? []
        guard !updates.isEmpty else {
            return ExpectationResult(met: false, predicate: nil, actual: "no element updates")
        }
        for edit in updates {
            if let elementPredicate = update.element {
                guard elementPredicate.matches(edit.element) else { continue }
            }
            let targetChanges: [PropertyChange]
            if let property = update.property {
                targetChanges = edit.changes.filter { $0.property == property }
                if targetChanges.isEmpty { continue }
            } else {
                targetChanges = edit.changes
            }
            let matchingChanges: [PropertyChange]
            if update.from != nil || update.to != nil {
                matchingChanges = targetChanges.filter { change in
                    if let from = update.from, change.old != from { return false }
                    if let to = update.to, change.new != to { return false }
                    return true
                }
                guard !matchingChanges.isEmpty else { continue }
            } else {
                matchingChanges = targetChanges
            }
            return ExpectationResult(
                met: true,
                predicate: nil,
                actual: Self.describeUpdate(edit, changes: matchingChanges)
            )
        }
        let observed = updates.map { edit in
            Self.describeUpdate(edit, changes: edit.changes)
        }.joined(separator: "; ")
        return ExpectationResult(met: false, predicate: nil, actual: observed)
    }

    private static func describeUpdate(_ edit: ElementUpdate, changes: [PropertyChange]) -> String {
        let properties = changes.map { "\($0.property.rawValue): \($0.old ?? "nil") → \($0.new ?? "nil")" }
        let name = edit.element.label ?? edit.element.description
        return "\(name): \(properties.joined(separator: ", "))"
    }
}

// MARK: - Delta Facts

private extension AccessibilityTrace.Delta {
    var kindDescription: String {
        switch self {
        case .noChange: return AccessibilityTrace.DeltaKind.noChange.rawValue
        case .elementsChanged: return AccessibilityTrace.DeltaKind.elementsChanged.rawValue
        case .screenChanged: return AccessibilityTrace.DeltaKind.screenChanged.rawValue
        }
    }

    var satisfiesElementsChanged: Bool {
        switch self {
        case .noChange: return false
        case .elementsChanged, .screenChanged: return true
        }
    }

    var elementEdits: ElementEdits {
        if case .elementsChanged(let payload) = self { return payload.edits }
        return ElementEdits()
    }
}

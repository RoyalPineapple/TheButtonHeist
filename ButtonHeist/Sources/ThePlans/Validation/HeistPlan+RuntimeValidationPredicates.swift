import Foundation

extension HeistPlanRuntimeSafetyValidator {
    mutating func validatePredicate<Context>(
        _ predicate: AccessibilityPredicate<Context>,
        path: String,
        depth: Int,
        scope: HeistReferenceScope
    ) {
        validatePredicateNode(predicate.node, path: path, depth: depth, scope: scope)
    }

    mutating func validatePredicateNode(
        _ node: AccessibilityPredicateNode,
        path: String,
        depth: Int,
        scope: HeistReferenceScope
    ) {
        checkPredicateDepth(depth, path: path)
        switch node {
        case .exists(let target), .missing(let target),
             .appeared(let target), .disappeared(let target):
            validateTarget(target, path: "\(path).target", scope: scope)
        case .announcement(let announcement):
            validateString(announcement.match, path: "\(path).match", role: "announcement")
        case .changed(let predicate):
            validatePredicateNode(predicate, path: "\(path).changed", depth: depth + 1, scope: scope)
        case .noChange:
            break
        case .screen(let assertions):
            validateAllChildCount(assertions.count, path: "\(path).assertions")
            for (index, assertion) in assertions.enumerated() {
                validatePredicateNode(
                    assertion,
                    path: "\(path).assertions[\(index)]",
                    depth: depth + 1,
                    scope: scope
                )
            }
        case .elements(let assertions):
            validateAllChildCount(assertions.count, path: "\(path).assertions")
            for (index, assertion) in assertions.enumerated() {
                validatePredicateNode(
                    assertion,
                    path: "\(path).assertions[\(index)]",
                    depth: depth + 1,
                    scope: scope
                )
            }
        case .updated(let target, let change):
            validateTarget(target, path: "\(path).target", scope: scope)
            validatePropertyChange(change, path: "\(path).change", scope: scope)
        }
    }
    mutating func validatePropertyChange(
        _ change: AnyPropertyChange?,
        path: String
    ) {
        guard let change else { return }
        switch change {
        case .value(let change):
            validateStringPropertyChange(change, path: path)
        case .traits:
            break
        case .hint(let change):
            validateStringPropertyChange(change, path: path)
        case .actions, .frame, .activationPoint:
            break
        case .customContent(let change):
            validateNestedStringPropertyChange(change, path: path)
        case .rotors(let change):
            validateNestedStringPropertyChange(change, path: path)
        }
    }

    mutating func validateStringPropertyChange<P: ElementPropertyKind>(
        _ change: ElementPropertyChange<P>,
        path: String
    ) where P.Checker == StringMatch<String> {
        validateString(change.before, path: "\(path).before", role: "element update before value")
        validateString(change.after, path: "\(path).after", role: "element update after value")
    }

    mutating func validatePropertyChange(
        _ change: AnyPropertyChangeExpr?,
        path: String,
        scope: HeistReferenceScope
    ) {
        guard let change else { return }
        switch change {
        case .value(let change):
            validateStringPropertyChange(change, path: path, scope: scope)
        case .traits:
            break
        case .hint(let change):
            validateStringPropertyChange(change, path: path, scope: scope)
        case .actions, .frame, .activationPoint:
            break
        case .customContent(let change):
            validateNestedStringPropertyChange(change, path: path, scope: scope)
        case .rotors(let change):
            validateNestedStringPropertyChange(change, path: path, scope: scope)
        }
    }

    mutating func validateStringPropertyChange<P: ElementPropertyKind>(
        _ change: ElementPropertyChangeExpr<P>,
        path: String,
        scope: HeistReferenceScope
    ) where P.ExprChecker == StringMatch<StringExpr> {
        if let before = change.before {
            validateString(before, path: "\(path).before", scope: scope)
        }
        if let after = change.after {
            validateString(after, path: "\(path).after", scope: scope)
        }
    }

    private mutating func validateNestedStringPropertyChange<P: ElementPropertyKind>(
        _ change: ElementPropertyChange<P>,
        path: String
    ) where P.Checker: NestedStringMatchContainer, P.Checker.Payload == String {
        if let before = change.before {
            validateNestedStrings(before, path: "\(path).before")
        }
        if let after = change.after {
            validateNestedStrings(after, path: "\(path).after")
        }
    }

    private mutating func validateNestedStrings<Container: NestedStringMatchContainer>(
        _ container: Container,
        path: String
    ) where Container.Payload == String {
        for nested in container.nestedStringMatches {
            validateString(nested.match, path: "\(path).\(nested.path)", role: nested.role)
        }
    }

    private mutating func validateNestedStringPropertyChange<P: ElementPropertyKind>(
        _ change: ElementPropertyChangeExpr<P>,
        path: String,
        scope: HeistReferenceScope
    ) where P.ExprChecker: NestedStringMatchContainer, P.ExprChecker.Payload == StringExpr {
        if let before = change.before {
            validateNestedStrings(before, path: "\(path).before", scope: scope)
        }
        if let after = change.after {
            validateNestedStrings(after, path: "\(path).after", scope: scope)
        }
    }

    private mutating func validateNestedStrings<Container: NestedStringMatchContainer>(
        _ container: Container,
        path: String,
        scope: HeistReferenceScope
    ) where Container.Payload == StringExpr {
        for nested in container.nestedStringMatches {
            validateString(nested.match, path: "\(path).\(nested.path)", scope: scope)
        }
    }

    mutating func checkPredicateDepth(_ depth: Int, path: String) {
        if depth > limits.maxPredicateDepth {
            fail(
                path: path,
                contract: "max predicate depth",
                observed: "depth \(depth)",
                correction: "Use predicates nested \(limits.maxPredicateDepth) levels or fewer."
            )
        }
    }

    mutating func validateAllChildCount(_ count: Int, path: String) {
        if count > limits.maxAllPredicateChildren {
            fail(
                path: path,
                contract: "max .all child count",
                observed: "\(count) children",
                correction: "Use \(limits.maxAllPredicateChildren) child predicates or fewer."
            )
        }
    }

}

private struct NestedStringMatch<Payload: StringMatchPayload & Codable> {
    let path: String
    let role: String
    let match: StringMatch<Payload>
}

private protocol NestedStringMatchContainer {
    associatedtype Payload: StringMatchPayload & Codable

    var nestedStringMatches: [NestedStringMatch<Payload>] { get }
}

extension CustomContentMatch: NestedStringMatchContainer {
    fileprivate var nestedStringMatches: [NestedStringMatch<Value>] {
        [
            label.map { NestedStringMatch(path: "label", role: "custom content label", match: $0) },
            value.map { NestedStringMatch(path: "value", role: "custom content value", match: $0) },
        ].compactMap { $0 }
    }
}

extension RotorSetMatch: NestedStringMatchContainer {
    fileprivate var nestedStringMatches: [NestedStringMatch<Value>] {
        include.enumerated().map { index, match in
            NestedStringMatch(path: "include[\(index)]", role: "rotor include", match: match)
        } + exclude.enumerated().map { index, match in
            NestedStringMatch(path: "exclude[\(index)]", role: "rotor exclude", match: match)
        }
    }
}

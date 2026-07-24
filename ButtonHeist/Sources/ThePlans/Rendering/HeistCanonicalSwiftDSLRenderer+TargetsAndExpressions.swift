import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func renderCorrection(target: AccessibilityTarget) throws -> String {
        try render(target: target, environment: .preservingReferences)
    }

    func renderCorrection(target: AccessibilityTarget, addingOrdinal ordinal: Int) throws -> String {
        try render(
            target: target.replacingInnermostOrdinal(with: ordinal),
            environment: .preservingReferences
        )
    }

    func render(target: AccessibilityTarget, environment: RenderEnvironment) throws -> String {
        switch target {
        case .predicate(let predicate, let ordinal):
            let renderedPredicate = try render(predicate: predicate, environment: environment)
            guard let ordinal else { return renderedPredicate }
            return ".target(\(renderedPredicate), ordinal: \(ordinal))"
        case .container(let predicate, let ordinal):
            let rendered = try render(container: predicate, environment: environment)
            return ordinal.map { ".container(\(rendered), ordinal: \($0))" }
                ?? ".container(\(rendered))"
        case .ref(let reference):
            guard environment.accepts(target: reference) else {
                throw HeistCanonicalSwiftDSLError.unresolvedTargetReference(reference.rawValue)
            }
            return reference.rawValue
        case .within(let container, let target):
            return try ".within(container: \(render(container: container, environment: environment)), "
                + "\(render(target: target, environment: environment)))"
        }
    }

    func render(container: ContainerPredicate, environment: RenderEnvironment) throws -> String {
        let checks = container.core.checks
        if let shorthand = try renderSingleContainerCheck(checks, environment: environment) {
            return shorthand
        }
        if let dataTable = renderDataTable(checks) {
            return dataTable
        }
        let rendered = try checks.map {
            try renderContainerCheck($0, environment: environment)
        }
        return ".matching(\(rendered.joined(separator: ", ")))"
    }

    private func renderSingleContainerCheck(
        _ checks: NonEmptyArray<ContainerPredicateCheckCore<AuthoredString>>,
        environment: RenderEnvironment
    ) throws -> String? {
        guard checks.count == 1 else { return nil }
        switch checks[0] {
        case .type(.none):
            return ".none"
        case .type(.semanticGroup):
            return ".semanticGroup"
        case .type(.list):
            return ".list"
        case .type(.landmark):
            return ".landmark"
        case .type(.dataTable):
            return ".dataTable()"
        case .type(.tabBar):
            return ".tabBar"
        case .type(.series):
            return ".type(.series)"
        case .identifier(let match):
            return try ".identifier(\(renderStringArgument(match, environment: environment)))"
        case .semantic(let predicate):
            return try renderSemanticContainerPredicate(predicate, environment: environment)
        case .scrollable(true):
            return ".scrollable(true)"
        case .actions(let actions):
            return ".actions(\(renderContainerActions(actions)))"
        case .rowCount, .columnCount, .modalBoundary, .scrollable(false):
            return nil
        }
    }

    private func renderDataTable(
        _ checks: NonEmptyArray<ContainerPredicateCheckCore<AuthoredString>>
    ) -> String? {
        let hasDataTableType = checks.contains {
            if case .type(.dataTable) = $0 { return true }
            return false
        }
        let hasOnlyTableChecks = checks.allSatisfy {
            switch $0 {
            case .type(.dataTable), .rowCount, .columnCount:
                return true
            case .type, .identifier, .semantic, .modalBoundary, .scrollable, .actions:
                return false
            }
        }
        guard hasDataTableType, hasOnlyTableChecks else { return nil }

        var arguments: [String] = []
        if let rowCount = checks.compactMap({
            if case .rowCount(let count) = $0 { return count.value }
            return nil
        }).first {
            arguments.append("rowCount: .init(\(rowCount))")
        }
        if let columnCount = checks.compactMap({
            if case .columnCount(let count) = $0 { return count.value }
            return nil
        }).first {
            arguments.append("columnCount: .init(\(columnCount))")
        }
        return ".dataTable(\(arguments.joined(separator: ", ")))"
    }

    private func renderContainerCheck(
        _ check: ContainerPredicateCheckCore<AuthoredString>,
        environment: RenderEnvironment
    ) throws -> String {
        switch check {
        case .type(let type):
            return ".type(.\(type.rawValue))"
        case .identifier(let match):
            return try ".identifier(\(renderStringArgument(match, environment: environment)))"
        case .semantic(let predicate):
            return try ".semantic(\(renderSemanticContainerPredicate(predicate, environment: environment)))"
        case .rowCount(let count):
            return ".rowCount(.init(\(count.value)))"
        case .columnCount(let count):
            return ".columnCount(.init(\(count.value)))"
        case .modalBoundary(let required):
            return ".modalBoundary(\(required))"
        case .scrollable(let required):
            return ".scrollable(\(required))"
        case .actions(let actions):
            return ".actions(\(renderContainerActions(actions)))"
        }
    }

    private func renderSemanticContainerPredicate(
        _ predicate: SemanticContainerPredicateCore<AuthoredString>,
        environment: RenderEnvironment
    ) throws -> String {
        switch predicate {
        case .label(let match):
            return try ".label(\(renderStringArgument(match, environment: environment)))"
        case .value(let match):
            return try ".value(\(renderStringArgument(match, environment: environment)))"
        }
    }

    private func renderContainerActions(_ actions: ContainerPredicateActions) -> String {
        let values = actions.values.sorted { $0.canonicalSortKey < $1.canonicalSortKey }
        return ".init(\(values.map(render(action:)).joined(separator: ", ")))"
    }

    func render(
        predicate: ElementPredicate,
        environment: RenderEnvironment
    ) throws -> String {
        let checks = predicate.core.checks
        if let shorthand = try renderSingleCheckTarget(checks, environment: environment) {
            return shorthand
        }
        let rendered = try checks.map {
            try renderPredicateCheck($0, environment: environment)
        }
        return ".element(\(rendered.joined(separator: ", ")))"
    }

    private func renderSingleCheckTarget(
        _ checks: [ElementPredicateCheckCore<AuthoredString>],
        environment: RenderEnvironment
    ) throws -> String? {
        guard checks.count == 1 else { return nil }
        switch checks[0] {
        case .label(let match):
            return try ".label(\(renderStringArgument(match, environment: environment)))"
        case .identifier(let match):
            return try ".identifier(\(renderStringArgument(match, environment: environment)))"
        case .value(let match):
            return try ".value(\(renderStringArgument(match, environment: environment)))"
        case .hint(let match):
            return try ".hint(\(renderStringArgument(match, environment: environment)))"
        case .actions(let actions):
            return ".actions(\(renderActionArray(actions)))"
        case .customContent(let match):
            return try ".customContent(\(render(customContent: match, environment: environment)))"
        case .rotors(let matches):
            return try ".rotors(\(renderStringMatchArray(matches, environment: environment)))"
        case .exclude(let check):
            return try ".exclude(\(renderPredicateCheck(check, environment: environment)))"
        case .traits:
            return nil
        }
    }

    private func renderPredicateCheck(
        _ check: ElementPredicateCheckCore<AuthoredString>,
        environment: RenderEnvironment
    ) throws -> String {
        switch check {
        case .label(let match):
            return try ".label(\(renderStringArgument(match, environment: environment)))"
        case .identifier(let match):
            return try ".identifier(\(renderStringArgument(match, environment: environment)))"
        case .value(let match):
            return try ".value(\(renderStringArgument(match, environment: environment)))"
        case .hint(let match):
            return try ".hint(\(renderStringArgument(match, environment: environment)))"
        case .traits(let traits):
            return ".traits(\(renderTraitArray(traits)))"
        case .actions(let actions):
            return ".actions(\(renderActionArray(actions)))"
        case .customContent(let match):
            return try ".customContent(\(render(customContent: match, environment: environment)))"
        case .rotors(let matches):
            return try ".rotors(\(renderStringMatchArray(matches, environment: environment)))"
        case .exclude(let check):
            return try ".exclude(\(renderPredicateCheck(check, environment: environment)))"
        }
    }

    func renderTraitArray(_ traits: Set<HeistTrait>) -> String {
        "[\(traits.canonicalHeistTraitArray.map { ".\($0.rawValue)" }.joined(separator: ", "))]"
    }

    func renderStringArgument(
        _ match: StringMatchCore<AuthoredString>,
        environment: RenderEnvironment
    ) throws -> String {
        try renderStringMatch(match, environment: environment)
    }

    private func renderStringMatch(
        _ match: StringMatchCore<AuthoredString>,
        environment: RenderEnvironment
    ) throws -> String {
        switch match {
        case .exact(let value):
            return try render(string: value, environment: environment)
        case .contains(let value):
            return try ".contains(\(render(string: value, environment: environment)))"
        case .prefix(let value):
            return try ".prefix(\(render(string: value, environment: environment)))"
        case .suffix(let value):
            return try ".suffix(\(render(string: value, environment: environment)))"
        case .isEmpty:
            return ".isEmpty"
        }
    }

    func render(string: AuthoredString, environment: RenderEnvironment) throws -> String {
        switch string {
        case .literal(let literal):
            return quote(literal)
        case .ref(let reference):
            guard environment.accepts(string: reference) else {
                throw HeistCanonicalSwiftDSLError.unresolvedStringReference(reference.rawValue)
            }
            return reference.rawValue
        }
    }

    func render(point: ScreenPoint) -> String {
        "ScreenPoint(x: \(decimal(point.x)), y: \(decimal(point.y)))"
    }

    func render(unitPoint: UnitPoint) -> String {
        "UnitPoint(x: \(decimal(unitPoint.x)), y: \(decimal(unitPoint.y)))"
    }

    func render(duration: GestureDuration) -> String {
        decimal(duration.seconds)
    }
}

private extension AccessibilityTarget {
    func replacingInnermostOrdinal(with ordinal: Int) -> AccessibilityTarget {
        switch self {
        case .predicate(let predicate, _):
            return .predicate(predicate, ordinal: ordinal)
        case .container(let predicate, _):
            return .container(predicate, ordinal: ordinal)
        case .ref:
            return self
        case .within(let container, let target):
            return .within(
                container: container,
                target: target.replacingInnermostOrdinal(with: ordinal)
            )
        }
    }
}

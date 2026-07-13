import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func renderCorrection(target: AccessibilityTarget) -> String {
        switch target {
        case .predicate(let predicate, let ordinal):
            let rendered = renderCorrection(predicate: predicate)
            return ordinal.map { ".target(\(rendered), ordinal: \($0))" } ?? rendered
        case .container(let predicate, let ordinal):
            let rendered = renderCorrection(container: predicate)
            return ordinal.map { ".container(\(rendered), ordinal: \($0))" } ?? ".container(\(rendered))"
        case .ref(let reference):
            return reference.rawValue
        case .within(let container, let target):
            return ".within(container: \(renderCorrection(container: container)), \(renderCorrection(target: target)))"
        }
    }

    func renderCorrection(target: AccessibilityTarget, addingOrdinal ordinal: Int) -> String {
        switch target {
        case .predicate(let predicate, _):
            return ".target(\(renderCorrection(predicate: predicate)), ordinal: \(ordinal))"
        case .container(let predicate, _):
            return ".container(\(renderCorrection(container: predicate)), ordinal: \(ordinal))"
        case .ref(let reference):
            return reference.rawValue
        case .within(let container, let target):
            return ".within(container: \(renderCorrection(container: container)), \(renderCorrection(target: target, addingOrdinal: ordinal)))"
        }
    }

    func renderCorrection(predicate: ElementPredicateTemplate) -> String {
        guard predicate.checks.count != 1 else {
            return renderCorrection(singleCheck: predicate.checks[0])
        }
        return ".element(\(predicate.checks.map { renderCorrection(check: $0) }.joined(separator: ", ")))"
    }

    private func renderCorrection(singleCheck check: ElementPredicateCheck<StringExpr>) -> String {
        switch check {
        case .traits:
            return ".element(\(renderCorrection(check: check)))"
        default:
            return renderCorrection(check: check)
        }
    }

    private func renderCorrection(check: ElementPredicateCheck<StringExpr>) -> String {
        switch check {
        case .label(let match): return ".label(\(renderCorrection(match: match)))"
        case .identifier(let match): return ".identifier(\(renderCorrection(match: match)))"
        case .value(let match): return ".value(\(renderCorrection(match: match)))"
        case .hint(let match): return ".hint(\(renderCorrection(match: match)))"
        case .traits(let traits): return ".traits(\(renderTraitArray(traits)))"
        case .actions(let actions): return ".actions(\(renderActionArray(actions)))"
        case .customContent(let match): return ".customContent(\(renderCorrection(customContent: match)))"
        case .rotors(let matches): return ".rotors(\(renderCorrection(matches: matches)))"
        case .exclude(let excluded): return ".exclude(\(renderCorrection(check: excluded)))"
        }
    }

    private func renderCorrection(container: ContainerPredicateExpr) -> String {
        if container.checks.count == 1 {
            switch container.checks[0] {
            case .type(let type):
                if type == .dataTable { return ".dataTable()" }
                return type == .series ? ".type(.series)" : ".\(type.rawValue)"
            case .identifier(let match):
                return ".identifier(\(renderCorrection(match: match)))"
            case .semantic(let predicate):
                return renderCorrection(semanticContainer: predicate)
            case .scrollable(true):
                return ".scrollable(true)"
            case .actions(let actions):
                return ".actions(\(renderContainerActions(actions)))"
            case .rowCount, .columnCount, .modalBoundary, .scrollable(false):
                break
            }
        }
        return ".matching(\(container.checks.map { renderCorrection(containerCheck: $0) }.joined(separator: ", ")))"
    }

    private func renderCorrection(containerCheck check: ContainerPredicateCheck<StringExpr>) -> String {
        switch check {
        case .type(let type):
            return ".type(.\(type.rawValue))"
        case .identifier(let match):
            return ".identifier(\(renderCorrection(match: match)))"
        case .semantic(let predicate):
            return ".semantic(\(renderCorrection(semanticContainer: predicate)))"
        case .rowCount(let count): return ".rowCount(.init(\(count.value)))"
        case .columnCount(let count): return ".columnCount(.init(\(count.value)))"
        case .modalBoundary(let required): return ".modalBoundary(\(required))"
        case .scrollable(let required): return ".scrollable(\(required))"
        case .actions(let actions): return ".actions(\(renderContainerActions(actions)))"
        }
    }

    private func renderCorrection(semanticContainer predicate: SemanticContainerPredicate<StringExpr>) -> String {
        switch predicate {
        case .label(let match): return ".label(\(renderCorrection(match: match)))"
        case .value(let match): return ".value(\(renderCorrection(match: match)))"
        }
    }

    private func renderCorrection(customContent match: CustomContentMatch<StringExpr>) -> String {
        let fields = [
            match.label.map { "label: \(renderCorrection(match: $0))" },
            match.value.map { "value: \(renderCorrection(match: $0))" },
            match.isImportant.map { "isImportant: \($0)" },
        ].compactMap { $0 }
        return ".init(\(fields.joined(separator: ", ")))"
    }

    private func renderCorrection(matches: [StringMatch<StringExpr>]) -> String {
        "[\(matches.map { renderCorrection(match: $0) }.joined(separator: ", "))]"
    }

    private func renderCorrection(match: StringMatch<StringExpr>) -> String {
        switch match {
        case .exact(let string): return renderCorrection(string: string)
        case .contains(let string): return ".contains(\(renderCorrection(string: string)))"
        case .prefix(let string): return ".prefix(\(renderCorrection(string: string)))"
        case .suffix(let string): return ".suffix(\(renderCorrection(string: string)))"
        case .isEmpty: return ".isEmpty"
        }
    }

    private func renderCorrection(string: StringExpr) -> String {
        switch string {
        case .literal(let literal): return quote(literal)
        case .ref(let reference): return reference.rawValue
        }
    }

    func render(target: AccessibilityTarget, environment: RenderEnvironment) throws -> String {
        switch target {
        case .predicate(let predicate, let ordinal):
            let renderedPredicate = try render(predicate: predicate, environment: environment)
            guard let ordinal else { return renderedPredicate }
            return ".target(\(renderedPredicate), ordinal: \(ordinal))"
        case .container(let predicate, let ordinal):
            let rendered = try render(container: predicate, environment: environment)
            return ordinal.map { ".container(\(rendered), ordinal: \($0))" } ?? ".container(\(rendered))"
        case .ref(let reference):
            guard environment.targetReferences.contains(reference) else {
                throw HeistCanonicalSwiftDSLError.unresolvedTargetReference(reference.rawValue)
            }
            return reference.rawValue
        case .within(let container, let target):
            return try ".within(container: \(render(container: container, environment: environment)), \(render(target: target, environment: environment)))"
        }
    }

    func render(target: AccessibilityTarget) -> String {
        renderCorrection(target: target)
    }

    func render(container: ContainerPredicate) -> String {
        if let shorthand = renderSingleContainerCheck(container.checks) { return shorthand }
        if let dataTable = renderDataTable(container.checks) { return dataTable }
        return ".matching(\(container.checks.map(renderContainerCheck).joined(separator: ", ")))"
    }

    func render(container: ContainerPredicateExpr, environment: RenderEnvironment) throws -> String {
        if let shorthand = try renderSingleContainerCheck(container.checks, environment: environment) { return shorthand }
        if let dataTable = renderDataTable(container.checks) { return dataTable }
        return try ".matching(\(container.checks.map { try renderContainerCheck($0, environment: environment) }.joined(separator: ", ")))"
    }

    func renderSingleContainerCheck(_ checks: NonEmptyArray<ContainerPredicateCheck<String>>) -> String? {
        renderSingleContainerCheck(
            checks,
            renderIdentifier: { renderCallArgument($0) },
            renderSemantic: { renderSemanticContainerPredicate($0) }
        )
    }

    func renderSingleContainerCheck(
        _ checks: NonEmptyArray<ContainerPredicateCheck<StringExpr>>,
        environment: RenderEnvironment
    ) throws -> String? {
        try renderSingleContainerCheck(
            checks,
            renderIdentifier: { try renderCallArgument($0, environment: environment) },
            renderSemantic: { try renderSemanticContainerPredicate($0, environment: environment) }
        )
    }

    private func renderSingleContainerCheck<Value: StringMatchPayload>(
        _ checks: NonEmptyArray<ContainerPredicateCheck<Value>>,
        renderIdentifier: (StringMatch<Value>) throws -> String,
        renderSemantic: (SemanticContainerPredicate<Value>) throws -> String
    ) rethrows -> String? {
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
            return try ".identifier(\(renderIdentifier(match)))"
        case .semantic(let predicate):
            return try renderSemantic(predicate)
        case .scrollable(true):
            return ".scrollable(true)"
        case .actions(let actions):
            return ".actions(\(renderContainerActions(actions)))"
        case .rowCount, .columnCount, .modalBoundary:
            return nil
        case .scrollable(false):
            return nil
        }
    }

    func renderDataTable(_ checks: NonEmptyArray<ContainerPredicateCheck<String>>) -> String? {
        renderDataTable(rowCount: rowCount(in: checks), columnCount: columnCount(in: checks), hasOnlyTableChecks: hasOnlyDataTableChecks(checks))
    }

    func renderDataTable(_ checks: NonEmptyArray<ContainerPredicateCheck<StringExpr>>) -> String? {
        renderDataTable(rowCount: rowCount(in: checks), columnCount: columnCount(in: checks), hasOnlyTableChecks: hasOnlyDataTableChecks(checks))
    }

    private func renderDataTable(rowCount: UInt?, columnCount: UInt?, hasOnlyTableChecks: Bool) -> String? {
        guard hasOnlyTableChecks else { return nil }
        var arguments: [String] = []
        if let rowCount { arguments.append("rowCount: .init(\(rowCount))") }
        if let columnCount { arguments.append("columnCount: .init(\(columnCount))") }
        return ".dataTable(\(arguments.joined(separator: ", ")))"
    }

    private func hasOnlyDataTableChecks<Value: StringMatchPayload>(
        _ checks: NonEmptyArray<ContainerPredicateCheck<Value>>
    ) -> Bool {
        let hasDataTableType = checks.contains { check in
            if case .type(.dataTable) = check { return true }
            return false
        }
        let containsOnlyDataTableChecks = checks.allSatisfy { check in
            switch check {
            case .type(.dataTable), .rowCount, .columnCount:
                return true
            case .type, .identifier, .semantic, .modalBoundary, .scrollable, .actions:
                return false
            }
        }
        return hasDataTableType && containsOnlyDataTableChecks
    }

    private func rowCount<Value: StringMatchPayload>(
        in checks: NonEmptyArray<ContainerPredicateCheck<Value>>
    ) -> UInt? {
        checks.compactMap {
            if case .rowCount(let count) = $0 { return count.value }
            return nil
        }.first
    }

    private func columnCount<Value: StringMatchPayload>(
        in checks: NonEmptyArray<ContainerPredicateCheck<Value>>
    ) -> UInt? {
        checks.compactMap {
            if case .columnCount(let count) = $0 { return count.value }
            return nil
        }.first
    }

    func renderContainerCheck(_ check: ContainerPredicateCheck<String>) -> String {
        renderContainerCheck(
            check,
            renderIdentifier: { renderCallArgument($0) },
            renderSemantic: { renderSemanticContainerPredicate($0) }
        )
    }

    func renderContainerCheck(
        _ check: ContainerPredicateCheck<StringExpr>,
        environment: RenderEnvironment
    ) throws -> String {
        try renderContainerCheck(
            check,
            renderIdentifier: { try renderCallArgument($0, environment: environment) },
            renderSemantic: { try renderSemanticContainerPredicate($0, environment: environment) }
        )
    }

    private func renderContainerCheck<Value: StringMatchPayload>(
        _ check: ContainerPredicateCheck<Value>,
        renderIdentifier: (StringMatch<Value>) throws -> String,
        renderSemantic: (SemanticContainerPredicate<Value>) throws -> String
    ) rethrows -> String {
        switch check {
        case .type(let type):
            return ".type(.\(type.rawValue))"
        case .identifier(let match):
            return try ".identifier(\(renderIdentifier(match)))"
        case .semantic(let predicate):
            return try ".semantic(\(renderSemantic(predicate)))"
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

    func renderSemanticContainerPredicate(_ predicate: SemanticContainerPredicate<String>) -> String {
        switch predicate {
        case .label(let match):
            return ".label(\(renderCallArgument(match)))"
        case .value(let match):
            return ".value(\(renderCallArgument(match)))"
        }
    }

    func renderSemanticContainerPredicate(
        _ predicate: SemanticContainerPredicate<StringExpr>,
        environment: RenderEnvironment
    ) throws -> String {
        switch predicate {
        case .label(let match):
            return try ".label(\(renderCallArgument(match, environment: environment)))"
        case .value(let match):
            return try ".value(\(renderCallArgument(match, environment: environment)))"
        }
    }

    private func renderContainerActions(_ actions: ContainerPredicateActions) -> String {
        let values = actions.values.sorted { $0.canonicalSortKey < $1.canonicalSortKey }
        return ".init(\(values.map(render(action:)).joined(separator: ", ")))"
    }

    func renderTargetPredicate(_ predicate: ElementPredicate) -> String {
        if let shorthand = renderSingleCheckTarget(predicate.checks) { return shorthand }
        return ".element(\(renderElementPredicateChecks(predicate)))"
    }

    func render(predicate: ElementPredicate) -> String {
        if let shorthand = renderSingleCheckTarget(predicate.checks) { return shorthand }
        return ".element(\(renderElementPredicateChecks(predicate)))"
    }

    func render(predicate: ElementPredicateTemplate, environment: RenderEnvironment) throws -> String {
        if let shorthand = try renderSingleCheckTarget(predicate.checks, environment: environment) { return shorthand }
        return ".element(\(try renderElementPredicateTemplateChecks(predicate, environment: environment)))"
    }

    func renderSingleCheckTarget(_ checks: [ElementPredicateCheck<String>]) -> String? {
        guard checks.count == 1 else { return nil }
        switch checks[0] {
        case .label(let match):
            return ".label(\(renderCallArgument(match)))"
        case .identifier(let match):
            return ".identifier(\(renderCallArgument(match)))"
        case .value(let match):
            return ".value(\(renderCallArgument(match)))"
        case .hint(let match):
            return ".hint(\(renderCallArgument(match)))"
        case .actions(let actions):
            return ".actions(\(renderActionArray(actions)))"
        case .customContent(let match):
            return ".customContent(\(render(customContent: match)))"
        case .rotors(let matches):
            return ".rotors(\(renderStringMatchArray(matches)))"
        case .exclude(let check):
            return ".exclude(\(renderPredicateCheck(check)))"
        case .traits:
            return nil
        }
    }

    func renderSingleCheckTarget(
        _ checks: [ElementPredicateCheck<StringExpr>],
        environment: RenderEnvironment
    ) throws -> String? {
        guard checks.count == 1 else { return nil }
        switch checks[0] {
        case .label(let match):
            return ".label(\(try renderCallArgument(match, environment: environment)))"
        case .identifier(let match):
            return ".identifier(\(try renderCallArgument(match, environment: environment)))"
        case .value(let match):
            return ".value(\(try renderCallArgument(match, environment: environment)))"
        case .hint(let match):
            return ".hint(\(try renderCallArgument(match, environment: environment)))"
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

    func renderElementPredicateChecks(_ predicate: ElementPredicate) -> String {
        predicate.checks.map(renderPredicateCheck).joined(separator: ", ")
    }

    func renderElementPredicateTemplateChecks(
        _ predicate: ElementPredicateTemplate,
        environment: RenderEnvironment
    ) throws -> String {
        try predicate.checks.map {
            try renderPredicateCheck($0, environment: environment)
        }.joined(separator: ", ")
    }

    func renderPredicateCheck(_ check: ElementPredicateCheck<String>) -> String {
        switch check {
        case .label(let match):
            return ".label(\(renderCallArgument(match)))"
        case .identifier(let match):
            return ".identifier(\(renderCallArgument(match)))"
        case .value(let match):
            return ".value(\(renderCallArgument(match)))"
        case .hint(let match):
            return ".hint(\(renderCallArgument(match)))"
        case .traits(let traits):
            return ".traits(\(renderTraitArray(traits)))"
        case .actions(let actions):
            return ".actions(\(renderActionArray(actions)))"
        case .customContent(let match):
            return ".customContent(\(render(customContent: match)))"
        case .rotors(let matches):
            return ".rotors(\(renderStringMatchArray(matches)))"
        case .exclude(let check):
            return ".exclude(\(renderPredicateCheck(check)))"
        }
    }

    func renderPredicateCheck(
        _ check: ElementPredicateCheck<StringExpr>,
        environment: RenderEnvironment
    ) throws -> String {
        switch check {
        case .label(let match):
            return ".label(\(try renderCallArgument(match, environment: environment)))"
        case .identifier(let match):
            return ".identifier(\(try renderCallArgument(match, environment: environment)))"
        case .value(let match):
            return ".value(\(try renderCallArgument(match, environment: environment)))"
        case .hint(let match):
            return ".hint(\(try renderCallArgument(match, environment: environment)))"
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

    func renderCallArgument(_ match: StringMatch<String>) -> String {
        switch match {
        case .exact(let value):
            return quote(value)
        case .contains(let value):
            return ".contains(\(quote(value)))"
        case .prefix(let value):
            return ".prefix(\(quote(value)))"
        case .suffix(let value):
            return ".suffix(\(quote(value)))"
        case .isEmpty:
            return ".isEmpty"
        }
    }

    func renderFieldArgument(_ match: StringMatch<String>) -> String {
        switch match {
        case .exact(let value):
            return quote(value)
        case .contains(let value):
            return ".contains(\(quote(value)))"
        case .prefix(let value):
            return ".prefix(\(quote(value)))"
        case .suffix(let value):
            return ".suffix(\(quote(value)))"
        case .isEmpty:
            return ".isEmpty"
        }
    }

    func renderCallArgument(
        _ match: StringMatch<StringExpr>,
        environment: RenderEnvironment
    ) throws -> String {
        switch match {
        case .exact(let value):
            return try render(string: value, environment: environment)
        case .contains(let value):
            return ".contains(\(try render(string: value, environment: environment)))"
        case .prefix(let value):
            return ".prefix(\(try render(string: value, environment: environment)))"
        case .suffix(let value):
            return ".suffix(\(try render(string: value, environment: environment)))"
        case .isEmpty:
            return ".isEmpty"
        }
    }

    func renderFieldArgument(
        _ match: StringMatch<StringExpr>,
        environment: RenderEnvironment
    ) throws -> String {
        switch match {
        case .exact(let value):
            return try render(string: value, environment: environment)
        case .contains(let value):
            return ".contains(\(try render(string: value, environment: environment)))"
        case .prefix(let value):
            return ".prefix(\(try render(string: value, environment: environment)))"
        case .suffix(let value):
            return ".suffix(\(try render(string: value, environment: environment)))"
        case .isEmpty:
            return ".isEmpty"
        }
    }

    func render(string: StringExpr, environment: RenderEnvironment) throws -> String {
        switch string {
        case .literal(let literal):
            return quote(literal)
        case .ref(let reference):
            guard environment.stringReferences.contains(reference) else {
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
        "GestureDuration(seconds: \(decimal(duration.seconds)))"
    }
}

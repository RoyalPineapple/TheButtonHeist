import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func render(predicate: StatePredicateExpr, environment: RenderEnvironment) throws -> String {
        try render(state: predicate, environment: environment)
    }

    func render(predicate: AccessibilityPredicateExpr, environment: RenderEnvironment) throws -> String {
        switch predicate {
        case .state(let state):
            return try render(state: state, environment: environment)
        case .changePredicate(let change):
            return try render(changePredicate: change, environment: environment)
        case .noChangePredicate:
            return ".noChange"
        case .announcement(let announcement):
            return try render(announcement: announcement, environment: environment)
        case .predicate(let predicate):
            return try render(predicate: predicate, environment: environment)
        }
    }

    func render(predicate: AccessibilityPredicate, environment: RenderEnvironment) throws -> String {
        switch predicate {
        case .state(let state):
            return try render(state: state, environment: environment)
        case .changePredicate(let change):
            return try render(changePredicate: change, environment: environment)
        case .noChangePredicate:
            return ".noChange"
        case .announcement(let announcement):
            return render(announcement: announcement)
        }
    }

    func render(announcement: AnnouncementPredicateExpr, environment: RenderEnvironment) throws -> String {
        guard let match = announcement.match else { return ".announcement" }
        return try ".announcement(\(renderCallArgument(match, environment: environment)))"
    }

    func render(announcement: AnnouncementPredicate) -> String {
        guard let match = announcement.match else { return ".announcement" }
        return ".announcement(\(renderCallArgument(match)))"
    }

    func render(changePredicate change: ChangePredicateExpr, environment: RenderEnvironment) throws -> String {
        if case .screenScope(let assertions) = change {
            return try renderScreenChanged(assertions: assertions, environment: environment)
        }
        if case .elementsScope(let assertions) = change, assertions.count == 1 {
            return try render(elementDelta: assertions[0], environment: environment)
        }
        return try ".change(\(render(change: change, environment: environment)))"
    }

    func render(changePredicate change: AccessibilityPredicate.Change, environment: RenderEnvironment) throws -> String {
        if case .screenScope(let assertions) = change {
            return try renderScreenChanged(assertions: assertions, environment: environment)
        }
        if case .elementsScope(let assertions) = change, assertions.count == 1 {
            return try render(elementDelta: assertions[0])
        }
        return try ".change(\(render(change: change, environment: environment)))"
    }

    func render(state: StatePredicateExpr, environment: RenderEnvironment) throws -> String {
        switch state {
        case .exists(let predicate):
            return try renderExistsState(predicate, environment: environment)
        case .missing(let predicate):
            return ".missing(\(try render(predicate: predicate, environment: environment)))"
        case .existsTarget(let target):
            return ".exists(\(try render(target: target, environment: environment)))"
        case .missingTarget(let target):
            return ".missing(\(try render(target: target, environment: environment)))"
        case .screen(let identity):
            return try render(screenIdentity: identity, environment: environment)
        case .all(let states):
            return ".all(\(try states.map { try render(state: $0, environment: environment) }.joined(separator: ", ")))"
        }
    }

    func render(state: AccessibilityPredicate.State, environment: RenderEnvironment) throws -> String {
        switch state {
        case .exists(let predicate):
            return renderExistsState(predicate)
        case .missing(let predicate):
            return ".missing(\(render(predicate: predicate)))"
        case .existsTarget(let target):
            return ".exists(\(render(target: target)))"
        case .missingTarget(let target):
            return ".missing(\(render(target: target)))"
        case .screen(let identity):
            return render(screenIdentity: identity)
        case .all(let states):
            return ".all(\(try states.map { try render(state: $0, environment: environment) }.joined(separator: ", ")))"
        }
    }

    func render(screenIdentity identity: ScreenIdentityPredicateExpr, environment: RenderEnvironment) throws -> String {
        switch identity {
        case .id(let id):
            return try ".onScreen(id: \(render(string: id, environment: environment)))"
        case .header(let header):
            return try ".onScreen(header: \(renderCallArgument(header, environment: environment)))"
        }
    }

    func render(screenIdentity identity: ScreenIdentityPredicate) -> String {
        switch identity {
        case .id(let id):
            return ".onScreen(id: \(ScoreDescription.quoted(id.rawValue)))"
        case .header(let header):
            return ".onScreen(header: \(renderCallArgument(header)))"
        }
    }

    func renderExistsState(_ predicate: ElementPredicateTemplate, environment: RenderEnvironment) throws -> String {
        if let shorthand = try renderSingleCheckTarget(predicate.checks, environment: environment) {
            return shorthand
        }
        return ".exists(.element(\(try renderElementPredicateTemplateChecks(predicate, environment: environment))))"
    }

    func renderExistsState(_ predicate: ElementPredicate) -> String {
        if let shorthand = renderSingleCheckTarget(predicate.checks) {
            return shorthand
        }
        return ".exists(.element(\(renderElementPredicateChecks(predicate))))"
    }

    func render(change: AccessibilityPredicate.Change, environment: RenderEnvironment) throws -> String {
        switch change {
        case .any:
            return ""
        case .screenScope(let assertions):
            return try renderScreenChanged(assertions: assertions, environment: environment)
        case .elementsScope(let assertions):
            switch assertions.count {
            case 0:
                return ".elements()"
            case 1:
                return try render(elementDelta: assertions[0])
            default:
                return try ".elements(\(assertions.map { try render(elementDelta: $0) }.joined(separator: ", ")))"
            }
        case .allScopes(let changes):
            return try changes.map { try render(changeScope: $0, environment: environment) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }

    func render(change: ChangePredicateExpr, environment: RenderEnvironment) throws -> String {
        switch change {
        case .any:
            return ""
        case .screenScope(let assertions):
            return try renderScreenChanged(assertions: assertions, environment: environment)
        case .elementsScope(let assertions):
            switch assertions.count {
            case 0:
                return ".elements()"
            case 1:
                return try render(elementDelta: assertions[0], environment: environment)
            default:
                return try ".elements(\(assertions.map { try render(elementDelta: $0, environment: environment) }.joined(separator: ", ")))"
            }
        case .allScopes(let changes):
            return try changes.map { try render(changeScope: $0, environment: environment) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }

    func render(changeScope scope: AccessibilityPredicate.ChangeScope, environment: RenderEnvironment) throws -> String {
        switch scope {
        case .screen(let assertions):
            return try renderScreenChanged(assertions: assertions, environment: environment)
        case .elements(let assertions):
            switch assertions.count {
            case 0:
                return ".elements()"
            case 1:
                return try render(elementDelta: assertions[0])
            default:
                return try ".elements(\(assertions.map { try render(elementDelta: $0) }.joined(separator: ", ")))"
            }
        case .all(let scopes):
            return try scopes.map { try render(changeScope: $0, environment: environment) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }

    func render(changeScope scope: ChangeScopePredicateExpr, environment: RenderEnvironment) throws -> String {
        switch scope {
        case .screen(let assertions):
            return try renderScreenChanged(assertions: assertions, environment: environment)
        case .elements(let assertions):
            switch assertions.count {
            case 0:
                return ".elements()"
            case 1:
                return try render(elementDelta: assertions[0], environment: environment)
            default:
                return try ".elements(\(assertions.map { try render(elementDelta: $0, environment: environment) }.joined(separator: ", ")))"
            }
        case .all(let scopes):
            return try scopes.map { try render(changeScope: $0, environment: environment) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }

    func renderScreenChanged(assertions: [StatePredicateExpr], environment: RenderEnvironment) throws -> String {
        switch assertions.count {
        case 0:
            return ".screenChanged"
        case 1:
            return try ".screenChanged(\(renderScreenAssertion(assertions[0], environment: environment)))"
        default:
            let assertion = StatePredicateExpr.all(NonEmptyArray(
                assertions[0],
                rest: Array(assertions.dropFirst())
            ))
            return try ".screenChanged(\(renderScreenAssertion(assertion, environment: environment)))"
        }
    }

    func renderScreenChanged(assertions: [AccessibilityPredicate.State], environment: RenderEnvironment) throws -> String {
        switch assertions.count {
        case 0:
            return ".screenChanged"
        case 1:
            return ".screenChanged(\(renderScreenAssertion(assertions[0])))"
        default:
            let assertion = AccessibilityPredicate.State.all(NonEmptyArray(
                assertions[0],
                rest: Array(assertions.dropFirst())
            ))
            return ".screenChanged(\(renderScreenAssertion(assertion)))"
        }
    }

    func renderScreenAssertion(_ state: StatePredicateExpr, environment: RenderEnvironment) throws -> String {
        switch state {
        case .exists(let predicate):
            return try ".exists(\(render(predicate: predicate, environment: environment)))"
        case .missing(let predicate):
            return try ".missing(\(render(predicate: predicate, environment: environment)))"
        case .existsTarget(let target):
            return try ".exists(\(render(target: target, environment: environment)))"
        case .missingTarget(let target):
            return try ".missing(\(render(target: target, environment: environment)))"
        case .screen(let identity):
            return try render(screenIdentity: identity, environment: environment)
        case .all(let states):
            return try ".all(\(states.map { try renderScreenAssertion($0, environment: environment) }.joined(separator: ", ")))"
        }
    }

    func renderScreenAssertion(_ state: AccessibilityPredicate.State) -> String {
        switch state {
        case .exists(let predicate):
            return ".exists(\(render(predicate: predicate)))"
        case .missing(let predicate):
            return ".missing(\(render(predicate: predicate)))"
        case .existsTarget(let target):
            return ".exists(\(render(target: target)))"
        case .missingTarget(let target):
            return ".missing(\(render(target: target)))"
        case .screen(let identity):
            return render(screenIdentity: identity)
        case .all(let states):
            return ".all(\(states.map(renderScreenAssertion).joined(separator: ", ")))"
        }
    }

    func render(elementDelta: ElementDeltaPredicate) throws -> String {
        switch elementDelta {
        case .appearedElement(let element):
            return ".appeared(\(render(predicate: element)))"
        case .disappearedElement(let element):
            return ".disappeared(\(render(predicate: element)))"
        case .updatedElement(let update):
            return try ".updated(\(render(update: update)))"
        }
    }

    func render(elementDelta: ElementDeltaPredicateExpr, environment: RenderEnvironment) throws -> String {
        switch elementDelta {
        case .appearedElement(let element):
            return try ".appeared(\(render(predicate: element, environment: environment)))"
        case .disappearedElement(let element):
            return try ".disappeared(\(render(predicate: element, environment: environment)))"
        case .updatedElement(let update):
            return try ".updated(\(render(update: update, environment: environment)))"
        }
    }

    func render(update: ElementUpdatePredicate) throws -> String {
        switch (update.element, update.change) {
        case (.none, .some(let change)):
            return render(propertyChange: change)
        case (.some(let element), .some(let change)):
            return "\(render(predicate: element)), \(render(propertyChange: change))"
        case (.some, .none):
            throw HeistCanonicalSwiftDSLError.unsupportedPredicate("updated element matcher without an update matcher")
        case (.none, .none):
            throw HeistCanonicalSwiftDSLError.unsupportedPredicate("empty updated predicate")
        }
    }

    func render(update: ElementUpdatePredicateExpr, environment: RenderEnvironment) throws -> String {
        switch (update.element, update.change) {
        case (.none, .some(let change)):
            return try render(propertyChange: change, environment: environment)
        case (.some(let element), .some(let change)):
            return try "\(render(predicate: element, environment: environment)), \(render(propertyChange: change, environment: environment))"
        case (.some, .none):
            throw HeistCanonicalSwiftDSLError.unsupportedPredicate("updated element matcher without an update matcher")
        case (.none, .none):
            throw HeistCanonicalSwiftDSLError.unsupportedPredicate("empty updated predicate")
        }
    }

    func render(propertyChange change: AnyPropertyChange) -> String {
        switch change {
        case .value(let change):
            return renderStringPropertyChange("value", before: change.before, after: change.after)
        case .traits(let change):
            return renderTraitsPropertyChange(before: change.before, after: change.after)
        case .hint(let change):
            return renderStringPropertyChange("hint", before: change.before, after: change.after)
        case .actions(let change):
            return renderPropertyChange("actions", before: change.before, after: change.after, render: render(actionSet:))
        case .frame(let change):
            return renderPropertyChange("frame", before: change.before, after: change.after, render: render(frame:))
        case .activationPoint(let change):
            return renderPropertyChange("activationPoint", before: change.before, after: change.after, render: render(point:))
        case .customContent(let change):
            return renderPropertyChange("customContent", before: change.before, after: change.after, render: render(customContent:))
        case .rotors(let change):
            return renderPropertyChange("rotors", before: change.before, after: change.after, render: render(rotorSet:))
        }
    }

    func render(propertyChange change: AnyPropertyChangeExpr, environment: RenderEnvironment) throws -> String {
        switch change {
        case .value(let change):
            return try renderStringPropertyChange("value", before: change.before, after: change.after, environment: environment)
        case .traits(let change):
            return renderTraitsPropertyChange(before: change.before, after: change.after)
        case .hint(let change):
            return try renderStringPropertyChange("hint", before: change.before, after: change.after, environment: environment)
        case .actions(let change):
            return renderPropertyChange("actions", before: change.before, after: change.after, render: render(actionSet:))
        case .frame(let change):
            return renderPropertyChange("frame", before: change.before, after: change.after, render: render(frame:))
        case .activationPoint(let change):
            return renderPropertyChange("activationPoint", before: change.before, after: change.after, render: render(point:))
        case .customContent(let change):
            return try renderPropertyChange("customContent", before: change.before, after: change.after) {
                try render(customContent: $0, environment: environment)
            }
        case .rotors(let change):
            return try renderPropertyChange("rotors", before: change.before, after: change.after) {
                try render(rotorSet: $0, environment: environment)
            }
        }
    }

    func renderPropertyChange<Checker>(
        _ name: String,
        before: Checker?,
        after: Checker?,
        render: (Checker) throws -> String
    ) rethrows -> String {
        let fields = try [
            before.map { "before: \(try render($0))" },
            after.map { "after: \(try render($0))" },
        ].compactMap { $0 }
        return ".\(name)(\(fields.joined(separator: ", ")))"
    }

    func renderStringPropertyChange(
        _ name: String,
        before: StringMatch<String>?,
        after: StringMatch<String>?
    ) -> String {
        if name == "value", before == nil, let after {
            return ".value(\(renderCallArgument(after)))"
        }
        let fields = [
            before.map { "before: \(renderFieldArgument($0))" },
            after.map { "after: \(renderFieldArgument($0))" },
        ].compactMap { $0 }
        return ".\(name)(\(fields.joined(separator: ", ")))"
    }

    func renderStringPropertyChange(
        _ name: String,
        before: StringMatch<StringExpr>?,
        after: StringMatch<StringExpr>?,
        environment: RenderEnvironment
    ) throws -> String {
        if name == "value", before == nil, let after {
            return try ".value(\(renderCallArgument(after, environment: environment)))"
        }
        let fields = try [
            before.map { "before: \(try renderFieldArgument($0, environment: environment))" },
            after.map { "after: \(try renderFieldArgument($0, environment: environment))" },
        ].compactMap { $0 }
        return ".\(name)(\(fields.joined(separator: ", ")))"
    }

    func renderTraitsPropertyChange(before: TraitSetMatch?, after: TraitSetMatch?) -> String {
        let fields = [
            before.map { "before: \(render(traitSet: $0))" },
            after.map { "after: \(render(traitSet: $0))" },
        ].compactMap { $0 }
        return ".traits(\(fields.joined(separator: ", ")))"
    }

    func render(traitSet match: TraitSetMatch) -> String {
        switch (match.include.isEmpty, match.exclude.isEmpty) {
        case (false, true):
            return ".include(\(renderTraitArray(match.include)))"
        case (true, false):
            return ".exclude(\(renderTraitArray(match.exclude)))"
        default:
            return ".match(include: \(renderTraitArray(match.include)), exclude: \(renderTraitArray(match.exclude)))"
        }
    }

    func render(actionSet match: ActionSetMatch) -> String {
        switch (match.include.isEmpty, match.exclude.isEmpty) {
        case (false, true):
            return ".include(\(renderActionArray(match.include)))"
        case (true, false):
            return ".exclude(\(renderActionArray(match.exclude)))"
        default:
            return ".match(include: \(renderActionArray(match.include)), exclude: \(renderActionArray(match.exclude)))"
        }
    }

    func render(frame match: ElementFrameMatch) -> String {
        if let x = match.x, let y = match.y, let width = match.width, let height = match.height {
            return ".exact(x: \(x), y: \(y), width: \(width), height: \(height))"
        }
        let fields = renderIntegerFields([
            ("x", match.x),
            ("y", match.y),
            ("width", match.width),
            ("height", match.height),
        ])
        return ".match(\(fields))"
    }

    func render(point match: ElementPointMatch) -> String {
        if let x = match.x, let y = match.y {
            return ".exact(x: \(x), y: \(y))"
        }
        let fields = renderIntegerFields([
            ("x", match.x),
            ("y", match.y),
        ])
        return ".match(\(fields))"
    }

    func render(customContent match: CustomContentMatch<String>) -> String {
        let fields = renderCustomContentFields(
            label: match.label.map(renderFieldArgument),
            value: match.value.map(renderFieldArgument),
            isImportant: match.isImportant
        )
        return ".match(\(fields))"
    }

    func render(customContent match: CustomContentMatch<StringExpr>, environment: RenderEnvironment) throws -> String {
        let fields = try renderCustomContentFields(
            label: match.label.map { try renderFieldArgument($0, environment: environment) },
            value: match.value.map { try renderFieldArgument($0, environment: environment) },
            isImportant: match.isImportant
        )
        return ".match(\(fields))"
    }

    func render(rotorSet match: RotorSetMatch<String>) -> String {
        switch (match.include.isEmpty, match.exclude.isEmpty) {
        case (false, true):
            return ".include(\(renderStringMatchArray(match.include)))"
        case (true, false):
            return ".exclude(\(renderStringMatchArray(match.exclude)))"
        default:
            return ".match(include: \(renderStringMatchArray(match.include)), exclude: \(renderStringMatchArray(match.exclude)))"
        }
    }

    func render(rotorSet match: RotorSetMatch<StringExpr>, environment: RenderEnvironment) throws -> String {
        switch (match.include.isEmpty, match.exclude.isEmpty) {
        case (false, true):
            return try ".include(\(renderStringMatchArray(match.include, environment: environment)))"
        case (true, false):
            return try ".exclude(\(renderStringMatchArray(match.exclude, environment: environment)))"
        default:
            let include = try renderStringMatchArray(match.include, environment: environment)
            let exclude = try renderStringMatchArray(match.exclude, environment: environment)
            return ".match(include: \(include), exclude: \(exclude))"
        }
    }

    private func renderIntegerFields(_ fields: [(String, Int?)]) -> String {
        fields.compactMap { name, value in
            value.map { "\(name): \($0)" }
        }.joined(separator: ", ")
    }

    private func renderCustomContentFields(
        label: String?,
        value: String?,
        isImportant: Bool?
    ) -> String {
        [
            label.map { "label: \($0)" },
            value.map { "value: \($0)" },
            isImportant.map { "isImportant: \($0)" },
        ].compactMap { $0 }.joined(separator: ", ")
    }

    func renderActionArray(_ actions: Set<ElementAction>) -> String {
        "[\(actions.sorted { $0.canonicalSortKey < $1.canonicalSortKey }.map(render(action:)).joined(separator: ", "))]"
    }

    func render(action: ElementAction) -> String {
        switch action {
        case .activate:
            return ".activate"
        case .increment:
            return ".increment"
        case .decrement:
            return ".decrement"
        case .custom(let name):
            return ".custom(\(quote(name)))"
        }
    }

    func renderStringMatchArray(_ matches: [StringMatch<String>]) -> String {
        "[\(matches.map(renderFieldArgument).joined(separator: ", "))]"
    }

    func renderStringMatchArray(
        _ matches: [StringMatch<StringExpr>],
        environment: RenderEnvironment
    ) throws -> String {
        let rendered = try matches.map { try renderFieldArgument($0, environment: environment) }
        return "[\(rendered.joined(separator: ", "))]"
    }
}

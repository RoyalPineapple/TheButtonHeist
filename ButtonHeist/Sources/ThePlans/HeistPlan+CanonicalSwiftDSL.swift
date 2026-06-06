import Foundation

public enum HeistCanonicalSwiftDSLError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedAction(String)
    case unresolvedTargetReference(String)
    case unresolvedStringReference(String)
    case invalidParameter(String)

    public var description: String {
        switch self {
        case .unsupportedAction(let action):
            return "unsupported canonical Swift DSL action: \(action)"
        case .unresolvedTargetReference(let reference):
            return "unresolved canonical Swift target reference: \(reference)"
        case .unresolvedStringReference(let reference):
            return "unresolved canonical Swift string reference: \(reference)"
        case .invalidParameter(let parameter):
            return "invalid canonical Swift DSL parameter: \(parameter)"
        }
    }
}

public extension HeistPlan {
    func canonicalSwiftDSL() throws -> String {
        try HeistCanonicalSwiftDSLRenderer().render(self)
    }
}

private struct HeistCanonicalSwiftDSLRenderer {
    func render(_ plan: HeistPlan) throws -> String {
        let definitions = try renderDefinitions(plan.definitions, path: [], indent: 0)
        let body = try render(steps: plan.body, indent: 1, environment: .empty)
        let heistHeader = plan.name.map { "try HeistPlan(\(quote($0))) {" } ?? "try HeistPlan {"
        let heist = """
        \(heistHeader)
        \(body)
        }
        """
        guard !definitions.isEmpty else { return heist }
        return """
        \(definitions)

        \(heist)
        """
    }

    private func render(
        steps: [HeistStep],
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        try steps.map { try render(step: $0, indent: indent, environment: environment) }
            .joined(separator: "\n\n")
    }

    private func render(
        step: HeistStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        switch step {
        case .action(let action):
            return try render(action: action, indent: indent, environment: environment)
        case .wait(let wait):
            return line("WaitFor(\(try render(predicate: wait.predicate, environment: environment))\(renderTimeout(wait.timeout)))", indent)
        case .conditional(let conditional):
            return try renderConditional(conditional, indent: indent, environment: environment)
        case .waitForCases(let waitForCases):
            return try renderWaitForCases(waitForCases, indent: indent, environment: environment)
        case .forEachElement(let forEach):
            return try renderForEachElement(forEach, indent: indent, environment: environment)
        case .forEachString(let forEach):
            return try renderForEachString(forEach, indent: indent, environment: environment)
        case .warn(let warn):
            return line("Warn(\(quote(warn.message)))", indent)
        case .fail(let fail):
            return line("Fail(\(quote(fail.message)))", indent)
        case .heist(let plan):
            let body = try render(steps: plan.body, indent: indent + 1, environment: environment)
            let header = plan.name.map { "try HeistPlan(\(quote($0))) {" } ?? "try HeistPlan {"
            return """
            \(line(header, indent))
            \(body)
            \(line("}", indent))
            """
        case .invoke(let invoke):
            return try line(render(invoke: invoke, environment: environment), indent)
        }
    }

    private func renderDefinitions(
        _ definitions: [HeistPlan],
        path: [String],
        indent: Int
    ) throws -> String {
        try definitions.map { definition in
            try renderDefinition(definition, path: path, indent: indent)
        }.joined(separator: "\n\n")
    }

    private func renderDefinition(
        _ definition: HeistPlan,
        path: [String],
        indent: Int
    ) throws -> String {
        guard let name = definition.name else {
            throw HeistCanonicalSwiftDSLError.invalidParameter("<anonymous>")
        }
        try validateParameter(name)
        let fullPath = path + [name]
        if definition.body.isEmpty, !definition.definitions.isEmpty, definition.parameter == .none {
            let nested = try renderDefinitions(definition.definitions, path: fullPath, indent: indent + 1)
            return """
            \(line("enum \(name) {", indent))
            \(nested)
            \(line("}", indent))
            """
        }
        let declaration = indent == 0 ? "let" : "static let"
        let definitionType = try renderDefinitionType(definition.parameter)
        let path = quote(fullPath.joined(separator: "."))
        let nestedDefinitions = try renderDefinitions(definition.definitions, path: [], indent: indent + 1)

        switch definition.parameter {
        case .none:
            let body = try render(steps: definition.body, indent: indent + 1, environment: .empty)
            let content = [nestedDefinitions, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
            return """
            \(line("\(declaration) \(name) = try! \(definitionType)(\(path)) {", indent))
            \(content)
            \(line("}", indent))
            """
        case .string, .elementTarget:
            let parameterName = try renderDefinitionParameter(definition.parameter)
            let childEnvironment = try RenderEnvironment.empty.binding(parameter: definition.parameter)
            let body = try render(steps: definition.body, indent: indent + 1, environment: childEnvironment)
            let content = [nestedDefinitions, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
            let parameter = quote(parameterName)
            return """
            \(line("\(declaration) \(name) = try! \(definitionType)(\(path), parameter: \(parameter)) { \(parameterName) in", indent))
            \(content)
            \(line("}", indent))
            """
        }
    }

    private func renderDefinitionType(_ parameter: HeistParameter) throws -> String {
        switch parameter {
        case .string:
            return "HeistDef<String>"
        case .elementTarget:
            return "HeistDef<ElementTarget>"
        case .none:
            return "HeistDef<Void>"
        }
    }

    private func renderDefinitionParameter(_ parameter: HeistParameter) throws -> String {
        guard let name = parameter.name else {
            throw HeistCanonicalSwiftDSLError.invalidParameter("<none>")
        }
        try validateParameter(name)
        return name
    }

    private func render(invoke: HeistInvocationStep, environment: RenderEnvironment) throws -> String {
        let callee = invoke.path.joined(separator: ".")
        let argument = try render(argument: invoke.argument, environment: environment)
        return argument.isEmpty ? "RunHeist(\(quote(callee)))" : "RunHeist(\(quote(callee)), \(argument))"
    }

    private func render(argument: HeistArgument, environment: RenderEnvironment) throws -> String {
        switch argument {
        case .none:
            return ""
        case .string(let value):
            return try render(string: value, environment: environment)
        case .elementTarget(let target):
            return try render(target: target, environment: environment)
        }
    }

    private func render(
        action: ActionStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        var text = try line(render(command: action.command, environment: environment), indent)
        if let expectation = action.expectation {
            let predicate = try render(predicate: expectation.predicate, environment: environment)
            text += "\n" + line(".expect(\(predicate)\(renderTimeout(expectation.timeout)))", indent + 1)
        }
        if let waiver = action.expectationWaiver {
            text += "\n" + line(".withoutExpectation(\(quote(waiver)))", indent + 1)
        }
        return text
    }

    private func render(
        command: HeistActionCommand,
        environment: RenderEnvironment
    ) throws -> String {
        if let failure = command.durableHeistActionFailure {
            throw HeistCanonicalSwiftDSLError.unsupportedAction(failure)
        }
        switch command {
        case .activate(let target):
            return "Activate(\(try render(target: target, environment: environment)))"
        case .increment(let target):
            return "Increment(\(try render(target: target, environment: environment)))"
        case .decrement(let target):
            return "Decrement(\(try render(target: target, environment: environment)))"
        case .customAction(let name, let target):
            return "CustomAction(\(quote(name)), on: \(try render(target: target, environment: environment)))"
        case .rotor(let selection, let target, let direction):
            guard case .named(let name) = selection else {
                throw HeistCanonicalSwiftDSLError.unsupportedAction(command.durableHeistActionFailure ?? "rotor selection \(selection)")
            }
            return "Rotor(\(quote(name)), on: \(try render(target: target, environment: environment)), direction: .\(direction.rawValue))"
        case .typeText(let text, let target):
            if let target {
                return "TypeText(\(try render(string: text, environment: environment)), into: \(try render(target: target, environment: environment)))"
            }
            return "TypeText(\(try render(string: text, environment: environment)))"
        case .mechanicalTap(let target):
            return try render(mechanicalTap: target)
        case .mechanicalLongPress(let target):
            return try render(mechanicalLongPress: target)
        case .mechanicalSwipe(let target):
            return try render(mechanicalSwipe: target)
        case .mechanicalDrag(let target):
            return try render(mechanicalDrag: target)
        case .viewportScroll, .viewportScrollToVisible, .viewportScrollToEdge:
            throw HeistCanonicalSwiftDSLError.unsupportedAction(
                command.durableHeistActionFailure ?? "viewport debug command is not a durable heist action"
            )
        case .editAction(let target):
            return "Edit(.\(target.action.rawValue))"
        case .setPasteboard(let target):
            return "SetPasteboard(\(quote(target.text)))"
        case .dismissKeyboard:
            return "DismissKeyboard()"
        }
    }

    private func render(mechanicalTap target: TapTarget) throws -> String {
        switch target.selection {
        case .element(let target):
            return "Mechanical.Tap(\(render(target: target)))"
        case .coordinate(let point):
            return "Mechanical.Tap(x: \(decimal(point.x)), y: \(decimal(point.y)))"
        }
    }

    private func render(mechanicalLongPress target: LongPressTarget) throws -> String {
        switch target.selection {
        case .element(let elementTarget):
            return "Mechanical.LongPress(\(render(target: elementTarget)))"
        case .coordinate(let point):
            if target.duration == .longPressDefault {
                return "Mechanical.LongPress(x: \(decimal(point.x)), y: \(decimal(point.y)))"
            }
            return "Mechanical.LongPress(x: \(decimal(point.x)), y: \(decimal(point.y)), duration: \(render(duration: target.duration)))"
        }
    }

    private func render(mechanicalSwipe target: SwipeTarget) throws -> String {
        switch target.selection {
        case .unitElement(let target, let start, let end):
            return "Mechanical.Swipe(\(render(target: target)), from: \(render(unitPoint: start)), to: \(render(unitPoint: end)))"
        case .elementDirection(let target, let direction):
            return "Mechanical.Swipe(\(render(target: target)), .\(direction.rawValue))"
        case .point(.coordinate(let start), .coordinate(let end)):
            return "Mechanical.Swipe(from: \(render(point: start)), to: \(render(point: end)))"
        case .point(.coordinate(let start), .direction(let direction)):
            return "Mechanical.Swipe(from: \(render(point: start)), .\(direction.rawValue))"
        case .point(.element, _):
            throw HeistCanonicalSwiftDSLError.unsupportedAction("swipe selection is not a durable heist action")
        }
    }

    private func render(mechanicalDrag target: DragTarget) throws -> String {
        switch target.selection {
        case .elementToPoint(let target, let end):
            return "Mechanical.Drag(\(render(target: target)), to: \(render(point: end)))"
        case .pointToPoint(let start, let end):
            return "Mechanical.Drag(from: \(render(point: start)), to: \(render(point: end)))"
        }
    }

    private func renderConditional(
        _ conditional: ConditionalStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        let cases = try renderCases(
            conditional.cases,
            elseBody: conditional.elseBody,
            indent: indent + 1,
            environment: environment
        )
        return """
        \(line("If {", indent))
        \(cases)
        \(line("}", indent))
        """
    }

    private func renderWaitForCases(
        _ waitForCases: WaitForCasesStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        let cases = try renderCases(
            waitForCases.cases,
            elseBody: waitForCases.elseBody,
            indent: indent + 1,
            environment: environment
        )
        return """
        \(line("WaitFor(timeout: .seconds(\(decimal(waitForCases.timeout)))) {", indent))
        \(cases)
        \(line("}", indent))
        """
    }

    private func renderCases(
        _ cases: [PredicateCase],
        elseBody: [HeistStep]?,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        var blocks: [String] = []
        for predicateCase in cases {
            blocks.append(try renderCase(predicateCase, indent: indent, environment: environment))
        }
        if let elseBody {
            let body = try render(steps: elseBody, indent: indent + 1, environment: environment)
            blocks.append("""
            \(line("Else {", indent))
            \(body)
            \(line("}", indent))
            """)
        }
        return blocks.joined(separator: "\n\n")
    }

    private func renderCase(
        _ predicateCase: PredicateCase,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        let body = try render(steps: predicateCase.body, indent: indent + 1, environment: environment)
        return """
        \(line("Case(\(try render(predicate: predicateCase.predicate, environment: environment))) {", indent))
        \(body)
        \(line("}", indent))
        """
    }

    private func renderForEachElement(
        _ forEach: ForEachElementStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        try validateParameter(forEach.parameter)
        let childEnvironment = environment.bindingTargetReference(forEach.parameter)
        let body = try render(steps: forEach.body, indent: indent + 1, environment: childEnvironment)
        return """
        \(line("try ForEach(.matching(\(render(predicate: forEach.matching))), limit: \(forEach.limit)) { \(forEach.parameter) in", indent))
        \(body)
        \(line("}", indent))
        """
    }

    private func renderForEachString(
        _ forEach: ForEachStringStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        try validateParameter(forEach.parameter)
        let childEnvironment = environment.bindingStringReference(forEach.parameter)
        let values = forEach.values.map(quote).joined(separator: ", ")
        let body = try render(steps: forEach.body, indent: indent + 1, environment: childEnvironment)
        return """
        \(line("try ForEach([\(values)]) { \(forEach.parameter) in", indent))
        \(body)
        \(line("}", indent))
        """
    }

    private func render(predicate: AccessibilityPredicateExpr, environment: RenderEnvironment) throws -> String {
        switch predicate {
        case .state(let state):
            return try render(state: state, environment: environment)
        case .changed(let change):
            return try ".changed(\(render(change: change, environment: environment)))"
        case .predicate(let predicate):
            return try render(predicate: predicate, environment: environment)
        }
    }

    private func render(predicate: AccessibilityPredicate, environment: RenderEnvironment) throws -> String {
        switch predicate {
        case .state(let state):
            return try render(state: state, environment: environment)
        case .changed(let change):
            return try ".changed(\(render(change: change, environment: environment)))"
        }
    }

    private func render(state: StatePredicateExpr, environment: RenderEnvironment) throws -> String {
        switch state {
        case .present(let predicate):
            return ".present(\(try render(predicate: predicate, environment: environment)))"
        case .absent(let predicate):
            return ".absent(\(try render(predicate: predicate, environment: environment)))"
        case .presentTarget(let target):
            return ".present(\(try render(target: target, environment: environment)))"
        case .absentTarget(let target):
            return ".absent(\(try render(target: target, environment: environment)))"
        case .all(let states):
            return ".all([\(try states.map { try render(state: $0, environment: environment) }.joined(separator: ", "))])"
        }
    }

    private func render(state: AccessibilityPredicate.State, environment: RenderEnvironment) throws -> String {
        switch state {
        case .present(let predicate):
            return ".present(\(render(predicate: predicate)))"
        case .absent(let predicate):
            return ".absent(\(render(predicate: predicate)))"
        case .presentTarget(let target):
            return ".present(\(render(target: target)))"
        case .absentTarget(let target):
            return ".absent(\(render(target: target)))"
        case .all(let states):
            return ".all([\(try states.map { try render(state: $0, environment: environment) }.joined(separator: ", "))])"
        }
    }

    private func render(change: AccessibilityPredicate.Change, environment: RenderEnvironment) throws -> String {
        switch change {
        case .screen(let state):
            if let state {
                return try ".screen(where: \(render(state: state, environment: environment)))"
            }
            return ".screen()"
        case .elements:
            return ".elements"
        case .appeared(let predicate):
            return ".appeared(\(render(predicate: predicate)))"
        case .disappeared(let predicate):
            return ".disappeared(\(render(predicate: predicate)))"
        case .updated(let update):
            return ".updated(\(render(update: update)))"
        }
    }

    private func render(change: ChangePredicateExpr, environment: RenderEnvironment) throws -> String {
        switch change {
        case .screen(let state):
            if let state {
                return try ".screen(where: \(render(state: state, environment: environment)))"
            }
            return ".screen()"
        case .elements:
            return ".elements"
        case .appeared(let predicate):
            return try ".appeared(\(render(predicate: predicate, environment: environment)))"
        case .disappeared(let predicate):
            return try ".disappeared(\(render(predicate: predicate, environment: environment)))"
        case .updated(let update):
            return try ".updated(\(render(update: update, environment: environment)))"
        }
    }

    private func render(update: ElementUpdatePredicate) -> String {
        let fields = [
            update.element.map { render(predicate: $0) },
            update.property.map { "property: .\($0.rawValue)" },
            update.from.map { "from: \(quote($0))" },
            update.to.map { "to: \(quote($0))" },
        ].compactMap { $0 }
        return fields.joined(separator: ", ")
    }

    private func render(update: ElementUpdatePredicateExpr, environment: RenderEnvironment) throws -> String {
        let fields = try [
            update.element.map { try render(predicate: $0, environment: environment) },
            update.property.map { "property: .\($0.rawValue)" },
            update.from.map { "from: \(try render(string: $0, environment: environment))" },
            update.to.map { "to: \(try render(string: $0, environment: environment))" },
        ].compactMap { $0 }
        return fields.joined(separator: ", ")
    }

    private func render(target: ElementTargetExpr, environment: RenderEnvironment) throws -> String {
        switch target {
        case .target(let target):
            return render(target: target)
        case .predicate(let predicate, let ordinal):
            let renderedPredicate = try render(predicate: predicate, environment: environment)
            guard let ordinal else { return renderedPredicate }
            return ".target(\(renderedPredicate), ordinal: \(ordinal))"
        case .ref(let reference):
            guard environment.targetReferences.contains(reference) else {
                throw HeistCanonicalSwiftDSLError.unresolvedTargetReference(reference)
            }
            return reference
        }
    }

    private func render(target: ElementTarget) -> String {
        switch target {
        case .predicate(let predicate, let ordinal):
            guard let ordinal else { return renderTargetPredicate(predicate) }
            return ".target(\(render(predicate: predicate)), ordinal: \(ordinal))"
        }
    }

    private func renderTargetPredicate(_ predicate: ElementPredicate) -> String {
        if predicate.traits.isEmpty, predicate.excludeTraits.isEmpty {
            switch (predicate.label, predicate.identifier, predicate.value) {
            case (.some(let label), nil, nil):
                return ".label(\(quote(label)))"
            case (nil, .some(let identifier), nil):
                return ".identifier(\(quote(identifier)))"
            case (nil, nil, .some(let value)):
                return ".value(\(quote(value)))"
            default:
                break
            }
        }
        return ".element(\(renderElementPredicateFields(predicate)))"
    }

    private func render(predicate: ElementPredicate) -> String {
        if predicate.traits.isEmpty, predicate.excludeTraits.isEmpty {
            switch (predicate.label, predicate.identifier, predicate.value) {
            case (.some(let label), nil, nil):
                return ".label(\(quote(label)))"
            case (nil, .some(let identifier), nil):
                return ".identifier(\(quote(identifier)))"
            case (nil, nil, .some(let value)):
                return ".value(\(quote(value)))"
            default:
                break
            }
        }
        return ".element(\(renderElementPredicateFields(predicate)))"
    }

    private func render(predicate: ElementPredicateTemplate, environment: RenderEnvironment) throws -> String {
        if predicate.traits.isEmpty, predicate.excludeTraits.isEmpty {
            switch (predicate.label, predicate.identifier, predicate.value) {
            case (.some(let label), nil, nil):
                return ".label(\(try render(string: label, environment: environment)))"
            case (nil, .some(let identifier), nil):
                return ".identifier(\(try render(string: identifier, environment: environment)))"
            case (nil, nil, .some(let value)):
                return ".value(\(try render(string: value, environment: environment)))"
            default:
                break
            }
        }
        return "ElementPredicateTemplate(\(try renderElementPredicateTemplateFields(predicate, environment: environment)))"
    }

    private func renderElementPredicateFields(_ predicate: ElementPredicate) -> String {
        [
            predicate.label.map { "label: \(quote($0))" },
            predicate.identifier.map { "identifier: \(quote($0))" },
            predicate.value.map { "value: \(quote($0))" },
            renderTraits("traits", predicate.traits),
            renderTraits("excludeTraits", predicate.excludeTraits),
        ].compactMap { $0 }.joined(separator: ", ")
    }

    private func renderElementPredicateTemplateFields(
        _ predicate: ElementPredicateTemplate,
        environment: RenderEnvironment
    ) throws -> String {
        try [
            predicate.label.map { "label: \(try render(string: $0, environment: environment))" },
            predicate.identifier.map { "identifier: \(try render(string: $0, environment: environment))" },
            predicate.value.map { "value: \(try render(string: $0, environment: environment))" },
            renderTraits("traits", predicate.traits),
            renderTraits("excludeTraits", predicate.excludeTraits),
        ].compactMap { $0 }.joined(separator: ", ")
    }

    private func render(string: StringExpr, environment: RenderEnvironment) throws -> String {
        switch string {
        case .literal(let literal):
            return quote(literal)
        case .ref(let reference):
            guard environment.stringReferences.contains(reference) else {
                throw HeistCanonicalSwiftDSLError.unresolvedStringReference(reference)
            }
            return reference
        }
    }

    private func render(point: ScreenPoint) -> String {
        "ScreenPoint(x: \(decimal(point.x)), y: \(decimal(point.y)))"
    }

    private func render(unitPoint: UnitPoint) -> String {
        "UnitPoint(x: \(decimal(unitPoint.x)), y: \(decimal(unitPoint.y)))"
    }

    private func render(duration: GestureDuration) -> String {
        "try! GestureDuration(seconds: \(decimal(duration.seconds)))"
    }

    private func renderTraits(_ label: String, _ traits: [HeistTrait]) -> String? {
        guard !traits.isEmpty else { return nil }
        return "\(label): [\(traits.map { ".\($0.rawValue)" }.joined(separator: ", "))]"
    }

    private func renderTimeout(_ timeout: Double) -> String {
        timeout == 0 ? "" : ", timeout: .seconds(\(decimal(timeout)))"
    }

    private func validateParameter(_ parameter: String) throws {
        guard HeistParameterName.isValid(parameter) else {
            throw HeistCanonicalSwiftDSLError.invalidParameter(parameter)
        }
    }

    private func line(_ text: String, _ indent: Int) -> String {
        "\(String(repeating: "    ", count: indent))\(text)"
    }

    private func quote(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "\(value)" }
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000_001 { return "\(Int(rounded))" }
        var text = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

}

private struct RenderEnvironment {
    static let empty = RenderEnvironment()

    var targetReferences: Set<HeistReferenceName> = []
    var stringReferences: Set<HeistReferenceName> = []

    func bindingTargetReference(_ reference: HeistReferenceName) -> RenderEnvironment {
        var copy = self
        copy.targetReferences.insert(reference)
        return copy
    }

    func bindingStringReference(_ reference: HeistReferenceName) -> RenderEnvironment {
        var copy = self
        copy.stringReferences.insert(reference)
        return copy
    }

    func binding(parameter: HeistParameter) throws -> RenderEnvironment {
        guard let name = parameter.name else { return self }
        switch parameter {
        case .none:
            return self
        case .string:
            return bindingStringReference(name)
        case .elementTarget:
            return bindingTargetReference(name)
        }
    }
}

import Foundation
import TheScore

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
        let body = try render(steps: plan.steps, indent: 1, environment: .empty)
        return """
        try Heist {
        \(body)
        }
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
        case .viewportScroll(let target):
            return try render(viewportScroll: target)
        case .viewportScrollToVisible(let target):
            return "Viewport.ScrollToVisible(\(try render(target: target, environment: environment)))"
        case .viewportScrollToEdge(let target):
            return try render(viewportScrollToEdge: target)
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

    private func render(viewportScroll target: ScrollTarget) throws -> String {
        switch target.selection {
        case .visibleContainer:
            return "Viewport.Scroll(.\(target.direction.rawValue))"
        case .element(let element):
            return "Viewport.Scroll(.\(target.direction.rawValue), in: \(render(target: element)))"
        }
    }

    private func render(viewportScrollToEdge target: ScrollToEdgeTarget) throws -> String {
        switch target.selection {
        case .visibleContainer:
            return "Viewport.ScrollToEdge(.\(target.edge.rawValue))"
        case .element(let element):
            return "Viewport.ScrollToEdge(.\(target.edge.rawValue), in: \(render(target: element)))"
        }
    }

    private func renderConditional(
        _ conditional: ConditionalStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        let cases = try renderCases(
            conditional.cases,
            elseSteps: conditional.elseSteps,
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
            elseSteps: waitForCases.elseSteps,
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
        elseSteps: [HeistStep]?,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        var blocks: [String] = []
        for predicateCase in cases {
            blocks.append(try renderCase(predicateCase, indent: indent, environment: environment))
        }
        if let elseSteps {
            let body = try render(steps: elseSteps, indent: indent + 1, environment: environment)
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
        let body = try render(steps: predicateCase.steps, indent: indent + 1, environment: environment)
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
        let body = try render(steps: forEach.steps, indent: indent + 1, environment: childEnvironment)
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
        let body = try render(steps: forEach.steps, indent: indent + 1, environment: childEnvironment)
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

    private func render(update: ElementUpdatePredicate) -> String {
        let fields = [
            update.element.map { render(predicate: $0) },
            update.property.map { "property: .\($0.rawValue)" },
            update.from.map { "from: \(quote($0))" },
            update.to.map { "to: \(quote($0))" },
        ].compactMap { $0 }
        return fields.joined(separator: ", ")
    }

    private func render(target: ElementTargetExpr, environment: RenderEnvironment) throws -> String {
        switch target {
        case .target(let target):
            return render(target: target)
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

    private func render(predicate: ElementPredicateExpr, environment: RenderEnvironment) throws -> String {
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
        return "ElementPredicateExpr(\(try renderElementPredicateExprFields(predicate, environment: environment)))"
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

    private func renderElementPredicateExprFields(
        _ predicate: ElementPredicateExpr,
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

    var targetReferences: Set<String> = []
    var stringReferences: Set<String> = []

    func bindingTargetReference(_ reference: String) -> RenderEnvironment {
        var copy = self
        copy.targetReferences.insert(reference)
        return copy
    }

    func bindingStringReference(_ reference: String) -> RenderEnvironment {
        var copy = self
        copy.stringReferences.insert(reference)
        return copy
    }
}

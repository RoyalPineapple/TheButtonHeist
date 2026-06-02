import Foundation

public struct HeistSwiftRenderer {
    public init() {}

    public func render(_ plan: HeistPlan) throws -> String {
        var lines = ["Heist {"]
        for step in plan.steps {
            lines.append(contentsOf: try renderStep(step, level: 1))
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func renderStep(
        _ step: HeistStep,
        level: Int,
        forEachBinding: ElementPredicate? = nil
    ) throws -> [String] {
        switch step {
        case .action(let step):
            return try renderActionStep(step, level: level, forEachBinding: forEachBinding)
        case .wait(let step):
            return [indent(renderWait(step, forEachBinding: forEachBinding), level: level)]
        case .conditional(let step):
            return try renderConditional(step, level: level, forEachBinding: forEachBinding)
        case .waitForCases(let step):
            return try renderWaitForCases(step, level: level, forEachBinding: forEachBinding)
        case .forEach(let step):
            return try renderForEach(step, level: level)
        case .warn(let step):
            return [indent("Warn(\(SwiftString.literal(step.message)))", level: level)]
        case .fail(let step):
            return [indent("Fail(\(SwiftString.literal(step.message)))", level: level)]
        }
    }

    private func renderActionStep(
        _ step: ActionStep,
        level: Int,
        forEachBinding: ElementPredicate?
    ) throws -> [String] {
        var lines = [indent(try renderAction(step.command, forEachBinding: forEachBinding), level: level)]
        if let expectation = step.expectation {
            lines.append(indent(
                ".expect(\(renderPredicate(expectation.predicate, forEachBinding: forEachBinding)), timeout: \(renderTimeout(expectation.timeout)))",
                level: level + 1
            ))
        }
        return lines
    }

    private func renderWait(_ step: WaitStep, forEachBinding: ElementPredicate?) -> String {
        "WaitFor(\(renderPredicate(step.predicate, forEachBinding: forEachBinding)), timeout: \(renderTimeout(step.timeout)))"
    }

    private func renderAction(_ command: ClientMessage, forEachBinding: ElementPredicate?) throws -> String {
        switch command {
        case .activate(let target):
            return "Activate(\(renderTarget(target, forEachBinding: forEachBinding)))"
        case .oneFingerTap(let target):
            return "Tap(\(renderGesturePoint(target.selection, forEachBinding: forEachBinding)))"
        case .typeText(let target):
            if let elementTarget = target.elementTarget {
                return "TypeText(\(SwiftString.literal(target.text)), into: \(renderTarget(elementTarget, forEachBinding: forEachBinding)))"
            }
            return "TypeText(\(SwiftString.literal(target.text)))"
        case .scroll(let target):
            return try renderScroll(target, forEachBinding: forEachBinding)
        case .clientHello, .authenticate, .requestInterface, .ping, .status,
             .increment, .decrement, .performCustomAction, .rotor,
             .longPress, .swipe, .drag, .editAction, .setPasteboard,
             .scrollToVisible, .elementSearch, .scrollToEdge,
             .resignFirstResponder, .getPasteboard, .wait, .heistPlan,
             .requestScreen:
            throw HeistSwiftRendererError.unsupportedCommand(command.wireType.rawValue)
        }
    }

    private func renderConditional(
        _ step: ConditionalStep,
        level: Int,
        forEachBinding: ElementPredicate?
    ) throws -> [String] {
        if step.cases.count == 1, let onlyCase = step.cases.first {
            return try renderSingleConditional(
                predicate: onlyCase.predicate,
                steps: onlyCase.steps,
                elseSteps: step.elseSteps,
                level: level,
                forEachBinding: forEachBinding
            )
        }

        var lines = [indent("If {", level: level)]
        lines.append(contentsOf: try renderPredicateCases(step.cases, level: level + 1, forEachBinding: forEachBinding))
        if let elseSteps = step.elseSteps {
            if !step.cases.isEmpty { lines.append("") }
            lines.append(contentsOf: try renderElse(elseSteps, level: level + 1, forEachBinding: forEachBinding))
        }
        lines.append(indent("}", level: level))
        return lines
    }

    private func renderSingleConditional(
        predicate: AccessibilityPredicate,
        steps: [HeistStep],
        elseSteps: [HeistStep]?,
        level: Int,
        forEachBinding: ElementPredicate?
    ) throws -> [String] {
        var lines = [indent("If(\(renderPredicate(predicate, forEachBinding: forEachBinding))) {", level: level)]
        lines.append(contentsOf: try renderBody(steps, level: level + 1, forEachBinding: forEachBinding))
        if let elseSteps {
            lines.append(indent("} otherwise: {", level: level))
            lines.append(contentsOf: try renderBody(elseSteps, level: level + 1, forEachBinding: forEachBinding))
        }
        lines.append(indent("}", level: level))
        return lines
    }

    private func renderWaitForCases(
        _ step: WaitForCasesStep,
        level: Int,
        forEachBinding: ElementPredicate?
    ) throws -> [String] {
        var lines = [indent("WaitFor(timeout: \(renderTimeout(step.timeout))) {", level: level)]
        lines.append(contentsOf: try renderPredicateCases(step.cases, level: level + 1, forEachBinding: forEachBinding))
        if let elseSteps = step.elseSteps {
            if !step.cases.isEmpty { lines.append("") }
            lines.append(contentsOf: try renderElse(elseSteps, level: level + 1, forEachBinding: forEachBinding))
        }
        lines.append(indent("}", level: level))
        return lines
    }

    private func renderForEach(_ step: ForEachStep, level: Int) throws -> [String] {
        var lines = [
            indent("ForEach(.matching(\(renderElementPredicate(step.matching))), limit: \(step.limit)) { element in", level: level),
        ]
        lines.append(contentsOf: try renderBody(step.steps, level: level + 1, forEachBinding: step.matching))
        lines.append(indent("}", level: level))
        return lines
    }

    private func renderPredicateCases(
        _ cases: [PredicateCase],
        level: Int,
        forEachBinding: ElementPredicate?
    ) throws -> [String] {
        var lines: [String] = []
        for (index, predicateCase) in cases.enumerated() {
            if index > 0 { lines.append("") }
            lines.append(indent("Case(\(renderPredicate(predicateCase.predicate, forEachBinding: forEachBinding))) {", level: level))
            lines.append(contentsOf: try renderBody(predicateCase.steps, level: level + 1, forEachBinding: forEachBinding))
            lines.append(indent("}", level: level))
        }
        return lines
    }

    private func renderElse(
        _ steps: [HeistStep],
        level: Int,
        forEachBinding: ElementPredicate?
    ) throws -> [String] {
        var lines = [indent("Else {", level: level)]
        lines.append(contentsOf: try renderBody(steps, level: level + 1, forEachBinding: forEachBinding))
        lines.append(indent("}", level: level))
        return lines
    }

    private func renderBody(
        _ steps: [HeistStep],
        level: Int,
        forEachBinding: ElementPredicate?
    ) throws -> [String] {
        var lines: [String] = []
        for step in steps {
            lines.append(contentsOf: try renderStep(step, level: level, forEachBinding: forEachBinding))
        }
        return lines
    }

    private func renderScroll(_ target: ScrollTarget, forEachBinding: ElementPredicate?) throws -> String {
        let direction = ".\(target.direction.rawValue)"
        switch target.selection {
        case .visibleContainer:
            return "Scroll(\(direction))"
        case .element(let elementTarget):
            return "Scroll(\(direction), in: \(renderTarget(elementTarget, forEachBinding: forEachBinding)))"
        case .container:
            throw HeistSwiftRendererError.unsupportedCommand("scroll container target")
        }
    }

    private func renderGesturePoint(_ selection: GesturePointSelection, forEachBinding: ElementPredicate?) -> String {
        switch selection {
        case .element(let target):
            return renderTarget(target, forEachBinding: forEachBinding)
        case .coordinate(let point):
            return ".point(x: \(renderDecimal(point.x)), y: \(renderDecimal(point.y)))"
        }
    }

    private func renderTarget(_ target: ElementTarget, forEachBinding: ElementPredicate? = nil) -> String {
        switch target {
        case .predicate(let predicate, let ordinal):
            if ordinal == 0, predicate == forEachBinding {
                return "element"
            }
            guard let ordinal else {
                return renderElementPredicate(predicate)
            }
            return ".target(\(renderElementPredicate(predicate)), ordinal: \(ordinal))"
        }
    }

    private func renderPredicate(_ predicate: AccessibilityPredicate, forEachBinding: ElementPredicate? = nil) -> String {
        switch predicate {
        case .state(let state):
            return renderState(state, forEachBinding: forEachBinding)
        case .changed(let change):
            return ".changed(\(renderChange(change, forEachBinding: forEachBinding)))"
        }
    }

    private func renderState(_ state: AccessibilityPredicate.State, forEachBinding: ElementPredicate? = nil) -> String {
        switch state {
        case .present(let predicate):
            return ".present(\(renderElementPredicate(predicate)))"
        case .absent(let predicate):
            return ".absent(\(renderElementPredicate(predicate)))"
        case .presentTarget(let target):
            return ".present(\(renderTarget(target, forEachBinding: forEachBinding)))"
        case .absentTarget(let target):
            return ".absent(\(renderTarget(target, forEachBinding: forEachBinding)))"
        case .all(let states):
            return ".all([\(states.map { renderState($0, forEachBinding: forEachBinding) }.joined(separator: ", "))])"
        }
    }

    private func renderChange(_ change: AccessibilityPredicate.Change, forEachBinding: ElementPredicate? = nil) -> String {
        switch change {
        case .screen(let state):
            if let state {
                return ".screen(where: \(renderState(state, forEachBinding: forEachBinding)))"
            }
            return ".screen()"
        case .elements:
            return ".elements"
        case .appeared(let predicate):
            return ".appeared(\(renderElementPredicate(predicate)))"
        case .disappeared(let predicate):
            return ".disappeared(\(renderElementPredicate(predicate)))"
        case .updated(let update):
            return ".updated(\(renderElementUpdatePredicate(update)))"
        }
    }

    private func renderElementPredicate(_ predicate: ElementPredicate) -> String {
        let hasLabel = predicate.label?.isEmpty == false
        let hasIdentifier = predicate.identifier?.isEmpty == false
        let hasValue = predicate.value?.isEmpty == false
        let hasTraits = !predicate.traits.isEmpty
        let hasExcludeTraits = !predicate.excludeTraits.isEmpty
        let fieldCount = [hasLabel, hasIdentifier, hasValue, hasTraits, hasExcludeTraits].filter { $0 }.count

        if fieldCount == 1 {
            if let label = predicate.label, hasLabel {
                return ".label(\(SwiftString.literal(label)))"
            }
            if let identifier = predicate.identifier, hasIdentifier {
                return ".identifier(\(SwiftString.literal(identifier)))"
            }
            if let value = predicate.value, hasValue {
                return ".value(\(SwiftString.literal(value)))"
            }
        }

        var fields: [String] = []
        if let label = predicate.label, hasLabel {
            fields.append("label: \(SwiftString.literal(label))")
        }
        if let identifier = predicate.identifier, hasIdentifier {
            fields.append("identifier: \(SwiftString.literal(identifier))")
        }
        if let value = predicate.value, hasValue {
            fields.append("value: \(SwiftString.literal(value))")
        }
        if hasTraits {
            fields.append("traits: \(renderTraits(predicate.traits))")
        }
        if hasExcludeTraits {
            fields.append("excludeTraits: \(renderTraits(predicate.excludeTraits))")
        }
        return ".element(\(fields.joined(separator: ", ")))"
    }

    private func renderElementUpdatePredicate(_ update: ElementUpdatePredicate) -> String {
        var fields: [String] = []
        if let element = update.element {
            fields.append("element: \(renderElementPredicate(element))")
        }
        if let property = update.property {
            fields.append("property: .\(property.rawValue)")
        }
        if let from = update.from {
            fields.append("from: \(SwiftString.literal(from))")
        }
        if let to = update.to {
            fields.append("to: \(SwiftString.literal(to))")
        }
        return ".elementUpdate(\(fields.joined(separator: ", ")))"
    }

    private func renderTraits(_ traits: [HeistTrait]) -> String {
        let rendered = traits
            .map(\.rawValue)
            .sorted()
            .map { ".\($0)" }
            .joined(separator: ", ")
        return "[\(rendered)]"
    }

    private func renderTimeout(_ timeout: Double) -> String {
        ".seconds(\(renderDecimal(timeout)))"
    }

    private func renderDecimal(_ value: Double) -> String {
        guard value.isFinite else { return "\(value)" }
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000_001 {
            return "\(Int(rounded))"
        }
        var text = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    private func indent(_ line: String, level: Int = 1) -> String {
        String(repeating: "    ", count: level) + line
    }
}

public enum HeistSwiftRendererError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedCommand(String)

    public var description: String {
        switch self {
        case .unsupportedCommand(let command):
            return "Unsupported ClientMessage command for HeistSwiftRenderer: \(command)"
        }
    }
}

private enum SwiftString {
    static func literal(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                result += "\\\""
            case "\\":
                result += "\\\\"
            case "\0":
                result += "\\0"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    result += "\\u{\(String(scalar.value, radix: 16))}"
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        result += "\""
        return result
    }
}

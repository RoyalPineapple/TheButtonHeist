import Foundation

public struct HeistSwiftRenderer {
    public init() {}

    public func render(_ plan: HeistPlan) throws -> String {
        var lines = ["Heist {"]
        for step in plan.steps {
            lines.append(contentsOf: try renderStep(step))
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func renderStep(_ step: HeistStep) throws -> [String] {
        switch step {
        case .action(let step):
            return try renderActionStep(step)
        case .wait(let step):
            return [indent(renderWait(step))]
        case .warn(let step):
            return [indent("Warn(\(SwiftString.literal(step.message)))")]
        case .fail(let step):
            return [indent("Fail(\(SwiftString.literal(step.message)))")]
        }
    }

    private func renderActionStep(_ step: ActionStep) throws -> [String] {
        var lines = [indent(try renderAction(step.command))]
        if let expectation = step.expectation {
            lines.append(indent(".expect(\(renderPredicate(expectation.predicate)), timeout: \(renderTimeout(expectation.timeout)))", level: 2))
        }
        return lines
    }

    private func renderWait(_ step: WaitStep) -> String {
        "WaitFor(\(renderPredicate(step.predicate)), timeout: \(renderTimeout(step.timeout)))"
    }

    private func renderAction(_ command: ClientMessage) throws -> String {
        switch command {
        case .activate(let target):
            return "Activate(\(renderTarget(target)))"
        case .oneFingerTap(let target):
            return "Tap(\(renderGesturePoint(target.selection)))"
        case .typeText(let target):
            if let elementTarget = target.elementTarget {
                return "TypeText(\(SwiftString.literal(target.text)), into: \(renderTarget(elementTarget)))"
            }
            return "TypeText(\(SwiftString.literal(target.text)))"
        case .scroll(let target):
            return renderScroll(target)
        case .clientHello, .authenticate, .requestInterface, .ping, .status,
             .increment, .decrement, .performCustomAction, .rotor,
             .longPress, .swipe, .drag, .editAction, .setPasteboard,
             .scrollToVisible, .elementSearch, .scrollToEdge,
             .resignFirstResponder, .getPasteboard, .wait, .heistPlan,
             .requestScreen:
            throw HeistSwiftRendererError.unsupportedCommand(command.wireType.rawValue)
        }
    }

    private func renderScroll(_ target: ScrollTarget) -> String {
        let direction = ".\(target.direction.rawValue)"
        switch target.selection {
        case .visibleContainer:
            return "Scroll(\(direction))"
        case .element(let elementTarget):
            return "Scroll(\(direction), in: \(renderTarget(elementTarget)))"
        case .container(let containerTarget):
            if let stableId = containerTarget.stableId {
                return "Scroll(\(direction), in: .container(\(SwiftString.literal(stableId))))"
            }
            return "Scroll(\(direction), in: .container)"
        }
    }

    private func renderGesturePoint(_ selection: GesturePointSelection) -> String {
        switch selection {
        case .element(let target):
            return renderTarget(target)
        case .coordinate(let point):
            return ".point(x: \(renderDecimal(point.x)), y: \(renderDecimal(point.y)))"
        }
    }

    private func renderTarget(_ target: ElementTarget) -> String {
        switch target {
        case .predicate(let predicate, let ordinal):
            guard let ordinal else {
                return renderElementPredicate(predicate)
            }
            return ".target(\(renderElementPredicate(predicate)), ordinal: \(ordinal))"
        }
    }

    private func renderPredicate(_ predicate: AccessibilityPredicate) -> String {
        switch predicate {
        case .state(let state):
            return renderState(state)
        case .changed(let change):
            return ".changed(\(renderChange(change)))"
        }
    }

    private func renderState(_ state: AccessibilityPredicate.State) -> String {
        switch state {
        case .present(let predicate):
            return ".present(\(renderElementPredicate(predicate)))"
        case .absent(let predicate):
            return ".absent(\(renderElementPredicate(predicate)))"
        case .all(let states):
            return ".all([\(states.map(renderState).joined(separator: ", "))])"
        }
    }

    private func renderChange(_ change: AccessibilityPredicate.Change) -> String {
        switch change {
        case .screen(let state):
            if let state {
                return ".screen(where: \(renderState(state)))"
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

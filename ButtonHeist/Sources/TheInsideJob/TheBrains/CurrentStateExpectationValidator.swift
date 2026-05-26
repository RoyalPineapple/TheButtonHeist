#if canImport(UIKit)
#if DEBUG
import TheScore

/// Validates expectations that can be answered from the currently parsed semantic tree.
@MainActor
final class CurrentStateExpectationValidator {
    private init() {}

    static func validate(
        _ expectation: ActionExpectation,
        snapshot: [Screen.ScreenElement]
    ) -> ExpectationResult {
        validate(
            expectation,
            elements: TheStash.WireConversion.toWire(snapshot)
        )
    }

    static func validate(
        _ expectation: ActionExpectation,
        elements: [HeistElement]
    ) -> ExpectationResult {
        switch expectation {
        case .delivery:
            return ExpectationResult(
                met: true,
                expectation: expectation,
                actual: "delivered"
            )
        case .screenChanged:
            return ExpectationResult(
                met: false,
                expectation: expectation,
                actual: "requires observed screen change"
            )
        case .elementsChanged:
            return ExpectationResult(
                met: false,
                expectation: expectation,
                actual: "requires observed element change"
            )
        case .elementUpdated(let heistId, let property, let oldValue, let newValue):
            return validateElementUpdatedCurrentState(
                heistId: heistId,
                property: property,
                oldValue: oldValue,
                newValue: newValue,
                expectation: expectation,
                elements: elements
            )
        case .elementAppeared(let matcher):
            let present = elements.contains { $0.matches(matcher) }
            return ExpectationResult(
                met: present,
                expectation: expectation,
                actual: present ? "present" : "not present"
            )
        case .elementDisappeared(let matcher):
            let present = elements.contains { $0.matches(matcher) }
            return ExpectationResult(
                met: !present,
                expectation: expectation,
                actual: present ? "still present" : "absent"
            )
        case .compound(let expectations):
            let failures = expectations.compactMap { subExpectation -> String? in
                let result = validate(subExpectation, elements: elements)
                guard !result.met else { return nil }
                return "\(subExpectation.summaryDescription): \(result.actual ?? "failed")"
            }
            guard !failures.isEmpty else {
                return ExpectationResult(met: true, expectation: expectation, actual: nil)
            }
            return ExpectationResult(
                met: false,
                expectation: expectation,
                actual: failures.joined(separator: "; ")
            )
        }
    }

    private static func validateElementUpdatedCurrentState(
        heistId: HeistId?,
        property: ElementProperty?,
        oldValue: String?,
        newValue: String?,
        expectation: ActionExpectation,
        elements: [HeistElement]
    ) -> ExpectationResult {
        guard oldValue == nil else {
            return ExpectationResult(
                met: false,
                expectation: expectation,
                actual: "oldValue requires observed update"
            )
        }
        guard let newValue else {
            return ExpectationResult(
                met: false,
                expectation: expectation,
                actual: "newValue required for current state"
            )
        }

        let candidates = elements.filter { element in
            guard let heistId else { return true }
            return element.heistId == heistId
        }
        guard !candidates.isEmpty else {
            return ExpectationResult(met: false, expectation: expectation, actual: "element not found")
        }

        let properties = property.map { [$0] } ?? ElementProperty.allCases
        let matched = candidates.contains { element in
            properties.contains { element.currentStateValue(for: $0) == newValue }
        }
        guard !matched else {
            return ExpectationResult(met: true, expectation: expectation, actual: nil)
        }

        let observed = candidates.prefix(5).map { element in
            let values = properties
                .map { property in
                    "\(property.rawValue): \(element.currentStateValue(for: property) ?? "nil")"
                }
                .joined(separator: ", ")
            return "\(element.heistId): \(values)"
        }.joined(separator: "; ")
        return ExpectationResult(met: false, expectation: expectation, actual: observed)
    }
}

private extension HeistElement {
    func currentStateValue(for property: ElementProperty) -> String? {
        switch property {
        case .label:
            return label
        case .value:
            return value
        case .traits:
            return traits.map(\.rawValue).joined(separator: ", ")
        case .hint:
            return hint
        case .actions:
            return actions.map(\.description).joined(separator: ", ")
        case .frame:
            return "\(Int(frameX)),\(Int(frameY)),\(Int(frameWidth)),\(Int(frameHeight))"
        case .activationPoint:
            return "\(Int(activationPointX)),\(Int(activationPointY))"
        case .customContent:
            return customContent?.formattedCurrentStateValue
        case .rotors:
            guard let rotors, !rotors.isEmpty else { return nil }
            return rotors.map { $0.name }.joined(separator: ", ")
        }
    }
}

private extension Array where Element == HeistCustomContent {
    var formattedCurrentStateValue: String? {
        let formatted = compactMap { item -> String? in
            switch (item.label.isEmpty, item.value.isEmpty) {
            case (false, false): return "\(item.label): \(item.value)"
            case (false, true): return item.label
            case (true, false): return item.value
            case (true, true): return nil
            }
        }
        guard !formatted.isEmpty else { return nil }
        return formatted.joined(separator: "; ")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

import ButtonHeistTestSupport
import ThePlans
@testable import TheScore

extension AccessibilityPredicateTests {
    func observationSnapshot(
        elements: [HeistElement]
    ) -> Observation.Snapshot {
        Observation.Snapshot(
            interface: makeTestInterface(elements: elements),
            context: .empty
        )
    }

    func observationSnapshot(
        nodes: [TestInterfaceNode]
    ) -> Observation.Snapshot {
        Observation.Snapshot(
            interface: makeTestInterface(nodes: nodes),
            context: .empty
        )
    }

    func element(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 100,
        frameHeight: Double = 44,
        activationPointEvidence: ActivationPointEvidence? = nil,
        customContent: [HeistCustomContent]? = nil,
        rotors: [HeistRotor]? = nil,
        actions: [ElementAction] = []
    ) -> HeistElement {
        makeTestHeistElement(
            description: label ?? "",
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            activationPointEvidence: activationPointEvidence,
            customContent: customContent,
            rotors: rotors,
            actions: actions
        )
    }

}

func evaluateExpectation(
    _ expectation: Expectation,
    events: some Sequence<Observation.Event>
) -> Expectation.Result {
    events.reduce(expectation) { expectation, event in
        expectation.evaluating(event)
    }.result
}

extension Expectation.Result {
    var isSatisfied: Bool {
        self == .satisfied
    }

    var outstandingDescription: String? {
        guard case .waiting(let description) = self else { return nil }
        return description
    }
}

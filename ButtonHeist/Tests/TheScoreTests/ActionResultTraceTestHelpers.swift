import Foundation
import ThePlans
@testable import TheScore

extension AccessibilityTrace {
    static func projectingForTests(_ delta: AccessibilityTrace.Delta) -> AccessibilityTrace {
        TestActionResultTrace.projecting(delta)
    }
}

private enum TestActionResultTrace {
    static func projecting(_ delta: AccessibilityTrace.Delta) -> AccessibilityTrace {
        switch delta {
        case .noChange(let payload):
            let interface = makeTestInterface(elements: placeholders(count: payload.elementCount))
            return AccessibilityTrace(captures: [
                capture(sequence: 1, interface: interface),
                capture(sequence: 2, interface: interface),
            ])

        case .elementsChanged(let payload):
            let before = makeTestInterface(elements: beforeElements(for: payload.edits, elementCount: payload.elementCount))
            let after = makeTestInterface(elements: afterElements(for: payload.edits, elementCount: payload.elementCount))
            if payload.edits.isEmpty {
                return AccessibilityTrace(captures: [
                    capture(sequence: 1, interface: before, context: .empty),
                    capture(sequence: 2, interface: before, context: AccessibilityTrace.Context(keyboardVisible: true)),
                ])
            }
            return AccessibilityTrace(captures: [
                capture(sequence: 1, interface: before),
                capture(sequence: 2, interface: after),
            ])

        case .screenChanged(let payload):
            let before = makeTestInterface(elements: placeholders(count: max(payload.elementCount, 1)))
            return AccessibilityTrace(captures: [
                capture(sequence: 1, interface: before, context: AccessibilityTrace.Context(screenId: "before")),
                capture(sequence: 2, interface: payload.newInterface, context: AccessibilityTrace.Context(screenId: "after")),
            ])
        }
    }

    private static func capture(
        sequence: Int,
        interface: Interface,
        context: AccessibilityTrace.Context = .empty
    ) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(sequence: sequence, interface: interface, context: context)
    }

    private static func beforeElements(for edits: ElementEdits, elementCount: Int) -> [HeistElement] {
        padded(edits.removed + edits.updated.map(\.before), count: elementCount)
    }

    private static func afterElements(for edits: ElementEdits, elementCount: Int) -> [HeistElement] {
        padded(edits.added + edits.updated.map(\.after), count: elementCount)
    }

    private static func padded(_ elements: [HeistElement], count: Int) -> [HeistElement] {
        let missing = max(0, count - elements.count)
        return elements + placeholders(count: missing, prefix: "__stable_")
    }

    private static func placeholders(count: Int, prefix: String = "__element_") -> [HeistElement] {
        guard count > 0 else { return [] }
        return (0..<count).map { placeholder(id: "\(prefix)\($0)", label: "Element \($0)") }
    }

    private static func placeholder(
        id: String,
        label: String,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [.button]
    ) -> HeistElement {
        HeistElement(
            description: label,
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: [.activate]
        )
    }
}

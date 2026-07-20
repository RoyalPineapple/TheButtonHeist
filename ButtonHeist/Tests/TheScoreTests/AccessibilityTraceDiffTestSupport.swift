import XCTest
import ButtonHeistTestSupport
import ThePlans
import AccessibilitySnapshotModel
@testable import TheScore

extension Collection where Element == AccessibilityTrace.ChangeFact {
    var testElementEdits: ElementEdits {
        ElementEdits(updated: compactMap { fact -> [ElementUpdate]? in
            guard case .elementsChanged(let payload) = fact else { return nil }
            return payload.updated
        }.flatMap { $0 })
    }

    var testTransient: [HeistElement] {
        flatMap(\.metadata.transient)
    }

    var testCaptureEdge: AccessibilityTrace.CaptureEdge? {
        first?.metadata.captureEdge
    }

    var testInteractionDigest: AccessibilityTrace.InteractionDigest? {
        first?.metadata.interactionDigest
    }

    var testAppearedLabels: [String] {
        flatMap { fact -> [AccessibilityTrace.InterfaceChangeNode] in
            guard case .elementsChanged(let payload) = fact else { return [] }
            return payload.appeared
        }.compactMap(\.elementLabel)
    }

    var testDisappearedLabels: [String] {
        flatMap { fact -> [AccessibilityTrace.InterfaceChangeNode] in
            guard case .elementsChanged(let payload) = fact else { return [] }
            return payload.disappeared
        }.compactMap(\.elementLabel)
    }
}

class AccessibilityTraceDiffTestCase: XCTestCase {
    func makeInterface() -> Interface {
        makeInterface(label: "Menu")
    }

    func makeInterface(label: String) -> Interface {
        makeTestInterface(elements: [
            makeElement(label: label, traits: [.header]),
            makeElement(label: "Total", value: "$5.00", traits: [.staticText]),
        ])
    }

    func makeTraceIdentityInterface(
        _ elements: [(element: HeistElement, identity: String)],
        timestamp: Date = Date(timeIntervalSince1970: 0)
    ) -> Interface {
        let tree = elements.enumerated().map { index, entry in
            AccessibilityHierarchy.element(makeTestAccessibilityElement(entry.element), traversalIndex: index)
        }
        let actionsByPath = Dictionary(uniqueKeysWithValues: elements.enumerated().map { index, entry in
            (TreePath([index]), entry.element.actions)
        })
        let traceIdentityByPath = Dictionary(uniqueKeysWithValues: elements.enumerated().map { index, entry in
            (TreePath([index]), TraceElementIdentity(entry.identity))
        })
        return Interface(
            timestamp: timestamp,
            projecting: tree,
            elementMetadata: { path, _, _ in
                guard let actions = actionsByPath[path] else { return nil }
                return InterfaceElementProjectionMetadata(
                    actions: actions,
                    traceIdentity: traceIdentityByPath[path]
                )
            },
            containerMetadata: { _, _ in nil }
        )
    }

    func makeContainer() -> AccessibilityContainer {
        makeTestAccessibilityContainer()
    }

    func makeElement(
        label: String,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait],
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
            description: label,
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

    func makeAccessibilityElement(
        activationPoint: AccessibilityPoint,
        usesDefaultActivationPoint: Bool
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: "Checkout",
            label: "Checkout",
            value: nil,
            traits: AccessibilityTraits.fromNames([HeistTrait.button.rawValue]),
            identifier: nil,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(AccessibilityRect(x: 0, y: 0, width: 100, height: 44)),
            activationPoint: activationPoint,
            usesDefaultActivationPoint: usesDefaultActivationPoint,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
        )
    }

    func singleChange(
        property: ElementProperty,
        old: HeistElement,
        new: HeistElement
    ) -> PropertyChange? {
        projectElementStateChange(old: old, new: new)?
            .changes
            .first { $0.property == property }
    }

    func assertFactsDeriveFromCaptureEdge(
        _ facts: [AccessibilityTrace.ChangeFact],
        trace: AccessibilityTrace,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let edge = try XCTUnwrap(facts.testCaptureEdge, "Facts did not carry capture edge", file: file, line: line)
        let before = try XCTUnwrap(
            trace.capture(ref: edge.before),
            "Trace did not contain before ref",
            file: file,
            line: line
        )
        let after = try XCTUnwrap(
            trace.capture(ref: edge.after),
            "Trace did not contain after ref",
            file: file,
            line: line
        )

        XCTAssertEqual(edge.before.hash, before.hash, file: file, line: line)
        XCTAssertEqual(edge.after.hash, after.hash, file: file, line: line)
        XCTAssertEqual(facts, AccessibilityTrace.ChangeFact.between(before, after), file: file, line: line)
    }

    func captureFacts(
        before beforeInterface: Interface,
        after afterInterface: Interface,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [AccessibilityTrace.ChangeFact] {
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: beforeInterface
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterInterface,
            parentHash: before.hash
        )
        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        if !facts.isEmpty {
            XCTAssertNotNil(facts.testCaptureEdge, file: file, line: line)
        }
        return facts
    }

    func notification(
        kind: AccessibilityNotificationKind,
        sequence: UInt64
    ) -> AccessibilityNotificationEvidence {
        AccessibilityNotificationEvidence(
            sequence: sequence,
            kind: kind,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            notificationData: .none,
            associatedElement: .none
        )
    }

}

extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}

extension AccessibilityTrace.InterfaceChangeNode {
    var elementLabel: String? {
        guard case .element(let element, _) = node else { return nil }
        return element.label
    }
}

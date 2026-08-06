import ButtonHeistTestSupport
import XCTest
import ThePlans
@_spi(ButtonHeistInternals) @_spi(ButtonHeistTooling) @testable import ButtonHeist
@testable import TheScore

final class CanonicalInterfaceTargetTests: XCTestCase {

    func testSummaryAndFullEncodeTheSameCanonicalTarget() throws {
        let interface = makeTestInterface(elements: [
            makeTestHeistElement(label: "Pay", traits: [.button]),
        ])

        let summary = try encodedInterface(interface, detail: .summary)
        let full = try encodedInterface(interface, detail: .full)
        let expected = AccessibilityTarget.predicate(ElementPredicate(label: "Pay"))

        XCTAssertEqual(summary.elements.first?.target, expected)
        XCTAssertEqual(full.elements.first?.target, expected)
        XCTAssertEqual(
            try JSONDecoder().decode(LegacyResponse.self, from: summary.data)
                .interface.tree.first?.element?.label,
            "Pay"
        )
    }

    func testElementWithoutMatcherFactsOmitsTarget() throws {
        let interface = makeTestInterface(elements: [
            makeTestHeistElement(label: nil, value: nil, identifier: nil, traits: []),
        ])

        let encoded = try encodedInterface(interface, detail: .summary)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded.data) as? [String: Any])
        let interfaceObject = try XCTUnwrap(root["interface"] as? [String: Any])
        let tree = try XCTUnwrap(interfaceObject["tree"] as? [[String: Any]])
        let element = try XCTUnwrap(tree.first?["element"] as? [String: Any])

        XCTAssertNil(encoded.elements.first?.target)
        XCTAssertNil(element["target"])
    }

    func testCanonicalTargetsResolveSemanticStringCollisions() throws {
        let collisions = [
            ("Pay", "PAY"),
            ("Don't", "Don’t"),
            ("Ready - Go", "Ready — Go"),
            ("Loading...", "Loading…"),
        ]

        for (firstLabel, secondLabel) in collisions {
            let interface = makeTestInterface(elements: [
                makeTestHeistElement(label: firstLabel, traits: [.button]),
                makeTestHeistElement(label: secondLabel, traits: [.button]),
            ])
            let elements = try encodedInterface(interface, detail: .summary).elements

            XCTAssertEqual(elements.map { ordinal(of: $0.target) }, [0, 1])
            try assertTargetsResolveSourceElements(elements, in: interface)
        }
    }

    func testCanonicalTargetsUseStableTraitsBeforeOrdinal() throws {
        let interface = makeTestInterface(elements: [
            makeTestHeistElement(label: "Continue", traits: [.button]),
            makeTestHeistElement(label: "Continue", traits: [.link]),
        ])
        let elements = try encodedInterface(interface, detail: .summary).elements

        XCTAssertEqual(elements.map { ordinal(of: $0.target) }, [nil, nil])
        try assertTargetsResolveSourceElements(elements, in: interface)
    }

    func testEqualLabelsAndTraitsUseOrdinal() throws {
        let interface = makeTestInterface(elements: [
            makeTestHeistElement(label: "Continue", traits: [.button]),
            makeTestHeistElement(label: "Continue", traits: [.button]),
        ])
        let elements = try encodedInterface(interface, detail: .summary).elements

        XCTAssertEqual(elements.map { ordinal(of: $0.target) }, [0, 1])
        try assertTargetsResolveSourceElements(elements, in: interface)
    }

    func testEqualIdentifiersIgnoringCaseUseOrdinal() throws {
        let interface = makeTestInterface(elements: [
            makeTestHeistElement(label: nil, identifier: "pay_button", traits: [.button]),
            makeTestHeistElement(label: nil, identifier: "PAY_BUTTON", traits: [.button]),
        ])
        let elements = try encodedInterface(interface, detail: .summary).elements

        XCTAssertEqual(elements.map { ordinal(of: $0.target) }, [0, 1])
        try assertTargetsResolveSourceElements(elements, in: interface)
    }

    func testStateValueDoesNotReplaceUsableIdentityPredicate() throws {
        let interface = makeTestInterface(elements: [
            makeTestHeistElement(label: "Save", value: "Disabled", traits: [.button]),
            makeTestHeistElement(label: "Cancel", value: "Enabled", traits: [.button]),
        ])
        let target = try XCTUnwrap(
            try encodedInterface(interface, detail: .summary).elements.first?.target
        )

        XCTAssertEqual(target, .predicate(ElementPredicate(label: "Save")))
    }

    func testProjectionLimitDoesNotChangeCanonicalOrdinal() throws {
        let interface = makeTestInterface(nodes: [
            .container(
                makeTestScrollableContainer(
                    contentWidth: 390,
                    contentHeight: 1_200,
                    frameWidth: 390,
                    frameHeight: 400
                ),
                containerName: "matches",
                children: [
                    .element(makeTestHeistElement(label: "Pay", traits: [.button])),
                    .element(makeTestHeistElement(label: "PAY", traits: [.button])),
                ]
            ),
        ])
        let encoded = try encodedInterface(
            interface,
            detail: .summary,
            visibleElementBudget: 1
        )
        let visible = try XCTUnwrap(encoded.elements.first)

        XCTAssertEqual(encoded.elements.count, 1)
        XCTAssertEqual(ordinal(of: visible.target), 0)
        try assertTargetResolvesSourceElement(visible, at: 0, in: interface)
    }

    private func assertTargetsResolveSourceElements(
        _ elements: [EncodedElement],
        in interface: Interface,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for (index, element) in elements.enumerated() {
            try assertTargetResolvesSourceElement(
                element,
                at: index,
                in: interface,
                file: file,
                line: line
            )
        }
    }

    private func assertTargetResolvesSourceElement(
        _ element: EncodedElement,
        at index: Int,
        in interface: Interface,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let target = try XCTUnwrap(element.target, file: file, line: line)
        let matches = AccessibilityTargetMatchGraph(interface: interface)
            .resolve(try target.resolve(in: .empty))
            .elements
            .matches

        XCTAssertEqual(matches.map(\.traversalOrder), [index], file: file, line: line)
    }

    private func encodedInterface(
        _ interface: Interface,
        detail: InterfaceDetail,
        visibleElementBudget: Int = ButtonHeistRuntimeKnobs.current.visibleElementBudget
    ) throws -> (data: Data, elements: [EncodedElement]) {
        let profile = ProjectionProfile(
            kind: detail == .full ? .full : .summary,
            limits: .current(
                visibleElementBudget: visibleElementBudget,
                totalNodeBudget: ButtonHeistRuntimeKnobs.current.totalNodeBudget
            )
        )
        let data = try FenceResponse.interface(interface, detail: detail).jsonData(profile: profile)
        let decoded = try JSONDecoder().decode(EncodedResponse.self, from: data)
        return (data, decoded.interface.tree.flatMap(\.elements))
    }

    private func ordinal(of target: AccessibilityTarget?) -> Int? {
        guard case .predicate(_, let ordinal) = target else { return nil }
        return ordinal
    }
}

private struct EncodedResponse: Decodable {
    let interface: EncodedInterface
}

private struct EncodedInterface: Decodable {
    let tree: [EncodedNode]
}

private struct EncodedNode: Decodable {
    let element: EncodedElement?
    let container: EncodedContainer?

    var elements: [EncodedElement] {
        if let element { return [element] }
        return container?.children.flatMap(\.elements) ?? []
    }
}

private struct EncodedElement: Decodable {
    let label: String?
    let target: AccessibilityTarget?
}

private struct EncodedContainer: Decodable {
    let children: [EncodedNode]
}

private struct LegacyInterface: Decodable {
    struct Node: Decodable {
        struct Element: Decodable {
            let label: String?
        }

        let element: Element?
    }

    let tree: [Node]
}

private struct LegacyResponse: Decodable {
    let interface: LegacyInterface
}

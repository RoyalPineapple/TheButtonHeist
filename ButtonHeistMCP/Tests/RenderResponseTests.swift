import AccessibilitySnapshotModel
import ButtonHeist
import Foundation
import Testing
import TheScore
@testable import ButtonHeistMCP

struct RenderResponseTests {

    @Test("inline screenshot render includes image content and interface text")
    func inlineScreenshotRenderIncludesImageAndInterfaceText() {
        let response = FenceResponse.screenshotData(
            payload: ScreenPayload(
                pngData: "abc",
                width: 100,
                height: 200,
                interface: Self.interfaceFixture()
            ),
            options: .init(includeInterface: true)
        )

        let result = ButtonHeistMCPServer.renderResponse(response)

        #expect(result.content.count == 2)
        #expect(String(describing: result.content[0]).contains("image"))
        guard case .text(let text, _, _) = result.content[1] else {
            Issue.record("expected second content item to be text")
            return
        }
        #expect(text.contains(#"group label="Actions" id="actions" containerName="semantic_actions__actions" frame=(0,40,200,100)"#))
    }

    private static func interfaceFixture() -> Interface {
        var elementAnnotations: [InterfaceElementAnnotation] = []
        let button = AccessibilityElement(
            description: "Submit",
            label: "Submit",
            value: nil,
            traits: AccessibilityTraits.fromNames(["button"]),
            identifier: nil,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(AccessibilityRect(x: 0, y: 0, width: 100, height: 44)),
            activationPoint: AccessibilityPoint(x: 50, y: 22),
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
        )
        elementAnnotations.append(InterfaceElementAnnotation(path: TreePath([0, 0]), actions: [.activate]))

        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil, identifier: "actions"),
            frame: AccessibilityRect(x: 0, y: 40, width: 200, height: 100)
        )
        return Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: [
                .container(container, children: [
                    .element(button, traversalIndex: 0),
                ]),
            ],
            annotations: InterfaceAnnotations(
                elements: elementAnnotations,
                containers: [
                    InterfaceContainerAnnotation(path: TreePath([0]), containerName: "semantic_actions__actions"),
                ]
            )
        )
    }
}

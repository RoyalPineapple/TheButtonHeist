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

    @Test("summary heist catalog render stays a compact menu")
    func summaryHeistCatalogRenderStaysCompactMenu() {
        let response = FenceResponse.heistCatalog(HeistCatalog(heists: [
            HeistCatalogEntry(
                name: "checkout",
                role: .capability,
                parameterKind: .string,
                requiresArgument: true,
                summary: "Reusable heist capability requiring string argument",
                tags: ["capability", "parameterized", "semantic-action"]
            ),
        ]))

        let result = ButtonHeistMCPServer.renderResponse(response)

        guard let first = result.content.first, case .text(let text, _, _) = first else {
            Issue.record("expected text content")
            return
        }
        #expect(text.contains("checkout"))
        #expect(text.contains("summary=Reusable heist capability requiring string argument"))
        #expect(!text.contains("actions:"))
        #expect(!text.contains("nested RunHeist:"))
        #expect(!text.contains("semantic surfaces:"))
        #expect(!text.contains("predicate("))
        #expect(!text.contains("invoke"))
    }

    @Test("detailed heist catalog render includes safe derived fields")
    func detailedHeistCatalogRenderIncludesSafeDerivedFields() {
        let response = FenceResponse.heistCatalog(HeistCatalog(heists: [
            HeistCatalogEntry(
                name: "checkout",
                role: .capability,
                parameterKind: .none,
                requiresArgument: false,
                summary: "Reusable heist capability",
                tags: ["capability", "composed", "assertion", "semantic-action"],
                nestedRunHeists: ["checkout.confirm"],
                actionCommands: ["activate"],
                waitCount: 1,
                expectationCount: 1,
                semanticSurfaces: ["label=Checkout", "identifier=confirm_button", "traits=button"],
                validationStatus: .validated
            ),
        ]))

        let result = ButtonHeistMCPServer.renderResponse(response)

        guard let first = result.content.first, case .text(let text, _, _) = first else {
            Issue.record("expected text content")
            return
        }
        #expect(text.contains("nested RunHeist: checkout.confirm"))
        #expect(text.contains("actions: activate"))
        #expect(text.contains("waits=1 expectations=1"))
        #expect(text.contains("semantic surfaces: label=Checkout, identifier=confirm_button, traits=button"))
        #expect(text.contains("validation=validated"))
        #expect(!text.contains("predicate("))
        #expect(!text.contains("point("))
        #expect(!text.contains("heistId"))
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

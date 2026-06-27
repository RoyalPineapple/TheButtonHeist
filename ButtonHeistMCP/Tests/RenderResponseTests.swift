import AccessibilitySnapshotModel
import ButtonHeist
import Foundation
import Testing
import ThePlans
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

    @Test("heist render attaches bounded structured report")
    func heistRenderAttachesBoundedStructuredReport() throws {
        let row = Self.staticText(label: "Row 0", identifier: "row_0")
        let lazyRow = Self.staticText(
            label: "Lazy Row",
            value: "Loaded by scroll",
            identifier: "lazy_row"
        )
        let trace = AccessibilityTrace(first: Self.interface([row]))
            .appending(Self.interface([row, lazyRow]))
        let command = HeistActionCommand.activate(.target(.predicate(ElementPredicate(label: "Load More"))))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let response = FenceResponse.heistExecution(
            plan: plan,
            result: HeistExecutionResult(
                steps: [
                    HeistExecutionStepResult(
                        path: "$.body[0]",
                        kind: .action,
                        status: .passed,
                        durationMs: 1,
                        intent: .action(
                            command: command.wireType.rawValue,
                            target: command.reportTarget.map(String.init(describing:))
                        ),
                        evidence: .action(HeistActionEvidence(
                            command: command,
                            actionResult: ActionResult(
                                success: true,
                                method: .activate,
                                accessibilityTrace: trace
                            )
                        ))
                    ),
                ],
                durationMs: 3
            )
        )

        let result = ButtonHeistMCPServer.renderResponse(response)
        let root = try #require(result.structuredContent?.objectValue)
        let report = try #require(root["report"]?.objectValue)
        let nodes = try #require(report["nodes"]?.arrayValue)
        let node = try #require(nodes.first?.objectValue)
        let evidence = try #require(node["evidence"]?.objectValue)
        let action = try #require(evidence["action"]?.objectValue)
        let actionResult = try #require(action["result"]?.objectValue)
        let delta = try #require(actionResult["delta"]?.objectValue)
        let edits = try #require(delta["edits"]?.objectValue)
        let added = try #require(edits["added"]?.arrayValue)
        let addedElement = try #require(added.first?.objectValue)
        let omitted = try #require(actionResult["omitted"]?.objectValue)
        let traceOmission = try #require(omitted["accessibilityTrace"]?.objectValue)

        #expect(root["status"]?.stringValue == "ok")
        #expect(node["action"] == nil)
        #expect(actionResult["method"]?.stringValue == "activate")
        #expect(delta["kind"]?.stringValue == "elementsChanged")
        #expect(addedElement["label"]?.stringValue == "Lazy Row")
        #expect(addedElement["value"]?.stringValue == "Loaded by scroll")
        #expect(addedElement["identifier"]?.stringValue == "lazy_row")
        #expect(traceOmission["projectedAs"]?.stringValue == "delta")
        #expect(traceOmission["omittedCount"] == .int(2))
        #expect(!String(describing: result.structuredContent).contains("captures"))
        guard case .text(let text, _, _)? = result.content.first else {
            Issue.record("expected compact text content")
            return
        }
        #expect(text.contains("-> elements changed"))
        #expect(!text.contains(#"+ "Lazy Row""#))
    }

    @Test("summary heist catalog render stays a compact menu")
    func summaryHeistCatalogRenderStaysCompactMenu() {
        let response = FenceResponse.heistCatalog(HeistDiscoveryCatalog(heists: [
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
        let response = FenceResponse.heistCatalog(HeistDiscoveryCatalog(heists: [
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

    @Test("error render uses canonical public failure mapping")
    func errorRenderUsesCanonicalPublicFailureMapping() throws {
        let response = FenceResponse.failure(FenceError.connectionTimeout)
        let expected = try #require(response.publicFailure)

        let result = ButtonHeistMCPServer.renderResponse(response)
        let root = try #require(result.structuredContent?.objectValue)
        let details = try #require(root["details"]?.objectValue)

        #expect(result.isError == true)
        #expect(root["status"]?.stringValue == "error")
        #expect(root["message"]?.stringValue == expected.message)
        #expect(root["code"]?.stringValue == expected.code)
        #expect(root["kind"]?.stringValue == expected.kind.rawValue)
        #expect(root["errorCode"]?.stringValue == expected.code)
        #expect(root["phase"]?.stringValue == expected.details.phase.rawValue)
        #expect(root["retryable"] == .bool(expected.details.retryable))
        #expect(root["hint"]?.stringValue == expected.details.hint)
        #expect(details["code"]?.stringValue == expected.code)
        #expect(details["kind"]?.stringValue == expected.kind.rawValue)
        #expect(details["phase"]?.stringValue == expected.details.phase.rawValue)
        #expect(details["retryable"] == .bool(expected.details.retryable))
        #expect(details["hint"]?.stringValue == expected.details.hint)
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

    private static func interface(_ elements: [AccessibilityElement]) -> Interface {
        Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: elements.enumerated().map { index, element in
                .element(element, traversalIndex: index)
            },
            annotations: InterfaceAnnotations(
                elements: elements.indices.map { index in
                    InterfaceElementAnnotation(path: TreePath([index]), actions: [])
                }
            )
        )
    }

    private static func staticText(
        label: String,
        value: String? = nil,
        identifier: String? = nil
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label,
            label: label,
            value: value,
            traits: AccessibilityTraits.fromNames(["staticText"]),
            identifier: identifier,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(AccessibilityRect(x: 0, y: 0, width: 100, height: 44)),
            activationPoint: AccessibilityPoint(x: 50, y: 22),
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: false
        )
    }
}

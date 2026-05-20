import Foundation
import Testing
import AccessibilitySnapshotModel
import MCP
@testable import ButtonHeistMCP
import ButtonHeist
import TheScore

struct ResponseRenderingTests {

    @Test("MCP renders no-change background transients")
    func rendersNoChangeBackgroundTransients() {
        let spinner = makeElement(heistId: "spinner", label: "Loading")
        let trace = makeNoChangeTrace(elementCount: 4, transient: [spinner])

        let result = ButtonHeistMCPServer.renderResponse(
            .ok(message: "done"),
            backgroundAccessibilityTraces: [trace]
        )
        let texts = textContents(result)

        #expect(texts.count == 2)
        #expect(texts[0] == "[while_idle: no net change (4 elements)]\n  +- spinner \"Loading\" [button]")
        #expect(texts[1] == FenceResponse.ok(message: "done").compactFormatted())
    }

    @Test("MCP includes transients alongside element changes")
    func rendersElementChangedBackgroundTransients() {
        let added = makeElement(heistId: "result", label: "Result")
        let spinner = makeElement(heistId: "spinner", label: "Loading")
        let trace = makeAddedTrace(added: added, finalElementCount: 5, transient: [spinner])

        let result = ButtonHeistMCPServer.renderResponse(
            .ok(message: "done"),
            backgroundAccessibilityTraces: [trace]
        )
        let texts = textContents(result)

        #expect(texts.count == 2)
        #expect(texts[0] == "[while_idle: elements changed +1 +-1 (5 total)]\n  + result \"Result\"\n  +- spinner \"Loading\" [button]")
        #expect(texts[1] == FenceResponse.ok(message: "done").compactFormatted())
    }

    @Test("MCP renders every queued background trace")
    func rendersMultipleBackgroundTraces() {
        let spinner = makeElement(heistId: "spinner", label: "Loading")
        let result = makeElement(heistId: "result", label: "Result")
        let traces = [
            makeNoChangeTrace(elementCount: 4, transient: [spinner]),
            makeAddedTrace(added: result, finalElementCount: 5),
        ]

        let response = ButtonHeistMCPServer.renderResponse(
            .ok(message: "done"),
            backgroundAccessibilityTraces: traces
        )
        let texts = textContents(response)

        #expect(texts.count == 3)
        #expect(texts[0] == "[while_idle: no net change (4 elements)]\n  +- spinner \"Loading\" [button]")
        #expect(texts[1] == "[while_idle: elements changed +1 (5 total)]\n  + result \"Result\"")
        #expect(texts[2] == FenceResponse.ok(message: "done").compactFormatted())
    }

    @Test("MCP renders session-lock diagnostics")
    func rendersSessionLockDiagnostics() {
        let payload = SessionLockedPayload(
            message: "Session is locked; owner driver id: driver-a; active connections: 0; remaining timeout: 8s.",
            activeConnections: 0
        )
        let response = FenceResponse.failure(FenceError.sessionLocked(payload.message))

        let result = ButtonHeistMCPServer.renderResponse(response, backgroundAccessibilityTraces: [])
        let texts = textContents(result)

        #expect(result.isError == true)
        #expect(texts.count == 1)
        #expect(texts[0].contains("owner driver id: driver-a"))
        #expect(texts[0].contains("remaining timeout: 8s"))
        #expect(texts[0].contains("BUTTONHEIST_DRIVER_ID"))
    }

    @Test("MCP preserves compact action failure method and kind")
    func rendersCompactActionFailureContract() {
        let actionResult = ActionResult(
            success: false,
            method: .activate,
            message: "No element matching label \"Buy\"",
            errorKind: .elementNotFound
        )
        let response = FenceResponse.action(result: actionResult)

        let result = ButtonHeistMCPServer.renderResponse(response, backgroundAccessibilityTraces: [])
        let texts = textContents(result)

        #expect(result.isError == true)
        #expect(texts == ["activate: error[elementNotFound]: No element matching label \"Buy\""])
    }

    @Test("MCP renders expanded recording responses as bounded JSON text")
    func rendersExpandedRecordingAsJSONText() throws {
        let payload = RecordingPayload(
            videoData: Data("video".utf8).base64EncodedString(),
            width: 390,
            height: 844,
            duration: 2.0,
            frameCount: 16,
            fps: 8,
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 2),
            stopReason: .manual,
            interactionLog: [
                InteractionEvent(
                    timestamp: 0,
                    command: .activate(.matcher(ElementMatcher(label: "Buy"))),
                    result: ActionResult(success: true, method: .activate)
                ),
            ]
        )
        let response = FenceResponse.recordingExpanded(
            path: "/tmp/rec.mp4",
            payload: payload,
            options: RecordingResponseOptions(inlineData: true, includeInteractionLog: true)
        )

        let result = ButtonHeistMCPServer.renderResponse(response, backgroundAccessibilityTraces: [])
        let texts = textContents(result)

        #expect(texts.count == 1)
        let data = try #require(texts[0].data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["path"] as? String == "/tmp/rec.mp4")
        #expect(object["videoData"] as? String == payload.videoData)
        #expect((object["interactionLog"] as? [[String: Any]])?.count == 1)
    }

    private func textContents(_ result: CallTool.Result) -> [String] {
        result.content.compactMap { content in
            if case .text(let text, _, _) = content { return text }
            return nil
        }
    }

    private func makeElement(heistId: String, label: String) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label,
            label: label,
            value: nil,
            identifier: nil,
            traits: [.button],
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: []
        )
    }

    private func makeNoChangeTrace(elementCount: Int, transient: [HeistElement]) -> AccessibilityTrace {
        let interface = makeInterface(elements: makePlaceholderElements(count: elementCount))
        return makeTrace(before: interface, after: interface, transition: AccessibilityTrace.Transition(transient: transient))
    }

    private func makeAddedTrace(
        added: HeistElement,
        finalElementCount: Int,
        transient: [HeistElement] = []
    ) -> AccessibilityTrace {
        let stableElements = makePlaceholderElements(count: finalElementCount - 1)
        let before = makeInterface(elements: stableElements)
        let after = makeInterface(elements: stableElements + [added])
        return makeTrace(before: before, after: after, transition: AccessibilityTrace.Transition(transient: transient))
    }

    private func makeTrace(
        before beforeInterface: Interface,
        after afterInterface: Interface,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: beforeInterface)
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterInterface,
            parentHash: before.hash,
            transition: transition
        )
        return AccessibilityTrace(captures: [before, after])
    }

    private func makeInterface(elements: [HeistElement]) -> Interface {
        let tree = elements.enumerated().map { index, element in
            AccessibilityHierarchy.element(makeAccessibilityElement(element), traversalIndex: index)
        }
        let annotations = InterfaceAnnotations(elements: elements.enumerated().map { index, element in
            InterfaceElementAnnotation(
                path: TreePath([index]),
                heistId: element.heistId,
                actions: element.actions
            )
        })
        return Interface(timestamp: Date(timeIntervalSince1970: 0), tree: tree, annotations: annotations)
    }

    private func makeAccessibilityElement(_ element: HeistElement) -> AccessibilityElement {
        AccessibilityElement(
            description: element.description,
            label: element.label,
            value: element.value,
            traits: AccessibilityTraits.fromNames(element.traits.map(\.rawValue)),
            identifier: element.identifier,
            hint: element.hint,
            userInputLabels: nil,
            shape: .frame(AccessibilityRect(
                x: element.frameX,
                y: element.frameY,
                width: element.frameWidth,
                height: element.frameHeight
            )),
            activationPoint: AccessibilityPoint(x: element.activationPointX, y: element.activationPointY),
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: element.customContent?.map {
                AccessibilityElement.CustomContent(label: $0.label, value: $0.value, isImportant: $0.isImportant)
            } ?? [],
            customRotors: element.rotors?.map { AccessibilityElement.CustomRotor(name: $0.name) } ?? [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: element.respondsToUserInteraction
        )
    }

    private func makePlaceholderElements(count: Int) -> [HeistElement] {
        (0..<max(0, count)).map { index in
            makeElement(heistId: "stable-\(index)", label: "Stable \(index)")
        }
    }
}

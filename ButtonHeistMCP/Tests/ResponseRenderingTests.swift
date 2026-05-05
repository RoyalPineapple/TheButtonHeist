import Testing
import MCP
@testable import ButtonHeistMCP
import ButtonHeist
import TheScore

struct ResponseRenderingTests {

    @Test("MCP renders no-change background transients")
    func rendersNoChangeBackgroundTransients() throws {
        let spinner = makeElement(heistId: "spinner", label: "Loading")
        let delta = InterfaceDelta(kind: .noChange, elementCount: 4, transient: [spinner])

        let result = try ButtonHeistMCPServer.renderResponse(
            .ok(message: "done"),
            backgroundDelta: delta
        )
        let text = renderedText(result)

        #expect(text.contains("[background: no net change (4 elements)]"))
        #expect(text.contains("+- spinner \"Loading\""))
        #expect(text.contains("done"))
    }

    @Test("MCP includes transients alongside element changes")
    func rendersElementChangedBackgroundTransients() throws {
        let added = makeElement(heistId: "result", label: "Result")
        let spinner = makeElement(heistId: "spinner", label: "Loading")
        let delta = InterfaceDelta(
            kind: .elementsChanged,
            elementCount: 5,
            added: [added],
            transient: [spinner]
        )

        let result = try ButtonHeistMCPServer.renderResponse(
            .ok(message: "done"),
            backgroundDelta: delta
        )
        let text = renderedText(result)

        #expect(text.contains("[background: elements changed +1 +-1 (5 total)]"))
        #expect(text.contains("+ result \"Result\""))
        #expect(text.contains("+- spinner \"Loading\""))
    }

    @Test("MCP renders every queued background delta")
    func rendersMultipleBackgroundDeltas() throws {
        let spinner = makeElement(heistId: "spinner", label: "Loading")
        let result = makeElement(heistId: "result", label: "Result")
        let deltas = [
            InterfaceDelta(kind: .noChange, elementCount: 4, transient: [spinner]),
            InterfaceDelta(kind: .elementsChanged, elementCount: 5, added: [result]),
        ]

        let response = try ButtonHeistMCPServer.renderResponse(
            .ok(message: "done"),
            backgroundDeltas: deltas
        )
        let text = renderedText(response)

        #expect(text.contains("[background: no net change (4 elements)]"))
        #expect(text.contains("+- spinner \"Loading\""))
        #expect(text.contains("[background: elements changed +1 (5 total)]"))
        #expect(text.contains("+ result \"Result\""))
    }

    private func renderedText(_ result: CallTool.Result) -> String {
        result.content.compactMap { content in
            if case .text(let text, _, _) = content { return text }
            return nil
        }.joined(separator: "\n")
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
}

import Testing
import MCP
@testable import ButtonHeistMCP
import ButtonHeist
import TheScore

struct ResponseRenderingTests {

    @Test("MCP renders no-change background transients")
    func rendersNoChangeBackgroundTransients() throws {
        let spinner = makeElement(heistId: "spinner", label: "Loading")
        let delta: InterfaceDelta = .noChange(.init(elementCount: 4, transient: [spinner]))

        let result = try ButtonHeistMCPServer.renderResponse(
            .ok(message: "done"),
            backgroundDeltas: [delta]
        )
        let texts = textContents(result)

        #expect(texts.count == 2)
        #expect(texts[0] == "[background: no net change (4 elements)]\n  +- spinner \"Loading\" [button]")
        #expect(texts[1] == FenceResponse.ok(message: "done").compactFormatted())
    }

    @Test("MCP includes transients alongside element changes")
    func rendersElementChangedBackgroundTransients() throws {
        let added = makeElement(heistId: "result", label: "Result")
        let spinner = makeElement(heistId: "spinner", label: "Loading")
        let delta: InterfaceDelta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(added: [added]), transient: [spinner]))

        let result = try ButtonHeistMCPServer.renderResponse(
            .ok(message: "done"),
            backgroundDeltas: [delta]
        )
        let texts = textContents(result)

        #expect(texts.count == 2)
        #expect(texts[0] == "[background: elements changed +1 +-1 (5 total)]\n  + result \"Result\"\n  +- spinner \"Loading\" [button]")
        #expect(texts[1] == FenceResponse.ok(message: "done").compactFormatted())
    }

    @Test("MCP renders every queued background delta")
    func rendersMultipleBackgroundDeltas() throws {
        let spinner = makeElement(heistId: "spinner", label: "Loading")
        let result = makeElement(heistId: "result", label: "Result")
        let deltas: [InterfaceDelta] = [
            .noChange(.init(elementCount: 4, transient: [spinner])),
            .elementsChanged(.init(elementCount: 5, edits: ElementEdits(added: [result]))),
        ]

        let response = try ButtonHeistMCPServer.renderResponse(
            .ok(message: "done"),
            backgroundDeltas: deltas
        )
        let texts = textContents(response)

        #expect(texts.count == 3)
        #expect(texts[0] == "[background: no net change (4 elements)]\n  +- spinner \"Loading\" [button]")
        #expect(texts[1] == "[background: elements changed +1 (5 total)]\n  + result \"Result\"")
        #expect(texts[2] == FenceResponse.ok(message: "done").compactFormatted())
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
}

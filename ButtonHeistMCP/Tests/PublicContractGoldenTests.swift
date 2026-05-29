import Foundation
import MCP
import Testing
@testable import ButtonHeistMCP
import ButtonHeist
import TheScore

struct PublicContractGoldenTests {
    @Test("MCP action failure rendering public contract golden")
    func mcpActionFailureRenderingPublicContractGolden() throws {
        let actionResult = ActionResult(
            success: false,
            method: .activate,
            message: "No element matching label \"Buy\"",
            errorKind: .elementNotFound
        )
        let result = ButtonHeistMCPServer.renderResponse(
            .action(command: .activate, result: actionResult),
            backgroundAccessibilityTraces: []
        )

        #expect(result.isError == true)
        #expect(textContents(result) == ["activate: error[elementNotFound]: No element matching label \"Buy\""])
    }

    @Test("MCP expanded recording rendering public contract golden")
    func mcpExpandedRecordingRenderingPublicContractGolden() throws {
        let payload = RecordingPayload(
            videoData: "dmlkZW8=",
            width: 390,
            height: 844,
            duration: 2.5,
            frameCount: 20,
            fps: 8,
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 2.5),
            stopReason: .manual,
            interactionLog: [
                InteractionEvent(
                    timestamp: 0.25,
                    command: .activate(.matcher(ElementMatcher(label: "Buy"))),
                    result: ActionResult(success: true, method: .activate)
                ),
            ]
        )
        let response = FenceResponse.recordingExpanded(
            path: "/tmp/buttonheist-recording.mp4",
            payload: payload,
            options: RecordingResponseOptions(inlineData: true, includeInteractionLog: true)
        )
        let result = ButtonHeistMCPServer.renderResponse(response, backgroundAccessibilityTraces: [])
        let expectedText = #"{"duration":2.5,"fps":8,"frameCount":20,"height":844,"interactionCount":1,"# +
            #""interactionLog":[{"command":{"payload":{"label":"Buy"},"type":"activate"},"# +
            #""result":{"method":"activate","success":true},"timestamp":0.25}],"# +
            #""path":"\/tmp\/buttonheist-recording.mp4","status":"ok","stopReason":"manual","videoData":"dmlkZW8=","width":390}"#

        #expect(result.isError == false)
        #expect(textContents(result) == [expectedText])
    }

    private func textContents(_ result: CallTool.Result) -> [String] {
        result.content.compactMap { content in
            guard case .text(let text, _, _) = content else { return nil }
            return text
        }
    }
}

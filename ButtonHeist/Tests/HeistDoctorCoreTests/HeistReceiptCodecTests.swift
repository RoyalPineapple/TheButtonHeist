import Foundation
import Testing
import ThePlans
import TheScore
@testable import HeistDoctorCore

@Suite struct HeistReceiptCodecTests {

    @Test func `decode plain heist execution receipt`() throws {
        let receipt = sampleReceipt()
        let data = try HeistReceiptCodec.encode(receipt, format: .json)

        let decoded = try HeistReceiptCodec.decode(data, format: .json)

        #expect(decoded == receipt)
    }

    @Test func `decode gzip heist execution receipt`() throws {
        let receipt = sampleReceipt()
        let data = try HeistReceiptCodec.encode(receipt, format: .gzipJSON)
        let jsonData = try HeistReceiptCodec.encode(receipt, format: .json)

        let decoded = try HeistReceiptCodec.decode(data, format: .gzipJSON)

        #expect(decoded == receipt)
        #expect(data.count < jsonData.count)
    }

    @Test func `round trip gzip receipt from file extension`() throws {
        let receipt = sampleReceipt()
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("heist-receipt-codec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("receipt.json.gz")
        try HeistReceiptCodec.write(receipt, to: url)

        let decoded = try HeistReceiptCodec.decode(contentsOf: url)

        #expect(decoded == receipt)
    }

    private func sampleReceipt() -> HeistExecutionResult {
        let before = makeTestInterface(elements: [
            element(label: "Checkout", traits: [.button], actions: [.activate]),
        ])
        let after = makeTestInterface(elements: [
            element(label: "Review Order", traits: [.header]),
        ])
        let trace = AccessibilityTrace(first: before).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "checkout")
        )
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: trace,
            subjectEvidence: ActionSubjectEvidence(
                source: .resolvedSemanticTarget,
                target: .predicate(.label("Checkout")),
                element: element(label: "Checkout", traits: [.button], actions: [.activate])
            )
        )
        return HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .action,
                    status: .passed,
                    durationMs: 12,
                    intent: .action(command: "Activate", target: "target(predicate(label=\"Checkout\"))"),
                    evidence: .action(HeistActionEvidence(
                        command: .activate(.predicate(.label("Checkout"))),
                        actionResult: result,
                        expectation: ExpectationResult(met: true, predicate: nil, actual: "screenChanged")
                    ))
                ),
            ],
            durationMs: 12
        )
    }

    private func element(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait] = [],
        actions: [ElementAction] = []
    ) -> HeistElement {
        HeistElement(
            description: label ?? "element",
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: actions
        )
    }
}

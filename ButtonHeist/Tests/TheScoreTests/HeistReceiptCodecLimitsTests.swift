import Foundation
import Testing
@_spi(ButtonHeistInternals) import TheScore

@Suite struct HeistReceiptCodecLimitsTests {

    @Test func `round trip gzip receipt from file extension`() throws {
        let receipt = sampleReceipt(message: "boom")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("receipt.json.gz")

        try HeistReceiptCodec.write(receipt, to: url)

        #expect(try HeistReceiptCodec.decode(contentsOf: url) == receipt)
    }

    @Test func `oversized gzip compressed receipt is rejected before decompression`() throws {
        let limits = HeistReceiptCodecLimits(maxGzipCompressedBytes: 8, maxGzipDecompressedBytes: 1024)
        let data = Data(repeating: 0x1F, count: limits.maxGzipCompressedBytes + 1)

        try expectReceiptDecodeError(
            data,
            limits: limits,
            containing: [
                "compressed data is too large",
                "limit 8 bytes",
            ]
        )
    }

    @Test func `oversized gzip decompressed receipt is rejected without unbounded growth`() throws {
        let receipt = sampleReceipt(message: String(repeating: "x", count: 4096))
        let data = try HeistReceiptCodec.encode(receipt, format: .gzipJSON)
        let limits = HeistReceiptCodecLimits(
            maxGzipCompressedBytes: data.count,
            maxGzipDecompressedBytes: 512
        )

        try expectReceiptDecodeError(
            data,
            limits: limits,
            containing: [
                "decompressed data is too large",
                "limit 512 bytes",
            ]
        )
    }

    @Test func `corrupt gzip receipt reports useful diagnostic`() throws {
        let corruptGzip = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00])
        let limits = HeistReceiptCodecLimits(maxGzipCompressedBytes: 1024, maxGzipDecompressedBytes: 1024)

        try expectReceiptDecodeError(
            corruptGzip,
            limits: limits,
            containing: [
                "gzip decompression failed",
                "corrupt or truncated gzip data",
            ]
        )
    }

    private func sampleReceipt(message: String) -> HeistExecutionResult {
        HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .fail,
                    status: .failed,
                    durationMs: 1,
                    intent: .fail(message: message),
                    failure: HeistFailureDetail(
                        category: .explicitFailure,
                        contract: "Fail",
                        observed: message
                    )
                ),
            ],
            durationMs: 1,
            abortedAtPath: "$.body[0]"
        )
    }

    private func expectReceiptDecodeError(
        _ data: Data,
        limits: HeistReceiptCodecLimits,
        containing substrings: [String]
    ) throws {
        do {
            _ = try HeistReceiptCodec.decode(data, format: .gzipJSON, limits: limits)
            Issue.record("Expected receipt decode to fail")
        } catch {
            let description = String(describing: error)
            for substring in substrings {
                #expect(description.contains(substring), "\(description) did not contain \(substring)")
            }
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("heist-receipt-codec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

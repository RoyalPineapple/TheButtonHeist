import ButtonHeistTestSupport
import Foundation
import Testing
@_spi(ButtonHeistInternals) import TheScore

@Suite struct HeistReceiptCodecLimitsTests {

    @Test func `round trip gzip receipt from file extension`() throws {
        let receipt = sampleReceipt(message: "boom")
        try withTemporaryDirectory(prefix: "heist-receipt-codec") { directory in
            let url = directory.appendingPathComponent("receipt.json.gz")

            try HeistReceiptCodec.write(receipt, to: url)

            #expect(try HeistReceiptCodec.decode(contentsOf: url) == receipt)
        }
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

    @Test func `oversized plain JSON receipt data is rejected before decode`() throws {
        let limits = HeistReceiptCodecLimits(
            maxJSONBytes: 8,
            maxGzipCompressedBytes: 1024,
            maxGzipDecompressedBytes: 1024
        )
        let data = Data(repeating: 0x7B, count: limits.maxJSONBytes + 1)

        try expectReceiptDecodeError(
            data,
            format: .json,
            limits: limits,
            containing: [
                "JSON receipt data is too large",
                "limit 8 bytes",
            ]
        )
    }

    @Test func `oversized plain JSON receipt file is rejected before unbounded read`() throws {
        let limits = HeistReceiptCodecLimits(
            maxJSONBytes: 8,
            maxGzipCompressedBytes: 1024,
            maxGzipDecompressedBytes: 1024
        )
        try withTemporaryDirectory(prefix: "heist-receipt-codec") { directory in
            let url = directory.appendingPathComponent("receipt.json")
            try Data(repeating: 0x7B, count: limits.maxJSONBytes + 1).write(to: url)

            do {
                _ = try HeistReceiptCodec.decode(contentsOf: url, limits: limits)
                Issue.record("Expected receipt decode to fail")
            } catch {
                let description = String(describing: error)
                #expect(description.contains("JSON receipt data is too large"), "\(description)")
                #expect(description.contains("limit 8 bytes"), "\(description)")
            }
        }
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

    private func sampleReceipt(message: String) -> HeistExecutionReceipt {
        HeistReceiptFixture.result(
            steps: [HeistReceiptFixture.explicitFailure(message: message)],
            durationMs: 1
        )
    }

    private func expectReceiptDecodeError(
        _ data: Data,
        format: HeistReceiptFormat = .gzipJSON,
        limits: HeistReceiptCodecLimits,
        containing substrings: [String]
    ) throws {
        do {
            _ = try HeistReceiptCodec.decode(data, format: format, limits: limits)
            Issue.record("Expected receipt decode to fail")
        } catch {
            let description = String(describing: error)
            for substring in substrings {
                #expect(description.contains(substring), "\(description) did not contain \(substring)")
            }
        }
    }

}

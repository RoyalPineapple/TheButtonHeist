import ButtonHeistTestSupport
import Foundation
import Testing
@_spi(ButtonHeistInternals) import TheScore

@Suite struct HeistResultCodecLimitsTests {

    @Test func `round trip gzip result from file extension`() throws {
        let result = sampleResult(message: "boom")
        try withTemporaryDirectory(prefix: "heist-result-codec") { directory in
            let url = directory.appendingPathComponent("result.json.gz")

            try HeistResultCodec.write(result, to: url)

            #expect(try HeistResultCodec.decode(contentsOf: url) == result)
        }
    }

    @Test func `oversized gzip compressed result is rejected before decompression`() throws {
        let limits = HeistResultCodecLimits(maxGzipCompressedBytes: 8, maxGzipDecompressedBytes: 1024)
        let data = Data(repeating: 0x1F, count: limits.maxGzipCompressedBytes + 1)

        try expectResultDecodeError(
            data,
            limits: limits,
            containing: [
                "compressed data is too large",
                "limit 8 bytes",
            ]
        )
    }

    @Test func `oversized plain JSON result data is rejected before decode`() throws {
        let limits = HeistResultCodecLimits(
            maxJSONBytes: 8,
            maxGzipCompressedBytes: 1024,
            maxGzipDecompressedBytes: 1024
        )
        let data = Data(repeating: 0x7B, count: limits.maxJSONBytes + 1)

        try expectResultDecodeError(
            data,
            format: .json,
            limits: limits,
            containing: [
                "JSON result data is too large",
                "limit 8 bytes",
            ]
        )
    }

    @Test func `oversized plain JSON result file is rejected before unbounded read`() throws {
        let limits = HeistResultCodecLimits(
            maxJSONBytes: 8,
            maxGzipCompressedBytes: 1024,
            maxGzipDecompressedBytes: 1024
        )
        try withTemporaryDirectory(prefix: "heist-result-codec") { directory in
            let url = directory.appendingPathComponent("result.json")
            try Data(repeating: 0x7B, count: limits.maxJSONBytes + 1).write(to: url)

            do {
                _ = try HeistResultCodec.decode(contentsOf: url, limits: limits)
                Issue.record("Expected result decode to fail")
            } catch {
                let description = String(describing: error)
                #expect(description.contains("JSON result data is too large"), "\(description)")
                #expect(description.contains("limit 8 bytes"), "\(description)")
            }
        }
    }

    @Test func `oversized gzip decompressed result is rejected without unbounded growth`() throws {
        let result = sampleResult(message: String(repeating: "x", count: 4096))
        let data = try HeistResultCodec.encode(result, format: .gzipJSON)
        let limits = HeistResultCodecLimits(
            maxGzipCompressedBytes: data.count,
            maxGzipDecompressedBytes: 512
        )

        try expectResultDecodeError(
            data,
            limits: limits,
            containing: [
                "decompressed data is too large",
                "limit 512 bytes",
            ]
        )
    }

    @Test func `corrupt gzip result reports useful diagnostic`() throws {
        let corruptGzip = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00])
        let limits = HeistResultCodecLimits(maxGzipCompressedBytes: 1024, maxGzipDecompressedBytes: 1024)

        try expectResultDecodeError(
            corruptGzip,
            limits: limits,
            containing: [
                "gzip decompression failed",
                "corrupt or truncated gzip data",
            ]
        )
    }

    private func sampleResult(message: String) -> HeistResult {
        HeistResultFixture.result(
            steps: [HeistResultFixture.explicitFailure(message: message)],
            durationMs: 1
        )
    }

    private func expectResultDecodeError(
        _ data: Data,
        format: HeistResultFormat = .gzipJSON,
        limits: HeistResultCodecLimits,
        containing substrings: [String]
    ) throws {
        do {
            _ = try HeistResultCodec.decode(data, format: format, limits: limits)
            Issue.record("Expected result decode to fail")
        } catch {
            let description = String(describing: error)
            for substring in substrings {
                #expect(description.contains(substring), "\(description) did not contain \(substring)")
            }
        }
    }

}

import ButtonHeistTestSupport
import Foundation
import Testing

@Suite struct ButtonHeistTestSupportTests {

    @Test func `shared JSONProbe reads nested typed values`() throws {
        let probe = try JSONProbe(data: Data("""
        {
          "items": [{"label": "Save"}],
          "metadata": {
            "enabled": true,
            "count": 2,
            "ratio": 1,
            "traits": ["button", "selected"],
            "empty": {}
          }
        }
        """.utf8))

        let firstItem = try #require(try probe.array("items").first)
        let metadata = try probe.object("metadata")

        #expect(try firstItem.string("label") == "Save")
        #expect(try metadata.bool("enabled"))
        #expect(try metadata.int("count") == 2)
        #expect(try metadata.double("ratio") == 1)
        #expect(try metadata.strings("traits") == ["button", "selected"])
        #expect(try metadata.object("empty").isEmptyObject())
    }

    @Test func `shared JSONProbe reports typed path failures`() throws {
        let probe = try JSONProbe(data: Data(#"{"root":{"bad-key":true}}"#.utf8))

        do {
            _ = try probe.object("root").string("bad-key")
            Issue.record("Expected JSONProbeFailure")
        } catch let error as JSONProbeFailure {
            #expect(error.path == #"$.root["bad-key"]"#)
            #expect(error.reason == "Expected string, got bool")
        }
    }

    @Test func `shared temporary directory fixture removes directory after body returns`() throws {
        let directory = try withTemporaryDirectory(prefix: "temp-directory-fixture") { directory in
            #expect(FileManager.default.fileExists(atPath: directory.path))
            try Data([0x00]).write(to: directory.appendingPathComponent("scratch.bin"))
            return directory
        }

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func `shared temporary directory fixture throws creation failures before body runs`() throws {
        try withTemporaryDirectory(prefix: "temp-directory-fixture-parent") { directory in
            let fileURL = directory.appendingPathComponent("not-a-directory")
            try Data([0x00]).write(to: fileURL)

            #expect(throws: (any Error).self) {
                try withTemporaryDirectory(prefix: "child", rootDirectory: fileURL) { _ in
                    Issue.record("Expected directory creation to fail before body runs")
                }
            }
        }
    }

    @Test func `shared receipt directory fixture finds one gzip artifact recursively`() throws {
        let receiptName = try withReceiptDirectory(prefix: "receipt-directory-fixture") { directory in
            let nestedDirectory = directory.appendingPathComponent("checkout-flow", isDirectory: true)
            try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
            try Data([0x00]).write(to: nestedDirectory.appendingPathComponent("receipt-passed.json.gz"))
            try Data([0x00]).write(to: nestedDirectory.appendingPathComponent("notes.txt"))

            return try assertSingleReceiptArtifactURL(in: directory).lastPathComponent
        }

        #expect(receiptName == "receipt-passed.json.gz")
    }
}

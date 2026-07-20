import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
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

    @Test func `gzip result rejects negative duration after decompression`() throws {
        // gzip for {"steps":[],"durationMs":-1}
        let malformedGzip = try #require(Data(
            base64Encoded: "H4sIAAAAAAAAA6tWKi5JLShWsoqO1VFKKS1KLMnMz/MF8nUNawGXzDspHAAAAA=="
        ))

        #expect(throws: DecodingError.self) {
            try HeistResultCodec.decode(malformedGzip, format: .gzipJSON)
        }
    }

    @Test func `result node count is bounded before codec exposure`() throws {
        let data = nestedResultData()
        let limits = HeistResultCodecLimits(
            maxJSONBytes: data.count,
            maxGzipCompressedBytes: 1024,
            maxGzipDecompressedBytes: 1024,
            maxNodeCount: 1
        )

        try expectResultDecodeError(
            data,
            format: .json,
            limits: limits,
            containing: ["too many nodes", "limit 1"]
        )
    }

    @Test func `result nesting depth is bounded before codec exposure`() throws {
        let data = nestedResultData()
        let limits = HeistResultCodecLimits(
            maxJSONBytes: data.count,
            maxGzipCompressedBytes: 1024,
            maxGzipDecompressedBytes: 1024,
            maxNestingDepth: 1
        )

        try expectResultDecodeError(
            data,
            format: .json,
            limits: limits,
            containing: ["nesting is too deep", "limit 1"]
        )
    }

    @Test func `aggregate admission rejects duplicate execution paths`() throws {
        let data = try duplicatingRoot(in: nestedResultData())

        try expectResultDecodeError(
            data,
            format: .json,
            limits: .default,
            containing: ["duplicate execution path", "$.body[0]"]
        )
    }

    @Test func `aggregate admission rejects child paths outside their parent`() throws {
        let data = try replacingChildPath(in: nestedResultData(), with: "$.body[1]")

        try expectResultDecodeError(
            data,
            format: .json,
            limits: .default,
            containing: ["is not a descendant", "$.body[0]", "$.body[1]"]
        )
    }

    @Test func `aggregate admission rejects child paths outside parent grammar`() throws {
        let data = try replacingChildPath(in: nestedResultData(), with: "$.body[0].conditional.cases[0].body[0]")

        try expectResultDecodeError(
            data,
            format: .json,
            limits: .default,
            containing: ["is not a legal heist child", "$.body[0]", "$.body[0].conditional.cases[0].body[0]"]
        )
    }

    @Test func `aggregate admission admits auxiliary failure screenshot roots`() throws {
        let result = try HeistResult(
            steps: [
                HeistResultFixture.explicitFailure(path: "$.body[0]", message: "stop"),
                HeistResultFixture.action(
                    path: "$.body[0].failure.actions[0]",
                    command: .takeScreenshot,
                    result: .success(payload: .screenshot(nil))
                ),
            ],
            durationMs: 2
        )

        #expect(result.steps.map(\.path) == ["$.body[0]", "$.body[0].failure.actions[0]"])
    }

    @Test func `aggregate admission rejects loop iteration paths with non iteration child nodes`() throws {
        let declaration = try #require(HeistForEachStringDeclaration(parameter: "item", count: 1))
        let child = HeistResultFixture.warning(
            path: "$.body[0].for_each_string.iterations[0]",
            message: "not an iteration"
        )
        let evidence = try #require(HeistForEachStringEvidence(iterationCount: 1))
        let children = try #require(HeistPassingChildren([child]))
        let root = HeistExecutionStepResult.forEachString(
            path: "$.body[0]",
            durationMs: 1,
            declaration: declaration,
            completion: .passed(
                evidence: try #require(HeistPassedForEachStringEvidence(evidence)),
                children: children
            )
        )

        #expect(throws: (any Error).self) {
            try HeistResult(steps: [root], durationMs: 1)
        }
    }

    @Test func `aggregate admission uses branch local ordinals for repeat until else body`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let declaration = HeistRepeatUntilDeclaration(predicate: predicate, timeout: 0.5)
        let unmet = try #require(ExpectationResult.Unmet(ExpectationResult(
            met: false,
            predicate: predicate,
            actual: "not found"
        )))
        let iterationEvidence = try #require(HeistRepeatUntilEvidence.continued(
            iterationCount: 1,
            iterationOrdinal: 0,
            expectation: unmet
        ))
        let iteration = HeistExecutionStepResult.repeatUntilIteration(
            path: "$.body[0].repeat_until.iterations[0]",
            durationMs: 1,
            declaration: declaration,
            completion: .passed(
                evidence: try #require(HeistPassedRepeatUntilIterationEvidence(iterationEvidence))
            )
        )
        let elseStep = HeistResultFixture.warning(
            path: "$.body[0].repeat_until.else_body[0]",
            message: "handled timeout"
        )
        let rootEvidence = try #require(HeistRepeatUntilEvidence.handledElse(
            iterationCount: 1,
            expectation: unmet,
            lastObservedSummary: "not found"
        ))
        let root = HeistExecutionStepResult.repeatUntil(
            path: "$.body[0]",
            durationMs: 2,
            declaration: declaration,
            completion: .passed(
                evidence: try #require(HeistPassedRepeatUntilEvidence(rootEvidence)),
                children: try #require(HeistPassingChildren([iteration, elseStep]))
            )
        )

        let result = try HeistResult(steps: [root], durationMs: 2)

        #expect(result.steps.first?.children.map { $0.path } == [
            "$.body[0].repeat_until.iterations[0]",
            "$.body[0].repeat_until.else_body[0]",
        ])
    }

    @Test func `aggregate admission rejects conditional children outside matched case`() throws {
        let selection = HeistCaseSelectionResult.selectingFirstMatch(
            cases: [
                HeistCaseMatchResult(predicate: .exists(.label("One")), met: true),
                HeistCaseMatchResult(predicate: .exists(.label("Two")), met: false),
            ],
            ifNone: .noMatch,
            elapsedMs: 1
        )
        let root = HeistResultFixture.conditional(
            selection: selection,
            children: [
                HeistResultFixture.warning(
                    path: "$.body[0].conditional.cases[1].body[0]",
                    message: "wrong case"
                ),
            ]
        )

        try expectAggregateAdmissionError(
            steps: [root],
            containing: ["incoherent execution evidence", "conditional children do not match selected branch"]
        )
    }

    @Test func `aggregate admission rejects conditional case children for else outcome`() throws {
        let selection = HeistCaseSelectionResult.selectingFirstMatch(
            cases: [
                HeistCaseMatchResult(predicate: .exists(.label("One")), met: false),
            ],
            ifNone: .noMatch,
            elapsedMs: 1
        ).selectingElseBranch()
        let root = HeistResultFixture.conditional(
            selection: selection,
            children: [
                HeistResultFixture.warning(
                    path: "$.body[0].conditional.cases[0].body[0]",
                    message: "wrong branch"
                ),
            ]
        )

        try expectAggregateAdmissionError(
            steps: [root],
            containing: ["incoherent execution evidence", "conditional children do not match selected branch"]
        )
    }

    @Test func `aggregate admission rejects loop evidence count that disagrees with iteration children`() throws {
        let declaration = try #require(HeistForEachStringDeclaration(parameter: "item", count: 2))
        let evidence = try #require(HeistForEachStringEvidence(iterationCount: 2))
        let iteration = HeistResultFixture.forEachStringIteration(
            path: "$.body[0].for_each_string.iterations[0]",
            count: 2,
            iterationCount: 2,
            ordinal: 0,
            value: "one",
            status: .passed,
            children: []
        )
        let root = HeistExecutionStepResult.forEachString(
            path: "$.body[0]",
            durationMs: 1,
            declaration: declaration,
            completion: .passed(
                evidence: try #require(HeistPassedForEachStringEvidence(evidence)),
                children: try #require(HeistPassingChildren([iteration]))
            )
        )

        try expectAggregateAdmissionError(
            steps: [root],
            containing: ["for_each_string evidence iterationCount 2 does not match 1 iteration child"]
        )
    }

    @Test func `aggregate admission rejects repeat until handled else evidence without else children`() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let declaration = HeistRepeatUntilDeclaration(predicate: predicate, timeout: 0.5)
        let unmet = try #require(ExpectationResult.Unmet(ExpectationResult(
            met: false,
            predicate: predicate,
            actual: "not found"
        )))
        let iterationEvidence = try #require(HeistRepeatUntilEvidence.continued(
            iterationCount: 1,
            iterationOrdinal: 0,
            expectation: unmet
        ))
        let iteration = HeistExecutionStepResult.repeatUntilIteration(
            path: "$.body[0].repeat_until.iterations[0]",
            durationMs: 1,
            declaration: declaration,
            completion: .passed(
                evidence: try #require(HeistPassedRepeatUntilIterationEvidence(iterationEvidence))
            )
        )
        let rootEvidence = try #require(HeistRepeatUntilEvidence.handledElse(
            iterationCount: 1,
            expectation: unmet,
            lastObservedSummary: "not found"
        ))
        let root = HeistExecutionStepResult.repeatUntil(
            path: "$.body[0]",
            durationMs: 2,
            declaration: declaration,
            completion: .passed(
                evidence: try #require(HeistPassedRepeatUntilEvidence(rootEvidence)),
                children: try #require(HeistPassingChildren([iteration]))
            )
        )

        try expectAggregateAdmissionError(
            steps: [root],
            containing: ["repeat_until handled_else evidence requires else_body children"]
        )
    }

    @Test func `aggregate admission rejects sparse top level body roots`() throws {
        try expectAggregateAdmissionError(
            steps: [HeistResultFixture.warning(path: "$.body[1]", message: "sparse")],
            containing: ["top-level body root indices must be contiguous and in result order"]
        )
    }

    @Test func `aggregate admission rejects stale warning fixture with heist child path`() throws {
        let data = Data(#"""
        {
          "steps": [{
            "path": "$.body[0]",
            "durationMs": 1,
            "node": {
              "type": "warning",
              "outcome": "passed",
              "message": "root",
              "children": [{
                "path": "$.body[0].heist.body[0]",
                "durationMs": 100,
                "node": {
                  "type": "warning",
                  "outcome": "passed",
                  "message": "child",
                  "children": []
                }
              }]
            }
          }],
          "durationMs": 5
        }
        """#.utf8)

        try expectResultDecodeError(
            data,
            format: .json,
            limits: .default,
            containing: ["is not a legal warn child", "$.body[0]", "$.body[0].heist.body[0]"]
        )
    }

    @Test func `aggregate and parent durations are independent wall clock observations`() throws {
        let result = try HeistResultCodec.decode(nestedResultData())
        let root = try #require(result.steps.first)
        let child = try #require(root.children.first)

        #expect(result.durationMs == 5)
        #expect(root.durationMs == 1)
        #expect(child.durationMs == 100)
    }

    private func sampleResult(message: String) -> HeistResult {
        HeistResultFixture.result(
            steps: [HeistResultFixture.explicitFailure(message: message)],
            durationMs: 1
        )
    }

    private func nestedResultData() -> Data {
        Data(#"""
        {
          "steps": [{
            "path": "$.body[0]",
            "durationMs": 1,
            "node": {
              "type": "heist",
              "outcome": "passed",
              "children": [{
                "path": "$.body[0].heist.body[0]",
                "durationMs": 100,
                "node": {
                  "type": "warning",
                  "outcome": "passed",
                  "message": "child",
                  "children": []
                }
              }]
            }
          }],
          "durationMs": 5
        }
        """#.utf8)
    }

    private func duplicatingRoot(in data: Data) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var steps = try #require(object["steps"] as? [[String: Any]])
        steps.append(steps[0])
        object["steps"] = steps
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func replacingChildPath(in data: Data, with path: String) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var steps = try #require(object["steps"] as? [[String: Any]])
        var root = steps[0]
        var node = try #require(root["node"] as? [String: Any])
        var children = try #require(node["children"] as? [[String: Any]])
        children[0]["path"] = path
        node["children"] = children
        root["node"] = node
        steps[0] = root
        object["steps"] = steps
        return try JSONSerialization.data(withJSONObject: object)
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

    private func expectAggregateAdmissionError(
        steps: [HeistExecutionStepResult],
        containing substrings: [String]
    ) throws {
        do {
            _ = try HeistResult(steps: steps, durationMs: 1)
            Issue.record("Expected result admission to fail")
        } catch {
            let description = String(describing: error)
            for substring in substrings {
                #expect(description.contains(substring), "\(description) did not contain \(substring)")
            }
        }
    }

}

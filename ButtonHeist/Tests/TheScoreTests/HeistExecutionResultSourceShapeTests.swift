import ButtonHeistTestSupport
import Foundation
import Testing

@Suite struct HeistExecutionResultSourceShapeTests {
    private let repository = SourceShapeRepository(filePath: #filePath)

    @Test func `step receipt construction uses typed outcomes instead of optional status bags`() throws {
        let source = try repository.requiredFile(relativePath: "ButtonHeist/Sources/TheScore/HeistExecutionResult.swift")
        let stepType = try source.requiredBlock(
            .structure("HeistExecutionStepResult"),
            message:
            "HeistExecutionStepResult should remain the canonical receipt node type"
        )
        let failedOutcome = try source.requiredBlock(
            .structure("HeistExecutionStepFailedOutcome"),
            message:
            "Failed receipt nodes should use a named failure outcome"
        )
        let childAbortedOutcome = try source.requiredBlock(
            .structure("HeistExecutionStepChildAbortedOutcome"),
            message:
            "Child-aborted receipt nodes should use a named outcome"
        )
        let failedFactory = try #require(
            try stepType.firstBlock(matching: #"\bpublic\s+static\s+func\s+failed\b"#),
            "HeistExecutionStepResult should expose a typed failed factory"
        )
        let packageInitializerSignatures = try stepType.matches(of: #"\bpackage\s+init\s*\([^)]*\)"#)

        #expect(try stepType.containsMatch(#"\bpublic\s+static\s+func\s+passed\s*\("#))
        #expect(try stepType.containsMatch(#"\bpublic\s+static\s+func\s+failed\s*\("#))
        #expect(try stepType.containsMatch(#"\bpublic\s+static\s+func\s+childAborted\s*\("#))
        #expect(try stepType.containsMatch(#"\bpublic\s+static\s+func\s+skipped\s*\("#))
        #expect(try stepType.containsMatch(#"\bpackage\s+init\s*\([^)]*\boutcome\s*:\s*HeistExecutionStepOutcome\b"#))
        #expect(
            !packageInitializerSignatures.contains { $0.contains("status: HeistExecutionStepStatus") },
            "Production receipt construction should not expose a status/evidence/failure optional bag initializer."
        )
        #expect(
            !stepType.contents.contains("inferredFailure"),
            "Production receipt construction should require explicit typed failure payloads."
        )
        #expect(
            try !failedFactory.containsMatch(#"\bfailure\s*:\s*HeistFailureDetail[?]"#),
            "Failed receipt factory should require a concrete failure."
        )
        #expect(
            try !failedFactory.containsMatch(#"\babortedAtChildPath\s*:"#),
            "Child-abort receipt state should be constructed through childAborted, not failed."
        )
        #expect(!failedOutcome.contents.contains("abortedAtChildPath"))
        #expect(childAbortedOutcome.contents.contains("let evidence: HeistStepEvidence"))
        #expect(childAbortedOutcome.contents.contains("let abortedAtChildPath: String"))
    }

    @Test func `action warning dispatch evidence requires a concrete command`() throws {
        let source = try repository.requiredFile(relativePath: "ButtonHeist/Sources/TheScore/HeistExecutionResult.swift")
        let actionEvidence = try source.requiredBlock(
            .structure("HeistActionEvidence"),
            message:
            "HeistActionEvidence should remain the canonical action evidence type"
        )

        let commandfulDispatchSignature = [
            #"\bpublic\s+static\s+func\s+dispatch\s*\("#,
            #"\s*command\s*:\s*HeistActionCommand,\s*"#,
            #"dispatchResult\s*:\s*ActionResult,\s*"#,
            #"warning\s*:\s*HeistActionWarning[?]\s*=\s*nil\s*\)"#
        ].joined()
        #expect(try actionEvidence.containsMatch(
            commandfulDispatchSignature
        ))
        #expect(try actionEvidence.containsMatch(
            #"\bpublic\s+static\s+func\s+dispatch\s*\(\s*dispatchResult\s*:\s*ActionResult\s*\)"#
        ))
        #expect(try !actionEvidence.containsMatch(
            #"\bpublic\s+static\s+func\s+dispatch\s*\(\s*command\s*:\s*HeistActionCommand[?]"#
        ))
        #expect(try !actionEvidence.containsMatch(
            #"\bcase\s+dispatch\s*\(\s*command\s*:\s*HeistActionCommand[?],\s*dispatchResult\s*:\s*ActionResult,\s*warning\s*:\s*HeistActionWarning[?]\s*\)"#
        ))
        #expect(try actionEvidence.containsMatch(#"\bcase\s+dispatch\s*\(\s*Dispatch\s*\)"#))
        #expect(try !actionEvidence.containsMatch(
            #"\bprecondition\s*\(\s*command\s*!=\s*nil[\s\S]*warning\s*==\s*nil"#
        ))
    }

    @Test func `action evidence exposes typed result meanings`() throws {
        let source = try repository.requiredFile(relativePath: "ButtonHeist/Sources/TheScore/HeistExecutionResult.swift")
        let actionEvidence = try source.requiredBlock(
            .structure("HeistActionEvidence"),
            message:
            "HeistActionEvidence should own the meaning of dispatch, expectation, reported, and trace results"
        )
        let resultEvidence = try actionEvidence.requiredBlock(
            .enumeration("ResultEvidence"),
            message:
            "Action evidence consumers should use one typed result evidence model"
        )
        let expectationEvidence = try actionEvidence.requiredBlock(
            .structure("ExpectationResultEvidence"),
            message:
            "Expectation action evidence should structurally carry both action dispatch and expectation results"
        )

        #expect(try resultEvidence.containsMatch(#"\bvar\s+dispatchResult\s*:\s*ActionResult[?]"#))
        #expect(try resultEvidence.containsMatch(#"\bvar\s+expectationResult\s*:\s*ActionResult[?]"#))
        #expect(try resultEvidence.containsMatch(#"\bvar\s+reportedResult\s*:\s*ActionResult[?]"#))
        #expect(try resultEvidence.containsMatch(#"\bvar\s+traceResult\s*:\s*ActionResult[?]"#))
        #expect(try expectationEvidence.containsMatch(#"\blet\s+dispatchResult\s*:\s*ActionResult\b"#))
        #expect(try expectationEvidence.containsMatch(#"\blet\s+expectationResult\s*:\s*ActionResult\b"#))
        #expect(try !expectationEvidence.containsMatch(#"\blet\s+dispatchResult\s*:\s*ActionResult[?]"#))
        #expect(try !expectationEvidence.containsMatch(#"\blet\s+expectationResult\s*:\s*ActionResult[?]"#))
    }

    @Test func `report summary actions and warnings reduce one receipt event stream`() throws {
        let source = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheScore/HeistExecutionResult+Report.swift"
        )
        try source.requireDeclaration(
            .type("HeistExecutionEvidenceEvent", conformingTo: ["Sendable", "Equatable"]),
            message:
            "Report projection facts should be reduced from one typed receipt event stream"
        )

        let rollup = try source.requiredBlock(
            .structure("HeistExecutionEvidenceRollup"),
            message:
            "HeistExecutionEvidenceRollup should be the single report reduction boundary"
        )
        let summary = try source.requiredBlock(.structure("HeistExecutionEvidenceSummary"))
        let actions = try source.requiredBlock(.structure("HeistExecutionActionEvidenceRollup"))
        let warnings = try source.requiredBlock(.structure("HeistExecutionWarningEvidenceRollup"))

        #expect(
            try source.containsMatch(#"\b(struct|enum)\s+HeistExecutionEvidence(EventBuilder|Event)\b"#),
            "Report facts should name the event-stream reducer/accumulator that owns summary, action, and warning state."
        )
        #expect(
            try source.containsMatch(#"\bevents\s*\([^)]*rootNodes\s*:\s*\[HeistExecutionEvidenceNode\]"#),
            "Report summary/actions/warnings should be advanced from HeistExecutionEvidenceEvent values."
        )
        #expect(
            try rollup.containsMatch(#"\bevents\s*:\s*\[HeistExecutionEvidenceEvent\]"#),
            "HeistExecutionEvidenceRollup should materialize the single report event stream."
        )
        #expect(
            try !rollup.containsMatch(#"\bHeistExecution(Action|Warning)EvidenceRollup\s*\(\s*nodes\s*:"#),
            "Action and warning rollups should not independently rescan raw receipt nodes."
        )

        for entry in [
            ("summary", summary),
            ("actions", actions),
            ("warnings", warnings),
        ] {
            let rawReceiptNodeScans = try entry.1.lines(
                matching: #"\b(rollup[.])?nodes\s*[.](compactMap|count|lazy)|\bstep[.]children\b"#
            )
            #expect(
                rawReceiptNodeScans.isEmpty,
                """
                Report \(entry.0) should be derived from the report event stream, \
                not by compactMap/count scans over raw receipt nodes:
                \(rawReceiptNodeScans.joined(separator: "\n"))
                """
            )
            #expect(
                try entry.1.containsMatch(#"\bHeistExecutionEvidence(Event|EventBuilder)\b|\bevents\b"#),
                "Report \(entry.0) should consume the shared report event stream."
            )
        }
    }
}

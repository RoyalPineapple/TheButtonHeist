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
            #"actionResult\s*:\s*ActionResult,\s*"#,
            #"warning\s*:\s*HeistActionWarning[?]\s*=\s*nil\s*\)"#
        ].joined()
        #expect(try actionEvidence.containsMatch(
            commandfulDispatchSignature
        ))
        #expect(try actionEvidence.containsMatch(
            #"\bpublic\s+static\s+func\s+dispatch\s*\(\s*actionResult\s*:\s*ActionResult\s*\)"#
        ))
        #expect(try !actionEvidence.containsMatch(
            #"\bpublic\s+static\s+func\s+dispatch\s*\(\s*command\s*:\s*HeistActionCommand[?]"#
        ))
        #expect(try !actionEvidence.containsMatch(
            #"\bcase\s+dispatch\s*\(\s*command\s*:\s*HeistActionCommand[?],\s*actionResult\s*:\s*ActionResult,\s*warning\s*:\s*HeistActionWarning[?]\s*\)"#
        ))
        #expect(try actionEvidence.containsMatch(#"\bcase\s+dispatch\s*\(\s*Dispatch\s*\)"#))
        #expect(try !actionEvidence.containsMatch(
            #"\bprecondition\s*\(\s*command\s*!=\s*nil[\s\S]*warning\s*==\s*nil"#
        ))
    }
}

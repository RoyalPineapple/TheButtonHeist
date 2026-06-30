import ButtonHeistTestSupport
import Testing

@Suite struct RepeatUntilSourceShapeTests {
    private let repository = SourceShapeRepository(filePath: #filePath)

    @Test func `repeat until runtime uses typed reducer state instead of optional progress bags`() throws {
        let source = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistRepeatUntilExecution.swift"
        )

        #expect(!source.contents.contains("RepeatUntilProgress"))
        #expect(!source.contents.contains("RepeatUntilPostBodyResult"))
        #expect(!source.contents.contains("RepeatUntilWaitProgress"))
        #expect(!source.contents.contains("RepeatUntilReceiptOutcome"))
        #expect(!source.contents.contains("applyPostBody"))
        #expect(!source.contents.contains("lastWaitReceipt: HeistWaitReceipt?"))
        #expect(!source.contents.contains("postBody.lastObservedSummary ??"))
        #expect(!source.contents.contains("lastObservedSummary ?? lastObservedSummary"))

        #expect(source.contents.contains("case awaitingInitial"))
        #expect(source.contents.contains("case running(RepeatUntilRunningState)"))
        #expect(source.contents.contains("case terminal(RepeatUntilTerminal)"))
        #expect(source.contents.contains("static func reduce(_ state: RepeatUntilLoopState, event: RepeatUntilLoopEvent)"))
        #expect(source.contents.contains("let sequence: SettledObservationSequence"))
        #expect(source.contents.contains("case predicateMet(check: RepeatUntilCheck"))
        #expect(source.contents.contains("case timeoutElseFailed("))
    }
}

import ButtonHeistTestSupport
import Foundation
import Testing

@Suite struct ActionResultPayloadSourceShapeTests {
    private let repository = SourceShapeRepository(filePath: #filePath)

    @Test func `public result factories do not accept raw result payload bags`() throws {
        let source = try repository.requiredFile(relativePath: "ButtonHeist/Sources/TheScore/ActionResultPayloads.swift")
        let publicFactorySignatures = try source.matches(
            of: #"\bpublic\s+static\s+func\s+(success|failure)\s*\([\s\S]*?\)\s*->\s*ActionResult\s*\{"#
        )
        let rawPayloadFactories = publicFactorySignatures.filter {
            $0.range(of: #"payload\s*:\s*ResultPayload[?]"#, options: .regularExpression) != nil
        }
        let looseOutcomeFactories = publicFactorySignatures.filter {
            $0.range(
                of: #"success\s*:\s*Bool[\s\S]*errorKind\s*:\s*ErrorKind[?]"#,
                options: .regularExpression
            ) != nil
        }

        #expect(
            rawPayloadFactories.isEmpty,
            "Public ActionResult factories should take ActionResultPayload for payload-carrying results."
        )
        #expect(
            looseOutcomeFactories.isEmpty,
            "Public ActionResult factories should expose typed success/failure paths, not success Bool plus optional errorKind bags."
        )
        #expect(
            try source.containsMatch(#"\bpublic\s+static\s+func\s+success\s*\(\s*payload\s*:\s*ActionResultPayload\b"#)
        )
        #expect(
            try source.containsMatch(#"\bpublic\s+static\s+func\s+failure\s*\(\s*payload\s*:\s*ActionResultPayload\b"#)
        )
    }

    @Test func `package result construction uses typed outcomes and derives method from typed payload`() throws {
        let source = try repository.requiredFile(relativePath: "ButtonHeist/Sources/TheScore/ActionResultPayloads.swift")
        let packageInitializers = try source.matches(of: #"\bpackage\s+init\s*\([\s\S]*?\)\s*\{"#)

        #expect(
            !packageInitializers.contains(where: {
                $0.range(of: #"success\s*:\s*Bool[\s\S]*errorKind\s*:\s*ErrorKind[?]"#, options: .regularExpression) != nil
            }),
            "Package ActionResult construction should not accept success Bool plus optional errorKind bags."
        )
        #expect(
            !packageInitializers.contains(where: {
                $0.range(of: #"payload\s*:\s*ResultPayload[?]"#, options: .regularExpression) != nil
            }),
            "Package ActionResult construction should not accept raw ResultPayload?."
        )
        #expect(
            !packageInitializers.contains(where: {
                $0.range(of: #"method\s*:\s*ActionMethod[\s\S]*payload\s*:\s*ActionResultPayload"#, options: .regularExpression) != nil
            }),
            "Payload-bearing package ActionResult construction should derive method from ActionResultPayload."
        )
        #expect(try source.containsMatch(#"\bpackage\s+init\s*\(\s*outcome\s*:\s*Outcome,\s*method\s*:\s*ActionMethod\b"#))
        #expect(try source.containsMatch(#"\bpackage\s+init\s*\(\s*outcome\s*:\s*Outcome,\s*payload\s*:\s*ActionResultPayload\b"#))
        #expect(try source.containsMatch(#"\bprivate\s+init[?]\s*\(\s*decodedSuccess\s+success\s*:\s*Bool,\s*errorKind\s*:\s*ErrorKind[?]\s*\)"#))
    }

    @Test func `runtime result builder does not accept raw result payload bags or store a method`() throws {
        let builder = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/ActionResultBuilder.swift"
        )
        let builderFactorySignatures = try builder.matches(
            of: #"\bfunc\s+(success|failure)\s*\([\s\S]*?\)\s*->\s*ActionResult\s*\{"#
        )
        let rawPayloadFactories = builderFactorySignatures.filter {
            $0.range(of: #"payload\s*:\s*ResultPayload[?]"#, options: .regularExpression) != nil
        }

        #expect(
            rawPayloadFactories.isEmpty,
            "ActionResultBuilder should traffic in method-bound ActionResultPayload values."
        )
        #expect(
            try !builder.containsMatch(#"\blet\s+method\s*:\s*ActionMethod\b|\bvar\s+method\s*:\s*ActionMethod\b"#),
            "ActionResultBuilder should not store a method that can be mismatched with a payload."
        )
        #expect(
            try !builder.containsMatch(#"\bprecondition\s*\("#),
            "ActionResultBuilder should not need runtime guards for method/payload mismatch."
        )
        #expect(
            try !builder.containsMatch(#"\bfunc\s+success\s*\(\s*payload\s*:\s*ActionResultPayload[?]\s*\)"#)
        )
        #expect(
            try !builder.containsMatch(#"\bfunc\s+failure\s*\([^)]*payload\s*:\s*ActionResultPayload[?]\s*\)"#)
        )
        #expect(try builder.containsMatch(#"\bfunc\s+success\s*\(\s*payload\s*:\s*ActionResultPayload\s*\)"#))
        #expect(try builder.containsMatch(#"\bfunc\s+failure\s*\([^)]*payload\s*:\s*ActionResultPayload\s*\)"#))
        #expect(try builder.containsMatch(#"\bfunc\s+success\s*\(\s*method\s*:\s*ActionMethod\s*\)"#))
        #expect(try builder.containsMatch(#"\bfunc\s+failure\s*\(\s*method\s*:\s*ActionMethod,\s*errorKind\s*:\s*ErrorKind"#))
    }

    @Test func `runtime payload producers construct method bound payloads`() throws {
        let textInput = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/Actions+TextInputActions.swift"
        )
        let rotor = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/Actions+RotorActions.swift"
        )
        let screenCapture = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+ScreenCapture.swift"
        )
        let heistExecution = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecution.swift"
        )
        let safecracker = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+InteractionResult.swift"
        )
        let postAction = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/PostActionObservation.swift"
        )

        for source in [textInput, rotor, screenCapture, heistExecution, safecracker, postAction] {
            #expect(
                try !source.containsMatch(#"\bResultPayload[.](value|screenshot|rotor|heistExecution)\b"#),
                "\(source.relativePath) should use ActionResultPayload factories in result construction."
            )
            #expect(
                try !source.containsMatch(#"\bpayload\s*:\s*ResultPayload[?]"#),
                "\(source.relativePath) should not reintroduce raw ResultPayload? plumbing."
            )
        }

        #expect(try textInput.containsMatch(#"[.]setPasteboard\s*\("#))
        #expect(try textInput.containsMatch(#"[.]getPasteboard\s*\("#))
        #expect(try textInput.containsMatch(#"[.]typeText\s*\("#))
        #expect(try rotor.containsMatch(#"[.]rotor\s*\("#))
        #expect(try screenCapture.containsMatch(#"[.]screenshot\s*\("#))
        #expect(try heistExecution.containsMatch(#"[.]heistExecution\s*\("#))
    }

    @Test func `post action payload resolution is a single enum not parallel optionals`() throws {
        let postAction = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/PostActionObservation.swift"
        )
        let success = try #require(
            try postAction.firstBlock(matching: #"\bstruct\s+ActionOutcomeSuccess\b"#)
        )
        let payload = try #require(
            try postAction.firstBlock(matching: #"\benum\s+ActionOutcomePayload\b"#)
        )

        #expect(success.contents.contains("let payload: ActionOutcomePayload"))
        #expect(!success.contents.contains("afterStatePayload"))
        #expect(!success.contents.contains("let payload: ActionResultPayload?"))
        #expect(payload.contents.contains("case none"))
        #expect(payload.contents.contains("case immediate("))
        #expect(payload.contents.contains("case afterState("))
        #expect(!payload.contents.contains("afterStateWithFallback"))
        #expect(!payload.contents.contains("init("))
    }
}

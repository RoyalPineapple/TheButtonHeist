import Foundation
import Testing
@testable import ThePlans

@Suite(.serialized)
struct HeistCompilerTests {
    @Test
    func `known build diagnostic codes preserve raw output`() {
        let representativeCodes: [(HeistKnownBuildDiagnosticCode, String)] = [
            (.dslInvalidActionExpectation, "heist.dsl.invalid_action_expectation"),
            (.sourceInvalidSyntax, "heist.source.invalid_syntax"),
            (.planRuntimeSafety, "heist.plan.runtime_safety"),
            (.swiftCompilationCompileFailed, "heist.swift_compilation.compile_failed"),
            (.directoryNoSources, "heist.directory.no_sources"),
            (.catalogDuplicateCapability, "heist.catalog.duplicate_capability"),
            (.planningRawJSONIRFields, "heist.planning.raw_json_ir_fields"),
        ]

        for (code, rawValue) in representativeCodes {
            #expect(HeistBuildDiagnosticCode(code).rawValue == rawValue)
            #expect(HeistBuildDiagnostic(code: code, phase: .planning, message: "test").code.rawValue == rawValue)
        }
    }

    @Test
    func `compileFile compiles a simple named HeistPlan Swift source`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "Named.swift",
            """
            import ThePlans

            func heist() throws -> HeistPlan {
                try HeistPlan("NamedPlan") {
                    Warn("ok")
                }
            }
            """
        )

        let (plan, diagnostics) = try await requireSuccess(HeistCompiler().compileFile(source))

        #expect(diagnostics.isEmpty)
        #expect(plan.name == "NamedPlan")
        #expect(plan.body == [.warn(WarnStep(message: "ok"))])
    }

    @Test
    func `compileFile compiles default heist value source`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "Value.swift",
            """
            import ThePlans

            let heist = try HeistPlan("ValuePlan") {
                Warn("ok")
            }
            """
        )

        let (plan, _) = try await requireSuccess(HeistCompiler().compileFile(source))

        #expect(plan.name == "ValuePlan")
        #expect(plan.body == [.warn(WarnStep(message: "ok"))])
    }

    @Test
    func `compileFile rejects invalid Swift source with bounded diagnostics`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "Broken.swift",
            """
            import ThePlans

            let heist =
            """
        )

        let diagnostics = try await requireFailure(HeistCompiler().compileFile(source))
        let diagnostic = try #require(diagnostics.first)

        #expect(diagnostic.code.rawValue == "heist.swift_compilation.compile_failed")
        #expect(diagnostic.kind == .error)
        #expect(diagnostic.phase == .swiftCompilation)
        #expect(diagnostic.sourceSpan?.sourceName.hasSuffix("Broken.swift") == true)
        #expect(diagnostic.renderedMessage.count < 2_500)
    }

    @Test
    func `compileFile rejects compiler output that is not valid heist JSON`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "BadOutput.swift",
            """
            import Foundation
            import ThePlans

            FileHandle.standardOutput.write(Data("not-json".utf8))

            let heist = try HeistPlan("BadOutput") {
                Warn("ok")
            }
            """
        )

        let diagnostics = try await requireFailure(HeistCompiler().compileFile(source))
        let diagnostic = try #require(diagnostics.first)

        #expect(diagnostic.code.rawValue == "heist.swift_compilation.invalid_output")
        #expect(diagnostic.phase == .swiftCompilation)
        #expect(diagnostic.message.contains("valid HeistPlan JSON"))
        #expect(diagnostic.renderedMessage.count < 2_500)
    }

    @Test
    func `compileFile returns a runtime validated HeistPlan`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "Validated.swift",
            """
            import ThePlans

            let heist = try HeistPlan("Validated") {
                Warn("ok")
            }
            """
        )

        let (plan, _) = try await requireSuccess(HeistCompiler().compileFile(source))

        #expect(plan.lint(.strictTest).isEmpty)
        #expect(try JSONDecoder().decode(HeistPlan.self, from: plan.canonicalHeistJSONData()) == plan)
    }

    @Test
    func `compileFile allows Swift wrapper outside selected heist`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "Wrapped.swift",
            """
            import ThePlans

            enum StoreFlows {
                static func checkout() throws -> HeistPlan {
                    try HeistPlan("Checkout") {
                        Warn("ok")
                    }
                }
            }

            let heist = try StoreFlows.checkout()
            """
        )

        let (plan, diagnostics) = try await requireSuccess(HeistCompiler().compileFile(source))

        #expect(diagnostics.isEmpty)
        #expect(plan.name == "Checkout")
        #expect(plan.body == [.warn(WarnStep(message: "ok"))])
    }

    @Test
    func `compileFile ignores Swift wrapper strings that mention HeistPlan`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "WrapperStrings.swift",
            #"""
            import ThePlans

            let template = """
            HeistPlan {
                let x = 1
            }
            """

            let rawTemplate = #"HeistPlan { if true { Warn("not real DSL") } }"#

            let heist = try HeistPlan("WrapperStrings") {
                Warn("ok")
            }
            """#
        )

        let (plan, diagnostics) = try await requireSuccess(HeistCompiler().compileFile(source))

        #expect(diagnostics.isEmpty)
        #expect(plan.name == "WrapperStrings")
        #expect(plan.body == [.warn(WarnStep(message: "ok"))])
    }

    @Test
    func `compileFile ignores Swift wrapper comments and return types that mention HeistPlan`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "WrapperComments.swift",
            """
            import ThePlans

            /*
                /*
                    inner block
                */
                HeistPlan {
                    let x = 1
                }
            */

            func makeHeist() throws -> /* wrapped return type */ HeistPlan {
                try HeistPlan("WrapperComments") {
                    Warn("ok")
                }
            }

            let heist = try makeHeist()
            """
        )

        let (plan, diagnostics) = try await requireSuccess(HeistCompiler().compileFile(source))

        #expect(diagnostics.isEmpty)
        #expect(plan.name == "WrapperComments")
        #expect(plan.body == [.warn(WarnStep(message: "ok"))])
    }

    @Test
    func `compileFile allows trusted Swift frontend helpers to emit a validated plan`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "TrustedFrontend.swift",
            """
            import ThePlans

            func payLabel() -> String { "Pay" }

            let heist = try HeistPlan("TrustedFrontend") {
                Activate(.label(payLabel()))
                    .expect(.change(.screen()))
            }
            """
        )

        let (plan, diagnostics) = try await requireSuccess(HeistCompiler().compileFile(source))

        #expect(diagnostics.isEmpty)
        #expect(plan.name == "TrustedFrontend")
        #expect(plan.body == [
            .action(try ActionStep(
                command: .activate(.predicate(.label("Pay"))),
                expectation: WaitStep(predicate: .change(.screen()), timeout: 1)
            )),
        ])
    }

    @Test
    func `compileFile allows trusted Swift frontend to emit raw validated HeistPlan AST`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "RawBody.swift",
            """
            import ThePlans

            let heist = try HeistPlan(name: "RawBody", body: [
                .warn(WarnStep(message: "raw")),
            ])
            """
        )

        let (plan, diagnostics) = try await requireSuccess(HeistCompiler().compileFile(source))

        #expect(diagnostics.isEmpty)
        #expect(plan.name == "RawBody")
        #expect(plan.body == [.warn(WarnStep(message: "raw"))])
    }

    @Test
    func `swift DSL builder failures surface typed build diagnostics`() throws {
        do {
            _ = try HeistPlan("InvalidExpectation") {
                Activate(.label("Pay"))
                    .expect(.exists(.label("Done")), timeout: 1)
                    .expect(.missing(.label("Error")), timeout: 2)
            }
            Issue.record("Expected invalid expectation composition to fail")
        } catch let error as HeistPlanBuildError {
            let diagnostic = try #require(error.diagnostics.first)

            #expect(error.diagnostics.count == 1)
            #expect(diagnostic.code == .dslInvalidActionExpectation)
            #expect(diagnostic.phase == .dslBuild)
            #expect(diagnostic.path == "activate")
            #expect(diagnostic.message.contains("multiple explicit expectation timeouts"))
            #expect(diagnostic.hint == "Use one explicit timeout for the composed expectation.")
        } catch {
            Issue.record("Expected HeistPlanBuildError, got \(error)")
        }
    }

    @Test
    func `result builders do not accept native Swift control flow in heist body`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "NativeIf.swift",
            """
            import ThePlans

            let shouldPay = true
            let heist = try HeistPlan("NativeIf") {
                if shouldPay {
                    Activate(.label("Pay"))
                }
            }
            """
        )

        let diagnostics = try await requireFailure(HeistCompiler().compileFile(source))
        let text = diagnostics.map(\.description).joined(separator: "\n")

        #expect(text.contains("Failed to compile Swift heist source"))
    }

    @Test
    func `result builders do not accept native Swift control flow in heist definitions`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "NativeIfInDefinition.swift",
            """
            import ThePlans

            let heist = try HeistPlan("NativeIfInDefinition") {
                HeistDef<Void>("Helper") {
                    if Bool.random() {
                        Warn("raw")
                    }
                }

                RunHeist("Helper")
            }
            """
        )

        let diagnostics = try await requireFailure(HeistCompiler().compileFile(source))
        let text = diagnostics.map(\.description).joined(separator: "\n")

        #expect(text.contains("Failed to compile Swift heist source"))
    }

    @Test
    func `conditionals accept only snapshot predicate types`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let validSource = try temp.writeSwiftSource(
            named: "SnapshotConditional.swift",
            """
            import ThePlans

            let heist = try HeistPlan("SnapshotConditional") {
                If(.exists(.label("Ready"))) {
                    Warn("ready")
                }

                If {
                    Case(.missing(.label("Loading"))) {
                        Warn("loaded")
                    }
                }
            }
            """
        )
        let invalidIfSource = try temp.writeSwiftSource(
            named: "TransitionIf.swift",
            """
            import ThePlans

            let heist = try HeistPlan("TransitionIf") {
                If(.updated(.value("Ready"))) {
                    Warn("ready")
                }
            }
            """
        )
        let invalidCaseSource = try temp.writeSwiftSource(
            named: "TransitionCase.swift",
            """
            import ThePlans

            let heist = try HeistPlan("TransitionCase") {
                If {
                    Case(.appeared(.label("Ready"))) {
                        Warn("ready")
                    }
                }
            }
            """
        )

        let (plan, _) = try await requireSuccess(HeistCompiler().compileFile(validSource))
        #expect(plan.body.count == 2)

        let invalidIfDiagnostics = try await requireFailure(HeistCompiler().compileFile(invalidIfSource))
        let invalidIfText = invalidIfDiagnostics.map(\.description).joined(separator: "\n")
        #expect(invalidIfText.contains("type 'StatePredicateExpr' has no member 'updated'"))

        let invalidCaseDiagnostics = try await requireFailure(HeistCompiler().compileFile(invalidCaseSource))
        let invalidCaseText = invalidCaseDiagnostics.map(\.description).joined(separator: "\n")
        #expect(invalidCaseText.contains("type 'StatePredicateExpr' has no member 'appeared'"))
    }

    @Test
    func `predicate composition shape is enforced by Swift types`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let validSource = try temp.writeSwiftSource(
            named: "PredicateComposition.swift",
            """
            import ThePlans

            let heist = try HeistPlan("PredicateComposition") {
                WaitFor(.all(
                    .exists(.label("Receipt")),
                    .missing(.label("Loading"))
                ))

                WaitFor(.change(.all(
                    .screenChanged(.exists(.label("Receipt"))),
                    .updated(.value("3"))
                )))
            }
            """
        )
        let emptyAllSource = try temp.writeSwiftSource(
            named: "EmptyAll.swift",
            """
            import ThePlans

            let heist = try HeistPlan("EmptyAll") {
                WaitFor(.all())
            }
            """
        )
        let rawEmptyAllSource = try temp.writeSwiftSource(
            named: "RawEmptyAll.swift",
            """
            import ThePlans

            let heist = try HeistPlan("RawEmptyAll") {
                WaitFor(.state(.all([])))
            }
            """
        )
        let nestedAnySource = try temp.writeSwiftSource(
            named: "NestedAny.swift",
            """
            import ThePlans

            let heist = try HeistPlan("NestedAny") {
                WaitFor(.changePredicate(.all(.any)))
            }
            """
        )

        let (plan, _) = try await requireSuccess(HeistCompiler().compileFile(validSource))
        #expect(plan.body.count == 2)

        let emptyAllDiagnostics = try await requireFailure(HeistCompiler().compileFile(emptyAllSource))
        let emptyAllText = emptyAllDiagnostics.map(\.description).joined(separator: "\n")
        #expect(emptyAllText.contains("missing argument"))

        let rawEmptyAllDiagnostics = try await requireFailure(HeistCompiler().compileFile(rawEmptyAllSource))
        let rawEmptyAllText = rawEmptyAllDiagnostics.map(\.description).joined(separator: "\n")
        #expect(rawEmptyAllText.contains("NonEmptyArray<StatePredicateExpr>"))

        let nestedAnyDiagnostics = try await requireFailure(HeistCompiler().compileFile(nestedAnySource))
        let nestedAnyText = nestedAnyDiagnostics.map(\.description).joined(separator: "\n")
        #expect(nestedAnyText.contains("type 'ChangeScopePredicateExpr' has no member 'any'"))
    }

    @Test
    func `compileDirectory compiles multiple Swift files into one catalog`() async throws {
        let temp = try CompilerTemporaryDirectory()
        _ = try temp.writeSwiftSource(named: "Alpha.swift", namedPlan: "Alpha")
        _ = try temp.writeSwiftSource(named: "Beta.swift", namedPlan: "Beta")

        let (catalog, diagnostics) = try await requireSuccess(HeistCompiler().compileDirectory(temp.url))

        #expect(diagnostics.isEmpty)
        #expect(catalog.source == HeistCatalogSource(url: temp.url.standardizedFileURL))
        #expect(catalog.capabilities.map(\.name) == ["Alpha", "Beta"])
    }

    @Test
    func `compileDirectory fails duplicate capability names`() async throws {
        let temp = try CompilerTemporaryDirectory()
        _ = try temp.writeSwiftSource(named: "First.swift", namedPlan: "Duplicate")
        _ = try temp.writeSwiftSource(named: "Second.swift", namedPlan: "Duplicate")

        let diagnostics = try await requireFailure(HeistCompiler().compileDirectory(temp.url))
        let diagnostic = try #require(diagnostics.first)

        #expect(diagnostic.code.rawValue == "heist.catalog.duplicate_capability")
        #expect(diagnostic.phase == .planValidation)
        #expect(diagnostic.sourceSpan?.sourceName.hasSuffix("Second.swift") == true)
    }

    @Test
    func `compileDirectory does not derive names from filenames`() async throws {
        let temp = try CompilerTemporaryDirectory()
        _ = try temp.writeSwiftSource(named: "Filename.swift", namedPlan: "PlanName")

        let (catalog, _) = try await requireSuccess(HeistCompiler().compileDirectory(temp.url))

        #expect(catalog.capabilities.map(\.name) == ["PlanName"])
        #expect(!catalog.capabilities.map { $0.name ?? "" }.contains("Filename"))
    }

    @Test
    func `compileDirectory ignores hidden files`() async throws {
        let temp = try CompilerTemporaryDirectory()
        _ = try temp.writeSwiftSource(named: ".Hidden.swift", "this is not Swift")
        _ = try temp.writeSwiftSource(named: "Visible.swift", namedPlan: "Visible")

        let (catalog, _) = try await requireSuccess(HeistCompiler().compileDirectory(temp.url))

        #expect(catalog.capabilities.map(\.name) == ["Visible"])
    }

    @Test
    func `compileDirectory rejects anonymous capabilities in multi file catalog`() async throws {
        let temp = try CompilerTemporaryDirectory()
        _ = try temp.writeSwiftSource(
            named: "Anonymous.swift",
            """
            import ThePlans

            let heist = try HeistPlan {
                Warn("anonymous")
            }
            """
        )
        _ = try temp.writeSwiftSource(named: "Named.swift", namedPlan: "Named")

        let diagnostics = try await requireFailure(HeistCompiler().compileDirectory(temp.url))

        #expect(diagnostics.map(\.description).joined(separator: "\n").contains("anonymous capability"))
    }

    @Test
    func `swiftPM metadata extraction selects active object files`() throws {
        let temp = try CompilerTemporaryDirectory()
        let objectDirectory = temp.url.appendingPathComponent("ThePlans.build", isDirectory: true)
        try FileManager.default.createDirectory(at: objectDirectory, withIntermediateDirectories: true)

        let activeObject = objectDirectory.appendingPathComponent("Active.swift.o")
        let staleObject = objectDirectory.appendingPathComponent("Stale.swift.o")
        try Data().write(to: activeObject)
        try Data().write(to: staleObject)

        let descriptionJSON = """
        {
          "swiftCommands": {
            "broken": [ "ignored" ],
            "other": {
              "moduleName": "Other",
              "objects": [ \(try jsonStringLiteral(staleObject.path)) ]
            },
            "theplans": {
              "moduleName": "ThePlans",
              "objects": [
                \(try jsonStringLiteral("/missing/build/Active.swift.o")),
                \(try jsonStringLiteral("/missing/build/Generated.swift"))
              ]
            }
          }
        }
        """
        try descriptionJSON.write(to: temp.url.appendingPathComponent("description.json"), atomically: true, encoding: .utf8)

        let objectFiles = try #require(try SwiftPMBuildDescription.activeSwiftObjectFiles(
            in: temp.url,
            moduleName: "ThePlans"
        ))
        #expect(objectFiles == [activeObject])
    }

    @Test
    func `source compiler remains behind ThePlans boundary`() throws {
        let root = try repositoryRoot()
        let files = try productionSwiftFilesOutsideThePlans(in: root)

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("HeistPlanSourceCompiler()"), "\(file.path) directly constructs HeistPlanSourceCompiler")
            #expect(!source.contains("HeistSwiftFileCompiler"), "\(file.path) references HeistSwiftFileCompiler")
            #expect(!source.contains("swiftc"), "\(file.path) invokes swiftc")
            #expect(!source.contains("decodeValidatedHeistJSON"), "\(file.path) decodes compiler stdout")
        }
    }

    @Test
    func `tooling-only helpers and report facts are package scoped`() throws {
        let root = try repositoryRoot()
        let sourceCompiler = try String(
            contentsOf: root.appendingPathComponent("ButtonHeist/Sources/ThePlans/HeistPlanSourceCompiler.swift"),
            encoding: .utf8
        )
        #expect(sourceCompiler.contains("package struct HeistPlanSourceCompiler: Sendable"))
        #expect(sourceCompiler.contains("package struct HeistPlanSourceCompilerError"))

        for forbidden in [
            "public struct HeistPlanSourceCompiler",
            "public struct HeistPlanSourceCompilerError",
        ] {
            #expect(!sourceCompiler.contains(forbidden), "Source compiler helper leaked public API: \(forbidden)")
        }

        let runtimeKnobs = try String(
            contentsOf: root.appendingPathComponent("ButtonHeist/Sources/TheScore/ButtonHeistRuntimeKnobs.swift"),
            encoding: .utf8
        )
        for required in [
            "package struct RuntimeKnobEnvironmentKey",
            "package struct RuntimeKnobEnvironment",
            "package enum RuntimeKnobEnvironmentBridge",
            "package struct ButtonHeistRuntimeKnobs",
        ] {
            #expect(runtimeKnobs.contains(required), "Runtime knob helper is not package scoped: \(required)")
        }

        for forbidden in [
            "public struct RuntimeKnobEnvironmentKey",
            "public struct RuntimeKnobEnvironment",
            "public enum RuntimeKnobEnvironmentBridge",
            "public struct ButtonHeistRuntimeKnobs",
        ] {
            #expect(!runtimeKnobs.contains(forbidden), "Runtime knob helper leaked public API: \(forbidden)")
        }

        let reportFacts = try String(
            contentsOf: root.appendingPathComponent("ButtonHeist/Sources/TheScore/HeistExecutionResult+Report.swift"),
            encoding: .utf8
        )
        for required in [
            "package struct HeistExecutionReportSummaryFacts",
            "package struct HeistExecutionStepReportFacts",
            "package extension HeistExecutionStepResult",
        ] {
            #expect(reportFacts.contains(required), "Report facts helper is not package scoped: \(required)")
        }

        for forbidden in [
            "@_spi(ButtonHeistInternals) public struct HeistExecutionReportSummaryFacts",
            "@_spi(ButtonHeistInternals) public struct HeistExecutionStepReportFacts",
            "public struct HeistExecutionReportSummaryFacts",
            "public struct HeistExecutionStepReportFacts",
            "HeistExecutionReportSummaryDTO",
            "HeistExecutionStepReportDTO",
            "reportDTO",
        ] {
            #expect(!reportFacts.contains(forbidden), "Report facts helper leaked public, SPI, or DTO API: \(forbidden)")
        }
    }

    @Test
    func `heist-plan stdout writes are routed through local output sink`() throws {
        let root = try repositoryRoot()
        let files = try swiftFiles(in: root.appendingPathComponent("ButtonHeist/Sources/HeistPlanTool", isDirectory: true))
        let forbiddenSnippets = [
            "print(",
            "FileHandle.standardOutput.write",
        ]
        var foundOutputSink = false

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            foundOutputSink = foundOutputSink || source.contains("enum HeistPlanToolOutput")
            for (lineNumber, line) in sourceLinesOutsideHeistPlanToolOutputSink(source) {
                for snippet in forbiddenSnippets {
                    #expect(
                        line.range(of: snippet) == nil,
                        "\(file.path):\(lineNumber) contains \(snippet) outside HeistPlanToolOutput"
                    )
                }
            }
        }

        #expect(foundOutputSink, "HeistPlanToolOutput sink is missing")
    }

    @Test
    func `untrusted heist planning representations stay behind ThePlans boundary`() throws {
        let root = try repositoryRoot()
        let files = try productionSwiftFilesOutsideThePlans(in: root)
        let forbiddenSnippets = [
            "@_spi(ButtonHeistInternals) import ThePlans",
            "HeistPlanAdmissionCandidate",
            ".validatedForRuntimeSafety(",
            "HeistPlanRuntimeSafetyError",
            "HeistPlanJSONCodec",
            "HeistArtifactCodec.read",
            "HeistArtifactCodec.decodePlanJSON",
            "JSONDecoder().decode(HeistPlan.self",
            "JSONDecoder().decode(HeistPlanAdmissionCandidate.self",
        ]

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for snippet in forbiddenSnippets {
                #expect(!source.contains(snippet), "\(file.path) contains \(snippet)")
            }
        }
    }

    @Test
    func `heist DSL build diagnostics stay on the typed diagnostic pipeline`() throws {
        let root = try repositoryRoot()
        let checkedFiles = [
            "ButtonHeist/Sources/ThePlans/ActionStep.swift",
            "ButtonHeist/Sources/ThePlans/HeistActions.swift",
            "ButtonHeist/Sources/ThePlans/HeistContent.swift",
            "ButtonHeist/Sources/ThePlans/HeistControl.swift",
            "ButtonHeist/Sources/ThePlans/HeistPlanSourceActionParser.swift",
            "ButtonHeist/Sources/ThePlans/HeistPlanSourceControlFlowParser.swift",
        ]
        let forbiddenPatterns = [
            #"\bheistBuildDiagnostics\s*:\s*\[String\]"#,
            #"\bvar\s+heistBuildDiagnostics\s*:\s*\[String\]"#,
            #"\blet\s+heistBuildDiagnostics\s*:\s*\[String\]"#,
            #"\bHeistDefinitionBuildResult\b"#,
            #"\bexpectationValidationFailure\b"#,
            #"\bfailure\s*:\s*String\?"#,
            #"\bcase\s+failure\s*\(\s*String\s*\)"#,
        ]

        for path in checkedFiles {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            for pattern in forbiddenPatterns {
                #expect(
                    source.range(of: pattern, options: .regularExpression) == nil,
                    "\(path) contains retired loose build diagnostic shape \(pattern)"
                )
            }
        }
    }

    @Test
    func `wire message coding uses concrete payload wrappers`() throws {
        let root = try repositoryRoot()
        let wireCodingFiles = [
            "ButtonHeist/Sources/TheScore/ClientMessages+WireCoding.swift",
            "ButtonHeist/Sources/TheScore/ServerMessages+WireCoding.swift",
        ]
        let erasedEncodable = "any " + "Encodable"

        for relativePath in wireCodingFiles {
            let file = root.appendingPathComponent(relativePath)
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains(erasedEncodable), "\(relativePath) uses erased Encodable payloads")
            #expect(source.contains("WirePayload"), "\(relativePath) is missing the concrete wire payload wrapper")
        }
    }

    @Test
    func `raw logger construction stays within ButtonHeistLog factory`() throws {
        let root = try repositoryRoot()
        let scorePath = "ButtonHeist/Sources/TheScore/"
        let loggerFactoryLine = sourceMatch(
            path: scorePath + "ButtonHeistLog.swift",
            line: "Logger(subsystem: channel.subsystem.rawValue, category: channel.category)"
        )
        let allowedLoggerLines = Set([loggerFactoryLine])

        let observed = try sourceMatches(
            in: productionSwiftFiles(in: root),
            root: root,
            pattern: #"\bLogger\s*\("#
        )
        let unexpected = observed.subtracting(allowedLoggerLines)

        #expect(unexpected.isEmpty, "Unexpected raw Logger constructions:\n\(unexpected.sorted().joined(separator: "\n"))")
        #expect(observed.contains(loggerFactoryLine))
    }

    @Test
    func `retired names stay retired or explicitly scoped`() throws {
        let root = try repositoryRoot()
        let files = try sourceAndTestSwiftFiles(in: root)
        let compatibilityChecks: [(label: String, pattern: String, allowedPaths: Set<String>)] = [
            (
                "public input adapter",
                "\\b" + "Public" + "Adapter(InputLimits|InputError)\\b",
                []
            ),
            (
                "public action failure projection",
                "\\b" + "Public" + "(ActionFailureProjection|Failure|FailureDetail|FailureDetails)\\b",
                []
            ),
            (
                "action kind initializer surface",
                "\\b" + "action" + "Kind\\b",
                []
            ),
            (
                "compilation",
                "\\b" + "Heist" + "Compilation(SourceLocation|Diagnostic|Result)\\b",
                [
                    "ButtonHeist/Sources/ThePlans/HeistCompiler.swift",
                    "ButtonHeist/Sources/ThePlans/HeistPlanSourceDiagnostics.swift",
                    "ButtonHeist/Sources/HeistPlanTool/main.swift",
                    "ButtonHeistCLI/Sources/Commands/RunHeistCommand.swift",
                    "ButtonHeist/Tests/ThePlansTests/HeistCompilerTests.swift",
                ]
            ),
        ]

        for check in compatibilityChecks {
            let unexpected = try sourceMatchFiles(in: files, root: root, pattern: check.pattern)
                .filter { !check.allowedPaths.contains($0) }
            #expect(
                unexpected.isEmpty,
                "Unexpected \(check.label) names:\n\(unexpected.sorted().joined(separator: "\n"))"
            )
        }
    }

    @Test
    func `property change values stay property typed`() throws {
        let root = try repositoryRoot()
        let file = root.appendingPathComponent("ButtonHeist/Sources/TheScore/TreeChangeModels.swift")
        let source = try String(contentsOf: file, encoding: .utf8)

        #expect(!source.contains("public var old: String?"))
        #expect(!source.contains("public var new: String?"))
        #expect(!source.contains("value(from erasedValue"))
        #expect(!source.contains("ElementPropertyValue.self"))
        #expect(!source.contains("decodeValue("))
        #expect(source.contains("associatedtype Value: Codable, Sendable, Equatable"))
        #expect(source.contains("let old = try container.decodeIfPresent(P.Value.self, forKey: .old)"))
        #expect(source.contains("let new = try container.decodeIfPresent(P.Value.self, forKey: .new)"))

        let evaluatorFile = root.appendingPathComponent("ButtonHeist/Sources/TheScore/AccessibilityPredicate+Evaluation.swift")
        let evaluatorSource = try String(contentsOf: evaluatorFile, encoding: .utf8)
        #expect(!evaluatorSource.contains("matchesPropertyValue"))
        #expect(!evaluatorSource.contains("matchesTraitPropertyValue"))
        #expect(!evaluatorSource.contains("propertyChange.oldValue"))
        #expect(!evaluatorSource.contains("propertyChange.newValue"))

        let erasedPropertyValueMatchers = try sourceMatches(
            in: productionSwiftFiles(in: root),
            root: root,
            pattern: #"func\s+\w+\s*\(\s*_\s+\w+:\s*ElementPropertyValue\?\s*,\s*matches\s+\w+:\s*ElementProperty"#
        )
        #expect(
            erasedPropertyValueMatchers.isEmpty,
            "Unexpected erased property/value matchers:\n\(erasedPropertyValueMatchers.sorted().joined(separator: "\n"))"
        )

        let propertyValueCompatibilitySwitches = try sourceMatches(
            in: productionSwiftFiles(in: root),
            root: root,
            pattern: #"switch\s*\(\s*property\s*,\s*value\s*\)"#
        )
        #expect(
            propertyValueCompatibilitySwitches.isEmpty,
            "Unexpected property/value compatibility switches:\n\(propertyValueCompatibilitySwitches.sorted().joined(separator: "\n"))"
        )
    }

    @Test
    func `action projection method identity stays typed until JSON encoding`() throws {
        let root = try repositoryRoot()
        let projectionFile = root.appendingPathComponent("ButtonHeist/Sources/TheButtonHeist/TheFence/ActionProjection.swift")
        let projectionSource = try String(contentsOf: projectionFile, encoding: .utf8)

        #expect(projectionSource.contains("enum ActionMethodProjection"))
        #expect(projectionSource.range(of: #"\binit\s*\(\s*method\s*:\s*String\b"#, options: .regularExpression) == nil)
        #expect(projectionSource.range(of: #"\bmethod:\s*String\b"#, options: .regularExpression) == nil)
        #expect(!projectionSource.contains("Public" + "ActionFailureProjection"))

        let actionProjectionCallPattern = #"ActionProjection\s*\(\s*method:"#
        for file in try productionSwiftFiles(in: root) {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(
                source.range(of: actionProjectionCallPattern, options: .regularExpression) == nil,
                "Unexpected raw ActionProjection method initializer in \(repositoryRelativePath(file, root: root))"
            )
        }

        let jsonSource = try String(
            contentsOf: root.appendingPathComponent("ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Action.swift"),
            encoding: .utf8
        )
        #expect(jsonSource.contains("self.method = projection.actionMethod.rawValue"))
    }

    @Test
    func `production source avoids tuple return APIs while allowing closure local tuples`() throws {
        let root = try repositoryRoot()
        let modifiers = #"@\w+(?:\([^)]*\))?|public|package|internal|private|fileprivate|static|class|mutating|nonmutating|nonisolated|final|override"#
        let tupleReturnAPIPattern = #"(?m)(?:^\s*(?:(?:"# + modifiers + #")\s+)*"#
            + #"func\s+\w+[^{=;]*?\)\s*(?:async\s+)?(?:(?:throws|rethrows)\s+)?->\s*\((?!\s*@Sendable\b)[^()]*,[^()]*\)\??"#
            + #"|^\s*(?:(?:public|package|internal|private|fileprivate)\s+)*typealias\s+\w+[^=\n]*=[^;\n]*->\s*\((?!\s*@Sendable\b)[^()]*,[^()]*\)\??)"#
        let tupleReturnAPIs = try sourceSnippets(
            in: productionSwiftFiles(in: root),
            root: root,
            pattern: tupleReturnAPIPattern
        )

        #expect(
            tupleReturnAPIs.isEmpty,
            """
            Unexpected production tuple return APIs. Use a named value type for \
            non-local return surfaces; closure-local tuple transforms are allowed:
            \(tupleReturnAPIs.sorted().joined(separator: "\n"))
            """
        )
    }

    @Test
    func `public response serialization stays behind PublicJSONSerializer`() throws {
        let root = try repositoryRoot()
        let responseCallSitePaths = [
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceResponsePresenter.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+JSON.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Response.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Action.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceResponseModels.swift",
        ]
        let responseCallSiteFiles = responseCallSitePaths.map { root.appendingPathComponent($0) }

        let directEncoders = try sourceMatches(
            in: responseCallSiteFiles,
            root: root,
            pattern: #"\bJSONEncoder\s*\("#
        )
        #expect(
            directEncoders.isEmpty,
            "Unexpected public response JSONEncoder bypasses:\n\(directEncoders.sorted().joined(separator: "\n"))"
        )

        let publicResponseEnvelopeUse = try sourceMatchFiles(
            in: try swiftFiles(in: root.appendingPathComponent("ButtonHeist/Sources/TheButtonHeist/TheFence", isDirectory: true)),
            root: root,
            pattern: #"\bPublicResponseEnvelope\b"#
        )
        .filter { $0 != "ButtonHeist/Sources/TheButtonHeist/TheFence/PublicJSONSerializer.swift" }
        #expect(
            publicResponseEnvelopeUse.isEmpty,
            "Unexpected public response envelope bypasses:\n\(publicResponseEnvelopeUse.sorted().joined(separator: "\n"))"
        )
    }

    @Test
    func `public report projections avoid raw dictionary surfaces`() throws {
        let root = try repositoryRoot()
        let projectionSurfacePaths = [
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Response.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Action.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Interface.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Container.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+TreeNode.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Session.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceResponsePresenter.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/ActionProjection.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/DeltaProjection.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/HeistEvidenceProjection.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/HeistReportProjection.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/InterfaceProjection.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/ProjectionProfile.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+Compact.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+Compact+Action.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+Compact+Delta.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+Compact+Heist.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+Compact+Interface.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+JUnitReport.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift",
        ]
        let projectionSurfaceFiles = projectionSurfacePaths.map { root.appendingPathComponent($0) }
        let rawDictionaryPatterns = [
            #"\[String:\s*(HeistValue|Any|any\s+Encodable|Encodable|JSONValue|Value)\]"#,
            #"Dictionary\s*<\s*String\s*,\s*(HeistValue|Any|any\s+Encodable|Encodable|JSONValue|Value)\s*>"#,
        ]

        for pattern in rawDictionaryPatterns {
            let unexpected = try sourceMatches(in: projectionSurfaceFiles, root: root, pattern: pattern)
            #expect(
                unexpected.isEmpty,
                "Unexpected raw projection dictionaries:\n\(unexpected.sorted().joined(separator: "\n"))"
            )
        }
    }

    @Test
    func `projection JSON does not rebuild public interfaces from raw models`() throws {
        let root = try repositoryRoot()
        let productionFiles = try productionSwiftFiles(in: root)
        let allowedPaths: Set<String> = [
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Interface.swift",
        ]
        let unexpected = try sourceMatches(
            in: productionFiles,
            root: root,
            pattern: #"PublicInterface\s*\(\s*interface:"#
        )
        .filter { match in
            guard let path = match.split(separator: ":", maxSplits: 1).first else { return true }
            return !allowedPaths.contains(String(path))
        }

        #expect(
            unexpected.isEmpty,
            "Unexpected raw Interface -> PublicInterface projection call sites:\n\(unexpected.sorted().joined(separator: "\n"))"
        )

        let deltaProjection = try String(
            contentsOf: root.appendingPathComponent("ButtonHeist/Sources/TheButtonHeist/TheFence/DeltaProjection.swift"),
            encoding: .utf8
        )
        #expect(deltaProjection.contains("let interface: InterfaceProjection?"))
        #expect(deltaProjection.contains("struct ScreenshotProjection"))
    }

    @Test
    func `source compiler preserves diagnostic sets through admission boundary`() throws {
        let root = try repositoryRoot()
        let compilerSource = try String(
            contentsOf: root.appendingPathComponent("ButtonHeist/Sources/ThePlans/HeistPlanSourceCompiler.swift"),
            encoding: .utf8
        )

        #expect(compilerSource.contains("func compileResult("))
        #expect(compilerSource.contains("package let diagnostics: [HeistBuildDiagnostic]"))
        #expect(!compilerSource.contains("diagnostics[0]"))
        #expect(!compilerSource.contains("throw HeistPlanSourceCompilerError(diagnostic: diagnostics"))

        let plansFiles = try swiftFiles(in: root.appendingPathComponent("ButtonHeist/Sources/ThePlans", isDirectory: true))
        let removedUncheckedAdmission = try sourceMatches(
            in: plansFiles,
            root: root,
            pattern: #"uncheckedPlanForRuntimeSafetyValidation\s*\("#
        )
        #expect(
            removedUncheckedAdmission.isEmpty,
            "Unexpected unchecked runtime admission bridge:\n\(removedUncheckedAdmission.sorted().joined(separator: "\n"))"
        )

        let allowedDraftPaths: Set<String> = [
            "ButtonHeist/Sources/ThePlans/HeistPlan+RuntimeValidationAdmission.swift",
            "ButtonHeist/Sources/ThePlans/HeistPlan+RuntimeValidationTraversal.swift",
            "ButtonHeist/Sources/ThePlans/HeistPlanSourceControlFlowParser.swift",
        ]
        let unexpectedDraftAdmission = try sourceMatches(
            in: plansFiles,
            root: root,
            pattern: #"runtimeSafetyTraversalDraft(?:Plan|Step)?\b"#
        )
        .filter { match in
            guard let path = match.split(separator: ":", maxSplits: 1).first else { return true }
            return !allowedDraftPaths.contains(String(path))
        }

        #expect(
            unexpectedDraftAdmission.isEmpty,
            "Runtime safety traversal draft escaped admission/parser boundary:\n\(unexpectedDraftAdmission.sorted().joined(separator: "\n"))"
        )
    }

    @Test
    func `fence execution ingress stays routed through operation requests`() throws {
        let root = try repositoryRoot()
        let productionFiles = try productionSwiftFiles(in: root)

        let publicCommandExecution = try sourceMatches(
            in: productionFiles,
            root: root,
            pattern: #"public\s+func\s+execute\s*\(\s*command:"#
        )
        #expect(
            publicCommandExecution.isEmpty,
            "Unexpected public command-plus-arguments execution surface:\n\(publicCommandExecution.sorted().joined(separator: "\n"))"
        )

        let directFenceExecution = try sourceMatches(
            in: productionFiles,
            root: root,
            pattern: #"\.execute\s*\(\s*command:[^)]*arguments:"#
        )
        #expect(
            directFenceExecution.isEmpty,
            "Unexpected direct fence command-plus-arguments call sites:\n\(directFenceExecution.sorted().joined(separator: "\n"))"
        )

        let routingSource = try String(
            contentsOf: root.appendingPathComponent("ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift"),
            encoding: .utf8
        )
        #expect(routingSource.contains("@_spi(ButtonHeistTooling) public struct FenceOperationRequest"))

        let argumentSource = try String(
            contentsOf: root.appendingPathComponent("ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift"),
            encoding: .utf8
        )
        #expect(argumentSource.contains("@_spi(ButtonHeistTooling) public struct CommandArgumentEnvelope"))
    }

    @Test
    func `legacy compatibility config spellings stay allowlisted`() throws {
        let root = try repositoryRoot()
        let files = try productionSwiftFiles(in: root)
        let runtimeKnobSource = "ButtonHeist/Sources/TheScore/ButtonHeistRuntimeKnobs.swift:"
        let allowedLegacyRuntimeKnobAliases: Set<String> = [
            runtimeKnobSource
                + #"package static let postScrollLayoutFrames = RuntimeKnobEnvironmentKey("BH_POST_SCROLL_LAYOUT_FRAMES")"#,
            runtimeKnobSource
                + #"package static let tripwirePulseFramesPerSecond = RuntimeKnobEnvironmentKey("BH_TRIPWIRE_PULSE_HZ")"#,
            runtimeKnobSource
                + #"package static let maxScrollsPerContainer = RuntimeKnobEnvironmentKey("BH_MAX_SCROLLS_PER_CONTAINER")"#,
            runtimeKnobSource
                + #"package static let maxScrollsPerDiscovery = RuntimeKnobEnvironmentKey("BH_MAX_SCROLLS_PER_DISCOVERY")"#,
            runtimeKnobSource
                + #"package static let scrollSubtreeElementBudget = RuntimeKnobEnvironmentKey("BH_SCROLL_SUBTREE_ELEMENT_BUDGET")"#,
            runtimeKnobSource
                + #"package static let visibleElementBudget = RuntimeKnobEnvironmentKey("BH_VISIBLE_ELEMENT_BUDGET")"#,
            runtimeKnobSource
                + #"package static let totalNodeBudget = RuntimeKnobEnvironmentKey("BH_TOTAL_NODE_BUDGET")"#,
        ]
        let legacyRuntimeKnobAliases = try sourceMatches(
            in: files,
            root: root,
            pattern: #""BH_[A-Z0-9_]+""#
        )
        let unexpectedLegacyRuntimeKnobAliases = legacyRuntimeKnobAliases.subtracting(allowedLegacyRuntimeKnobAliases)
        #expect(
            unexpectedLegacyRuntimeKnobAliases.isEmpty,
            "Unexpected legacy runtime knob aliases:\n\(unexpectedLegacyRuntimeKnobAliases.sorted().joined(separator: "\n"))"
        )

        let retiredConfigFieldMatches = try sourceMatches(
            in: files,
            root: root,
            pattern: #""(certFingerprint|certificateFingerprint|tlsFingerprint|tlsCertificateFingerprint|serverFingerprint|serverCertificateFingerprint)""#
        )
        #expect(
            retiredConfigFieldMatches.isEmpty,
            "Unexpected retired config field spellings:\n\(retiredConfigFieldMatches.sorted().joined(separator: "\n"))"
        )
    }

    @Test
    func `known failure codes avoid new raw construction sites`() throws {
        let root = try repositoryRoot()
        let files = try sourceAndTestSwiftFiles(in: root)
        let knownFailurePrefix = #"(request|discovery|setup|connection|transport|auth|session|protocol|tls|client|server|config|formatting|screen)\."#

        let rawConstructorMatches = try sourceSnippets(
            in: files,
            root: root,
            pattern: "\\b(FailureCode|KnownFailureCode)\\s*\\(\\s*(rawValue|boundaryRawValue):\\s*\"" + knownFailurePrefix
        )
        #expect(
            rawConstructorMatches.isEmpty,
            "Unexpected raw known failure constructors:\n\(rawConstructorMatches.sorted().joined(separator: "\n"))"
        )

        let allowedRawLiteralPaths: Set<String> = [
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+FailureDetails.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+FailureTaxonomy.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Action.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Connection.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+JSON.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ScreenHandlers.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheHandoff/HandoffConnectionState.swift",
            "ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceConnectionFailures.swift",
            "ButtonHeist/Tests/ButtonHeistTests/TheFenceHandlerTests.swift",
        ]
        let unexpectedRawLiteralFiles = try sourceMatchFiles(
            in: files,
            root: root,
            pattern: "\\berrorCode:\\s*\"" + knownFailurePrefix
        )
        .filter { !allowedRawLiteralPaths.contains($0) }

        #expect(
            unexpectedRawLiteralFiles.isEmpty,
            "Unexpected raw known failure-code literals:\n\(unexpectedRawLiteralFiles.sorted().joined(separator: "\n"))"
        )

        let allowedRawInitializerPaths: Set<String> = []
        let unexpectedRawInitializerSnippets = try sourceSnippets(
            in: files,
            root: root,
            pattern: "\\b(FailureDetails|ConnectionFailure)\\s*\\([^)]*\\berrorCode:"
        )
        .filter { snippet in
            guard let path = snippet.split(separator: ":", maxSplits: 1).first else { return true }
            return !allowedRawInitializerPaths.contains(String(path))
        }

        #expect(
            unexpectedRawInitializerSnippets.isEmpty,
            "Unexpected raw failure-domain initializers:\n\(unexpectedRawInitializerSnippets.sorted().joined(separator: "\n"))"
        )
    }

    @Test
    func `broad Any existential use stays limited to typed Foundation bridges`() throws {
        let root = try repositoryRoot()
        let productionFiles = try productionSwiftFiles(in: root)
        let allowedAnyLines: Set<String> = [
            "ButtonHeist/Sources/TheButtonHeist/Storage/PrivateStorage.swift:private typealias FoundationFileAttributeDictionary = [FileAttributeKey: Any]",
            "ButtonHeist/Sources/TheInsideJob/Lifecycle/StartupConfiguration.swift:static func value(from object: Any) -> InfoPlistValue {",
        ]
        let observed = try sourceMatches(
            in: productionFiles,
            root: root,
            pattern: #"(:|->|\[[^]]*:|Dictionary\s*<[^>]+,|Array\s*<|Set\s*<|\bany\s+)\s*Any\b"#
        )
        let unexpected = observed.subtracting(allowedAnyLines)

        #expect(unexpected.isEmpty, "Unexpected broad Any existential uses:\n\(unexpected.sorted().joined(separator: "\n"))")

        let allowedDictionaryBridgeLines: Set<String> = [
            "ButtonHeist/Sources/TheInsideJob/Lifecycle/StartupConfiguration.swift:let dictionary = propertyList as? NSDictionary else {",
        ]
        let unexpectedDictionaryBridgeLines = try sourceMatches(
            in: productionFiles,
            root: root,
            pattern: #"\bNS(Mutable)?Dictionary\b"#
        )
        .subtracting(allowedDictionaryBridgeLines)

        #expect(
            unexpectedDictionaryBridgeLines.isEmpty,
            "Unexpected Foundation dictionary bridges:\n\(unexpectedDictionaryBridgeLines.sorted().joined(separator: "\n"))"
        )
    }

    @Test
    func `raw AnyObject and ObjC perform dispatch stay limited to typed boundaries`() throws {
        let root = try repositoryRoot()
        let productionFiles = try productionSwiftFiles(in: root)

        let allowedAnyObjectLines: Set<String> = [
            "ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceProtocols.swift:protocol DeviceConnecting: AnyObject {",
            "ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceProtocols.swift:protocol DeviceDiscovering: AnyObject {",
            "ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceProtocols.swift:protocol TransportReachabilityConnecting: AnyObject {",
            "ButtonHeist/Sources/TheInsideJob/TheSafecracker/ObjCRuntime.swift:private typealias RawObjectiveCReceiver = AnyObject",
        ]
        let unexpectedAnyObjectLines = try sourceMatches(
            in: productionFiles,
            root: root,
            pattern: #"\bAnyObject\b"#
        )
        .subtracting(allowedAnyObjectLines)

        #expect(
            unexpectedAnyObjectLines.isEmpty,
            "Unexpected raw AnyObject uses:\n\(unexpectedAnyObjectLines.sorted().joined(separator: "\n"))"
        )

        let allowedSelectorPerformLines: Set<String> = [
            "ButtonHeist/Sources/TheInsideJob/TheSafecracker/ObjCRuntime.swift:_ = target.perform(selector)",
            "ButtonHeist/Sources/TheInsideJob/TheSafecracker/ObjCRuntime.swift:_ = target.perform(selector, with: argument)",
            "ButtonHeist/Sources/TheInsideJob/TheSafecracker/ObjCRuntime.swift:target.perform(selector)?.takeUnretainedValue() as? Result",
            "ButtonHeist/Sources/TheInsideJob/TheSafecracker/ObjCRuntime.swift:target.perform(selector, with: argument)?.takeUnretainedValue() as? Result",
        ]
        let unexpectedSelectorPerformLines = try sourceMatches(
            in: productionFiles,
            root: root,
            pattern: #"\.perform\s*\(\s*selector\b"#
        )
        .subtracting(allowedSelectorPerformLines)

        #expect(
            unexpectedSelectorPerformLines.isEmpty,
            "Unexpected selector perform dispatch:\n\(unexpectedSelectorPerformLines.sorted().joined(separator: "\n"))"
        )
    }

    @Test
    func `MCP SDK Value maps stay at the MCP argument boundary`() throws {
        let root = try repositoryRoot()
        let allowedPaths: Set<String> = [
            "ButtonHeistMCP/Sources/main.swift",
            "ButtonHeistMCP/Sources/MCPArgumentInputPreflight.swift",
            "ButtonHeistMCP/Tests/ToolRoutingTests.swift",
            "ButtonHeistMCP/Tests/ToolSyncTests.swift",
        ]
        let mcpFiles = try swiftFiles(in: root.appendingPathComponent("ButtonHeistMCP/Sources", isDirectory: true))
            + swiftFiles(in: root.appendingPathComponent("ButtonHeistMCP/Tests", isDirectory: true))
        let unexpected = try sourceMatchFiles(
            in: mcpFiles,
            root: root,
            pattern: #"\[String:\s*Value\]"#
        )
        .filter { !allowedPaths.contains($0) }

        #expect(unexpected.isEmpty, "Unexpected MCP SDK Value maps:\n\(unexpected.sorted().joined(separator: "\n"))")
    }
}

private func requireSuccess<Value>(
    _ result: ValidationResult<Value, HeistBuildDiagnostic>
) async throws -> (Value, [HeistBuildDiagnostic]) {
    let value = try result.get(orThrow: {
        CompilerTestFailure($0.map(\.description).joined(separator: "\n"))
    })
    return (value, result.diagnostics)
}

private func requireFailure<Value>(
    _ result: ValidationResult<Value, HeistBuildDiagnostic>
) async throws -> [HeistBuildDiagnostic] {
    guard let diagnostics = result.failureDiagnostics else {
        throw CompilerTestFailure("Expected compilation to fail")
    }
    return diagnostics
}

private final class CompilerTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("heist-compiler-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func writeSwiftSource(named fileName: String, _ source: String) throws -> URL {
        let url = url.appendingPathComponent(fileName)
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeSwiftSource(named fileName: String, namedPlan name: String) throws -> URL {
        try writeSwiftSource(
            named: fileName,
            """
            import ThePlans

            let heist = try HeistPlan("\(name)") {
                Warn("ok")
            }
            """
        )
    }
}

private func repositoryRoot() throws -> URL {
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    if isRepositoryRoot(currentDirectory) {
        return currentDirectory
    }

    var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while candidate.path != candidate.deletingLastPathComponent().path {
        if isRepositoryRoot(candidate) {
            return candidate
        }
        candidate = candidate.deletingLastPathComponent()
    }

    throw CompilerTestFailure("could not find repository root")
}

private func isRepositoryRoot(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.appendingPathComponent("ButtonHeist/Package.swift").path)
}

private func swiftFiles(in root: URL) throws -> [URL] {
    let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: Array(resourceKeys),
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var files: [URL] = []
    for case let url as URL in enumerator {
        if url.lastPathComponent == ".build" || url.lastPathComponent == "Derived" {
            enumerator.skipDescendants()
            continue
        }
        let values = try url.resourceValues(forKeys: resourceKeys)
        if values.isRegularFile == true, url.pathExtension == "swift" {
            files.append(url)
        }
    }
    return files
}

private func sourceLinesOutsideHeistPlanToolOutputSink(_ source: String) -> [(lineNumber: Int, line: Substring)] {
    var lines: [(lineNumber: Int, line: Substring)] = []
    var sinkBraceDepth: Int?

    for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        if sinkBraceDepth == nil, line.range(of: "enum HeistPlanToolOutput") != nil {
            let depth = braceDelta(in: line)
            sinkBraceDepth = depth > 0 ? depth : nil
            continue
        }

        if let currentDepth = sinkBraceDepth {
            let nextDepth = currentDepth + braceDelta(in: line)
            sinkBraceDepth = nextDepth > 0 ? nextDepth : nil
            continue
        }

        lines.append((lineNumber: index + 1, line: line))
    }

    return lines
}

private func braceDelta(in line: Substring) -> Int {
    line.reduce(0) { result, character in
        switch character {
        case "{":
            return result + 1
        case "}":
            return result - 1
        default:
            return result
        }
    }
}

private func productionSwiftFilesOutsideThePlans(in root: URL) throws -> [URL] {
    let relativeRoots = [
        "ButtonHeist/Sources/TheButtonHeist",
        "ButtonHeist/Sources/TheScore",
        "ButtonHeist/Sources/TheInsideJob",
        "ButtonHeist/Sources/HeistPlanTool",
        "ButtonHeistCLI/Sources",
        "ButtonHeistMCP/Sources",
    ]
    return try relativeRoots.flatMap { relativeRoot in
        try swiftFiles(in: root.appendingPathComponent(relativeRoot, isDirectory: true))
    }
}

private func productionSwiftFiles(in root: URL) throws -> [URL] {
    let relativeRoots = [
        "ButtonHeist/Sources",
        "ButtonHeistCLI/Sources",
        "ButtonHeistMCP/Sources",
    ]
    return try relativeRoots.flatMap { relativeRoot in
        try swiftFiles(in: root.appendingPathComponent(relativeRoot, isDirectory: true))
    }
}

private func sourceAndTestSwiftFiles(in root: URL) throws -> [URL] {
    let relativeRoots = [
        "ButtonHeist/Sources",
        "ButtonHeist/Tests",
        "ButtonHeistCLI/Sources",
        "ButtonHeistCLI/Tests",
        "ButtonHeistMCP/Sources",
        "ButtonHeistMCP/Tests",
    ]
    return try relativeRoots.flatMap { relativeRoot in
        try swiftFiles(in: root.appendingPathComponent(relativeRoot, isDirectory: true))
    }
}

private func sourceMatches(in files: [URL], root: URL, pattern: String) throws -> Set<String> {
    var matches: Set<String> = []
    for file in files {
        let relativePath = repositoryRelativePath(file, root: root)
        for line in try sourceLines(in: file) where line.range(of: pattern, options: .regularExpression) != nil {
            matches.insert("\(relativePath):\(line.trimmingCharacters(in: .whitespaces))")
        }
    }
    return matches
}

private func sourceMatchFiles(in files: [URL], root: URL, pattern: String) throws -> Set<String> {
    var matches: Set<String> = []
    for file in files {
        let lines = try sourceLines(in: file)
        if lines.contains(where: { $0.range(of: pattern, options: .regularExpression) != nil }) {
            matches.insert(repositoryRelativePath(file, root: root))
        }
    }
    return matches
}

private func sourceSnippets(in files: [URL], root: URL, pattern: String) throws -> Set<String> {
    let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    var matches: Set<String> = []
    for file in files {
        let source = try String(contentsOf: file, encoding: .utf8)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let relativePath = repositoryRelativePath(file, root: root)
        for match in regex.matches(in: source, range: range) {
            guard let sourceRange = Range(match.range, in: source) else { continue }
            let snippet = source[sourceRange]
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            matches.insert("\(relativePath):\(snippet)")
        }
    }
    return matches
}

private func sourceLines(in file: URL) throws -> [String] {
    try String(contentsOf: file, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
}

private func repositoryRelativePath(_ file: URL, root: URL) -> String {
    let rootPath = root.standardizedFileURL.path
    let filePath = file.standardizedFileURL.path
    guard filePath.hasPrefix(rootPath + "/") else {
        return file.path
    }
    return String(filePath.dropFirst(rootPath.count + 1))
}

private func sourceMatch(path: String, line: String) -> String {
    "\(path):\(line)"
}

private func jsonStringLiteral(_ value: String) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let literal = String(data: data, encoding: .utf8) else {
        throw CompilerTestFailure("could not encode JSON string literal")
    }
    return literal
}

private struct CompilerTestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

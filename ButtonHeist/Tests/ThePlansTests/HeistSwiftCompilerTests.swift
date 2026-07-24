import Foundation
import Testing
@testable import ThePlans

@Suite(.serialized)
struct HeistSwiftCompilerTests {
    @Test
    func `entry symbol validates one canonical dotted identifier currency`() throws {
        #expect(try HeistEntrySymbol(validating: "Checkout.compile").description == "Checkout.compile")
        #expect(throws: HeistEntrySymbol.ValidationError.self) {
            _ = try HeistEntrySymbol(validating: "Checkout-compile")
        }
    }

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

        let plan = try await HeistSwiftCompiler().compileFile(source)

        #expect(plan.name == "NamedPlan")
        #expect(plan.body == [.warn(WarnStep(message: "ok"))])
    }

    @Test
    func `compileFile rejects default heist value source`() async throws {
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

        let diagnostics = try await buildDiagnostics {
            try await HeistSwiftCompiler().compileFile(source)
        }
        let text = diagnostics.map(\.description).joined(separator: "\n")

        #expect(text.contains("cannot call value of non-function type"))
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

        let diagnostics = try await buildDiagnostics {
            try await HeistSwiftCompiler().compileFile(source)
        }
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

            func heist() throws -> HeistPlan {
                try HeistPlan("BadOutput") {
                    Warn("ok")
                }
            }
            """
        )

        let diagnostics = try await buildDiagnostics {
            try await HeistSwiftCompiler().compileFile(source)
        }
        let diagnostic = try #require(diagnostics.first)

        #expect(diagnostic.code.rawValue == "heist.swift_compilation.invalid_output")
        #expect(diagnostic.phase == .swiftCompilation)
        #expect(diagnostic.message.contains("valid HeistPlan JSON"))
        #expect(diagnostic.renderedMessage.count < 2_500)
    }

    @Test
    func `compileFile cancellation throws canonical build diagnostic`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(named: "Cancelled.swift", namedPlan: "Cancelled")
        let task = Task {
            try await HeistSwiftCompiler().compileFile(source)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected compilation cancellation to throw")
        } catch {
            let buildError = try #require(error as? HeistPlanBuildError)
            #expect(buildError.diagnostics.map(\.code.knownCode) == [.swiftCompilationCancelled])
        }
    }

#if !(os(macOS) || os(Linux))
    @Test
    func `compileFile unsupported platform throws canonical build diagnostic`() async throws {
        let source = URL(fileURLWithPath: "/tmp/Unsupported.swift")

        do {
            _ = try await HeistSwiftCompiler().compileFile(source)
            Issue.record("Expected unsupported platform compilation to throw")
        } catch {
            let buildError = try #require(error as? HeistPlanBuildError)
            #expect(buildError.diagnostics.map(\.code.knownCode) == [.swiftCompilationUnsupportedPlatform])
        }
    }
#endif

    @Test
    func `compiler plan JSON maps typed version admission failure`() {
        let data = Data(#"{"version":3,"body":[{"type":"warn","warn":{"message":"future"}}]}"#.utf8)
        let sourceURL = URL(fileURLWithPath: "/tmp/future-plan.swift")

        #expect(throws: HeistPlanJSONCodecError.unsupportedVersion(
            source: sourceURL.path,
            observed: 3
        )) {
            _ = try HeistPlanJSONCodec.decodeValidatedPlan(data, sourceURL: sourceURL)
        }
    }

    @Test
    func `compileFile returns a runtime validated HeistPlan`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "Validated.swift",
            """
            import ThePlans

            func heist() throws -> HeistPlan {
                try HeistPlan("Validated") {
                    Warn("ok")
                }
            }
            """
        )

        let plan = try await HeistSwiftCompiler().compileFile(source)

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

            func heist() throws -> HeistPlan {
                try StoreFlows.checkout()
            }
            """
        )

        let plan = try await HeistSwiftCompiler().compileFile(source)

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

            func heist() throws -> HeistPlan {
                try HeistPlan("WrapperStrings") {
                    Warn("ok")
                }
            }
            """#
        )

        let plan = try await HeistSwiftCompiler().compileFile(source)

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

            func heist() throws -> HeistPlan {
                try makeHeist()
            }
            """
        )

        let plan = try await HeistSwiftCompiler().compileFile(source)

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

            func heist() throws -> HeistPlan {
                try HeistPlan("TrustedFrontend") {
                    Activate(.label(payLabel()))
                        .expect(.changed(.screen()))
                }
            }
            """
        )

        let plan = try await HeistSwiftCompiler().compileFile(source)

        #expect(plan.name == "TrustedFrontend")
        #expect(plan.body == [
            .action(ActionStep(
                command: .activate(.predicate(.label("Pay"))),
                expectationPolicy: .expect(ActionExpectation(predicate: .changed(.screen()), timeout: 1)))),
        ])
    }

    @Test
    func `compileFile allows trusted Swift frontend to emit raw validated HeistPlan AST`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "RawBody.swift",
            """
            import ThePlans

            func heist() throws -> HeistPlan {
                try HeistPlan(name: "RawBody", body: [
                    .warn(WarnStep(message: "raw")),
                ])
            }
            """
        )

        let plan = try await HeistSwiftCompiler().compileFile(source)

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
            #expect(error.diagnostics.count == 2)
            #expect(error.diagnostics.allSatisfy { $0.code == .dslInvalidActionExpectation })
            #expect(error.diagnostics.allSatisfy { $0.phase == .dslBuild })
            #expect(error.diagnostics.allSatisfy { $0.path == "activate" })
            #expect(error.diagnostics.contains {
                $0.message.contains("unsupported expectation composition")
                    && $0.hint == "Use one canonical predicate per expectation, or add current-tree assertions inside .changed(.screen(...))."
            })
            #expect(error.diagnostics.contains {
                $0.message.contains("multiple explicit expectation timeouts")
                    && $0.hint == "Use one explicit timeout for the composed expectation."
            })
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
            func heist() throws -> HeistPlan {
                try HeistPlan("NativeIf") {
                    if shouldPay {
                        Activate(.label("Pay"))
                    }
                }
            }
            """
        )

        let diagnostics = try await buildDiagnostics {
            try await HeistSwiftCompiler().compileFile(source)
        }
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

            func heist() throws -> HeistPlan {
                try HeistPlan("NativeIfInDefinition") {
                    HeistDef<Void>("Helper") {
                        if Bool.random() {
                            Warn("raw")
                        }
                    }

                    RunHeist("Helper")
                }
            }
            """
        )

        let diagnostics = try await buildDiagnostics {
            try await HeistSwiftCompiler().compileFile(source)
        }
        let text = diagnostics.map(\.description).joined(separator: "\n")

        #expect(text.contains("Failed to compile Swift heist source"))
    }

    @Test
    func `conditionals compile with concrete screen assertions`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let validSource = try temp.writeSwiftSource(
            named: "SnapshotConditional.swift",
            """
            import ThePlans

            func heist() throws -> HeistPlan {
                try HeistPlan("SnapshotConditional") {
                    If(.exists(.label("Ready"))) {
                        Warn("ready")
                    }

                    If {
                        Case(.missing(.label("Loading"))) {
                            Warn("loaded")
                        }

                        Else {
                            Warn("loading")
                        }
                    }
                }
            }
            """
        )
        let plan = try await HeistSwiftCompiler().compileFile(validSource)
        #expect(plan.body.count == 2)
    }

    @Test
    func `canonical predicate composition compiles`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let validSource = try temp.writeSwiftSource(
            named: "PredicateComposition.swift",
            """
            import ThePlans

            func heist() throws -> HeistPlan {
                try HeistPlan("PredicateComposition") {
                    WaitFor(.exists(.label("Receipt")))
                    WaitFor(.missing(.label("Loading")))
                    WaitFor(.changed(.screen([
                        .exists(.label("Receipt")),
                        .missing(.label("Loading")),
                    ])))
                    WaitFor(.changed(.elements([
                        .updated(.identifier("count"), .value("3")),
                    ])))
                }
            }
            """
        )
        let plan = try await HeistSwiftCompiler().compileFile(validSource)
        #expect(plan.body.count == 4)
    }

    @Test
    func `compileDirectory compiles multiple Swift files into one catalog`() async throws {
        let temp = try CompilerTemporaryDirectory()
        _ = try temp.writeSwiftSource(named: "Alpha.swift", namedPlan: "Alpha")
        _ = try temp.writeSwiftSource(named: "Beta.swift", namedPlan: "Beta")

        let result = try await HeistSwiftCompiler().compileDirectory(temp.url)

        #expect(result.diagnostics.isEmpty)
        #expect(result.catalog.source == HeistCatalogSource(url: temp.url.standardizedFileURL))
        #expect(result.catalog.capabilities.map(\.name) == ["Alpha", "Beta"])
    }

    @Test
    func `compileDirectory fails duplicate capability names`() async throws {
        let temp = try CompilerTemporaryDirectory()
        _ = try temp.writeSwiftSource(named: "First.swift", namedPlan: "Duplicate")
        _ = try temp.writeSwiftSource(named: "Second.swift", namedPlan: "Duplicate")

        let diagnostics = try await buildDiagnostics {
            try await HeistSwiftCompiler().compileDirectory(temp.url)
        }
        let diagnostic = try #require(diagnostics.first)

        #expect(diagnostic.code.rawValue == "heist.catalog.duplicate_capability")
        #expect(diagnostic.phase == .planValidation)
        #expect(diagnostic.sourceSpan?.sourceName.hasSuffix("Second.swift") == true)
    }

    @Test
    func `compileDirectory does not derive names from filenames`() async throws {
        let temp = try CompilerTemporaryDirectory()
        _ = try temp.writeSwiftSource(named: "Filename.swift", namedPlan: "PlanName")

        let result = try await HeistSwiftCompiler().compileDirectory(temp.url)

        #expect(result.catalog.capabilities.map(\.name) == ["PlanName"])
        #expect(!result.catalog.capabilities.map { $0.name ?? "" }.contains("Filename"))
    }

    @Test
    func `compileDirectory ignores hidden files`() async throws {
        let temp = try CompilerTemporaryDirectory()
        _ = try temp.writeSwiftSource(named: ".Hidden.swift", "this is not Swift")
        _ = try temp.writeSwiftSource(named: "Visible.swift", namedPlan: "Visible")

        let result = try await HeistSwiftCompiler().compileDirectory(temp.url)

        #expect(result.catalog.capabilities.map(\.name) == ["Visible"])
    }

    @Test
    func `compileDirectory rejects anonymous capabilities in multi file catalog`() async throws {
        let temp = try CompilerTemporaryDirectory()
        _ = try temp.writeSwiftSource(
            named: "Anonymous.swift",
            """
            import ThePlans

            func heist() throws -> HeistPlan {
                try HeistPlan {
                    Warn("anonymous")
                }
            }
            """
        )
        _ = try temp.writeSwiftSource(named: "Named.swift", namedPlan: "Named")

        let diagnostics = try await buildDiagnostics {
            try await HeistSwiftCompiler().compileDirectory(temp.url)
        }

        #expect(diagnostics.map(\.description).joined(separator: "\n").contains("anonymous capability"))
    }

    @Test
    func testCompilerThrowsOrderedBuildDiagnostics() async throws {
        let temp = try CompilerTemporaryDirectory()
        _ = try temp.writeSwiftSource(named: "A.swift", namedPlan: "Valid")
        _ = try temp.writeSwiftSource(named: "B.swift", "not valid Swift")
        _ = try temp.writeSwiftSource(named: "C.swift", "also not valid Swift")

        do {
            _ = try await HeistSwiftCompiler().compileDirectory(temp.url)
            Issue.record("Expected directory compilation to throw")
        } catch let error {
            #expect(error.diagnostics.map { $0.sourceSpan?.sourceName }.compactMap { $0 } == [
                temp.url.appendingPathComponent("B.swift").path,
                temp.url.appendingPathComponent("C.swift").path,
            ])
            #expect(error.diagnostics.allSatisfy { $0.kind == .error })
        }
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

}

private func buildDiagnostics<Value>(
    _ operation: () async throws -> Value
) async throws -> [HeistBuildDiagnostic] {
    do {
        _ = try await operation()
        throw CompilerTestFailure("Expected compilation to fail")
    } catch let error as HeistPlanBuildError {
        return error.diagnostics
    }
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

            func heist() throws -> HeistPlan {
                try HeistPlan("\(name)") {
                    Warn("ok")
                }
            }
            """
        )
    }
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

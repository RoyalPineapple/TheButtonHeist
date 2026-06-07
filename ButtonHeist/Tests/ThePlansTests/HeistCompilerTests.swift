import Foundation
import Testing
import ThePlans

@Suite(.serialized)
struct HeistCompilerTests {
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

        #expect(diagnostics.contains { $0.severity == .error })
        #expect(diagnostics.map(\.description).joined(separator: "\n").contains("Broken.swift"))
        #expect(diagnostics.map(\.description).joined(separator: "\n").count < 2_500)
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

        #expect(diagnostics.map(\.description).joined(separator: "\n").contains("valid HeistPlan JSON"))
        #expect(diagnostics.map(\.description).joined(separator: "\n").count < 2_500)
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
    func `compileFile rejects native control flow inside heist body`() async throws {
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

        #expect(text.contains("Swift may wrap the heist"))
        #expect(text.contains("native Swift if/else is not supported inside ButtonHeist DSL bodies"))
    }

    @Test
    func `compileFile rejects arbitrary helper calls inside heist body`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "HelperCall.swift",
            """
            import ThePlans

            func payLabel() -> String { "Pay" }

            let heist = try HeistPlan("HelperCall") {
                Activate(.label(payLabel()))
            }
            """
        )

        let diagnostics = try await requireFailure(HeistCompiler().compileFile(source))
        let text = diagnostics.map(\.description).joined(separator: "\n")

        #expect(text.contains("Swift may wrap the heist"))
        #expect(text.contains("arbitrary calls are not supported inside ButtonHeist DSL bodies"))
    }

    @Test
    func `compileFile rejects helper heist calls inside heist body`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "HelperHeistCall.swift",
            """
            import ThePlans

            enum LibraryScreen {
                static let checkout = HeistDef<Void>("LibraryScreen.checkout") {
                    Warn("ok")
                }
            }

            let heist = try HeistPlan("HelperHeistCall") {
                try LibraryScreen.checkout()
            }
            """
        )

        let diagnostics = try await requireFailure(HeistCompiler().compileFile(source))
        let text = diagnostics.map(\.description).joined(separator: "\n")

        #expect(text.contains("Swift may wrap the heist"))
        #expect(text.contains("`try` is only allowed in Swift wrapper code"))
        #expect(text.contains("Use RunHeist(\"LibraryScreen.checkout\")"))
    }

    @Test
    func `compileFile rejects Swift declarations inside heist body`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "Intermixed.swift",
            """
            import ThePlans

            let heist = try HeistPlan("Intermixed") {
                let label = "Pay"
                Activate(.label(label))
            }
            """
        )

        let diagnostics = try await requireFailure(HeistCompiler().compileFile(source))
        let text = diagnostics.map(\.description).joined(separator: "\n")

        #expect(text.contains("Swift may wrap the heist"))
        #expect(text.contains("let declarations are not supported inside ButtonHeist DSL bodies"))
    }

    @Test
    func `compileFile rejects body local try inside heist body`() async throws {
        let temp = try CompilerTemporaryDirectory()
        let source = try temp.writeSwiftSource(
            named: "BodyTry.swift",
            """
            import ThePlans

            let heist = try HeistPlan("BodyTry") {
                try ForEach(["Milk"]) { item in
                    TypeText(item)
                }
            }
            """
        )

        let diagnostics = try await requireFailure(HeistCompiler().compileFile(source))
        let text = diagnostics.map(\.description).joined(separator: "\n")

        #expect(text.contains("`try` is only allowed in Swift wrapper code"))
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

        #expect(diagnostics.map(\.description).joined(separator: "\n").contains("Duplicate capability name"))
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
    func `source compiler remains behind ThePlans boundary`() throws {
        let root = try repositoryRoot()
        let files = try swiftFiles(in: root).filter {
            !$0.path.contains("/ButtonHeist/Sources/ThePlans/")
                && $0.lastPathComponent != "HeistCompilerTests.swift"
        }

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("HeistSourceCompiler"), "\(file.path) references HeistSourceCompiler")
            #expect(!source.contains("HeistSwiftFileCompiler"), "\(file.path) references HeistSwiftFileCompiler")
            #expect(!source.contains("swiftc"), "\(file.path) invokes swiftc")
            #expect(!source.contains("decodeValidatedHeistJSON"), "\(file.path) decodes compiler stdout")
        }
    }

    @Test
    func `untrusted heist planning representations stay behind ThePlans boundary`() throws {
        let root = try repositoryRoot()
        let files = try productionSwiftFilesOutsideThePlans(in: root)
        let forbiddenSnippets = [
            "@_spi(ButtonHeistInternals) import ThePlans",
            "UnvalidatedHeistPlan",
            ".validatedForRuntime(",
            "HeistPlanValidationError",
            "HeistPlanJSONCodec",
            "HeistArtifactCodec.read",
            "HeistArtifactCodec.decodePlanJSON",
            "JSONDecoder().decode(HeistPlan.self",
            "JSONDecoder().decode(UnvalidatedHeistPlan.self",
        ]

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for snippet in forbiddenSnippets {
                #expect(!source.contains(snippet), "\(file.path) contains \(snippet)")
            }
        }
    }
}

private func requireSuccess<Value>(
    _ result: HeistCompilationResult<Value>
) async throws -> (Value, [HeistCompilationDiagnostic]) {
    switch result {
    case .success(let value, let diagnostics):
        return (value, diagnostics)
    case .failure(let diagnostics):
        throw CompilerTestFailure(diagnostics.map(\.description).joined(separator: "\n"))
    }
}

private func requireFailure<Value>(
    _ result: HeistCompilationResult<Value>
) async throws -> [HeistCompilationDiagnostic] {
    switch result {
    case .success:
        throw CompilerTestFailure("Expected compilation to fail")
    case .failure(let diagnostics):
        return diagnostics
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

private struct CompilerTestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

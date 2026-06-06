import XCTest

@testable import ButtonHeist
import ThePlans
import TheScore

final class RecordedHeistSwiftExportTests: XCTestCase {

    func testConcreteRecordedPlanRendersSwiftDSLAndCompilesBack() async throws {
        let plan = try recordedSearchPlan()

        let result = try RecordedHeistSwiftExport().render(plan)

        XCTAssertEqual(result.source, """
        import ThePlans

        let heist = try HeistPlan("RecordedSearch") {
            TypeText("milk", into: .label("Search"))
                .expect(.present(.element(label: "Search", value: "milk")), timeout: .seconds(2))

            Activate(.label("Search"))
                .expect(.changed(.screen()), timeout: .seconds(5))
        }
        """)
        XCTAssertEqual(try result.plan.canonicalSwiftDSL(), try plan.canonicalSwiftDSL())

        #if SWIFT_PACKAGE && (os(macOS) || os(Linux))
        let compiled = try await compileExportedHeist(result.source)
        XCTAssertEqual(try compiled.canonicalSwiftDSL(), try plan.canonicalSwiftDSL())
        #endif
    }

    func testSampleRewriteParameterizesTypedTextAndExpectationValue() async throws {
        let plan = try recordedSearchPlan()

        let result = try RecordedHeistSwiftExport().render(
            plan,
            sampleRewrite: .init(parameterName: "query", sampleValue: "milk")
        )

        XCTAssertTrue(result.source.contains(#"let heist = try HeistPlan("RecordedSearch", parameter: "query") { query in"#))
        XCTAssertTrue(result.source.contains("TypeText(query, into: .label(\"Search\"))"))
        XCTAssertTrue(result.source.contains("value: query"))
        XCTAssertFalse(result.source.contains(#""milk""#))
        XCTAssertEqual(result.plan.parameter, .string(name: "query"))

        #if SWIFT_PACKAGE && (os(macOS) || os(Linux))
        let compiled = try await compileExportedHeist(result.source)
        XCTAssertEqual(try compiled.canonicalSwiftDSL(), try result.plan.canonicalSwiftDSL())
        #endif
    }

    func testSampleRewriteCanParameterizeExactLabelWhenLabelOnlyIsSafe() throws {
        let plan = try HeistPlan(name: "RecordedLabel", body: [
            .action(try ActionStep(command: .activate(.target(.label("milk"))))),
        ])

        let result = try RecordedHeistSwiftExport().render(
            plan,
            sampleRewrite: .init(parameterName: "query", sampleValue: "milk")
        )

        XCTAssertTrue(result.source.contains(#"HeistPlan("RecordedLabel", parameter: "query")"#))
        XCTAssertTrue(result.source.contains("Activate(.label(query))"))
    }

    func testSampleRewriteLeavesRepeatedLabelsConcrete() throws {
        let plan = try HeistPlan(name: "RecordedRepeatedLabels", body: [
            .action(try ActionStep(command: .activate(.target(.label("milk"))))),
            .wait(WaitStep(predicate: .present(.label("milk")), timeout: 1)),
        ])

        let result = try RecordedHeistSwiftExport().render(
            plan,
            sampleRewrite: .init(parameterName: "query", sampleValue: "milk")
        )

        XCTAssertTrue(result.source.contains(#"HeistPlan("RecordedRepeatedLabels")"#))
        XCTAssertTrue(result.source.contains(#"Activate(.label("milk"))"#))
        XCTAssertTrue(result.source.contains(#"WaitFor(.present(.label("milk")), timeout: .seconds(1))"#))
        XCTAssertFalse(result.source.contains("parameter: \"query\""))
        XCTAssertTrue(result.diagnostics.contains { $0.contains("multiple labels") })
    }

    func testPartialSampleMatchIsNotRewritten() throws {
        let plan = try HeistPlan(name: "RecordedPartial", body: [
            .action(try ActionStep(command: .typeText(
                text: .literal("milkshake"),
                target: .target(.label("Search"))
            ))),
        ])

        let result = try RecordedHeistSwiftExport().render(
            plan,
            sampleRewrite: .init(parameterName: "query", sampleValue: "milk")
        )

        XCTAssertTrue(result.source.contains(#"HeistPlan("RecordedPartial")"#))
        XCTAssertTrue(result.source.contains(#"TypeText("milkshake", into: .label("Search"))"#))
        XCTAssertFalse(result.source.contains("parameter: \"query\""))
    }

    func testAmbiguousLabelAndTypedTextLeavesLabelConcrete() throws {
        let plan = try HeistPlan(name: "RecordedAmbiguous", body: [
            .action(try ActionStep(command: .typeText(
                text: .literal("milk"),
                target: .target(.label("milk"))
            ))),
        ])

        let result = try RecordedHeistSwiftExport().render(
            plan,
            sampleRewrite: .init(parameterName: "query", sampleValue: "milk")
        )

        XCTAssertTrue(result.source.contains("TypeText(query, into: .label(\"milk\"))"))
        XCTAssertFalse(result.source.contains(".label(query)"))
        XCTAssertTrue(result.diagnostics.contains { $0.contains("typed text or value") })
    }

    func testIdentifiersAndTraitsAreNotRewritten() throws {
        let plan = try HeistPlan(name: "RecordedIdentifiers", body: [
            .action(try ActionStep(command: .typeText(
                text: .literal("milk"),
                target: .target(.predicate(ElementPredicate(
                    label: "Search",
                    identifier: "milk",
                    traits: [.button]
                )))
            ))),
        ])

        let result = try RecordedHeistSwiftExport().render(
            plan,
            sampleRewrite: .init(parameterName: "query", sampleValue: "milk")
        )

        XCTAssertTrue(result.source.contains("TypeText(query"))
        XCTAssertTrue(result.source.contains(#"identifier: "milk""#))
        XCTAssertTrue(result.source.contains("traits: [.button]"))
    }

    func testExporterRequiresNamedRecordedPlan() throws {
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(.target(.label("Search"))))),
        ])

        XCTAssertThrowsError(try RecordedHeistSwiftExport().render(plan)) { error in
            XCTAssertTrue(String(describing: error).contains("requires a non-empty heist name"))
        }
    }

    func testGeneratedSwiftContainsNoRecordingRuntimeIdentity() throws {
        let source = try RecordedHeistSwiftExport().render(recordedSearchPlan()).source

        for forbidden in ["heistId", "runtime", "capture", "containerName", "scrollable_", "ScreenPoint"] {
            XCTAssertFalse(source.contains(forbidden), "\(forbidden) leaked into generated Swift")
        }
    }

    @ButtonHeistActor
    func testStopHeistCanWriteHeistAndSwiftOutput() async throws {
        let tempDirectory = TempDirectoryFixture.make(prefix: "recorded-swift-export-command")
        defer { TempDirectoryFixture.remove(tempDirectory) }
        let heistURL = tempDirectory.appendingPathComponent("recording.heist")
        let swiftURL = tempDirectory.appendingPathComponent("recording.swift")
        let fence = TheFence(configuration: .init())

        _ = try fence.handleStartHeist(.init(app: "com.example.app", identifier: "RecordedSearch"))
        try fence.heistStore.appendSteps(recordedSearchPlan().body)
        let response = try fence.handleStopHeist(.init(
            outputPath: heistURL.path,
            swiftOutputPath: swiftURL.path,
            sampleRewrite: nil
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: heistURL.appendingPathComponent("plan.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: swiftURL.path))
        guard case .heistStopped(let path, let swiftPath, let stepCount) = response else {
            return XCTFail("Expected heistStopped response")
        }
        XCTAssertEqual(path, heistURL.path)
        XCTAssertEqual(swiftPath, swiftURL.path)
        XCTAssertEqual(stepCount, 2)
    }

    @ButtonHeistActor
    func testStopHeistCanStillWriteOnlyHeistOutput() async throws {
        let tempDirectory = TempDirectoryFixture.make(prefix: "recorded-heist-only-command")
        defer { TempDirectoryFixture.remove(tempDirectory) }
        let heistURL = tempDirectory.appendingPathComponent("recording.heist")
        let fence = TheFence(configuration: .init())

        _ = try fence.handleStartHeist(.init(app: "com.example.app", identifier: "RecordedSearch"))
        try fence.heistStore.appendSteps(recordedSearchPlan().body)
        let response = try fence.handleStopHeist(.init(
            outputPath: heistURL.path,
            swiftOutputPath: nil,
            sampleRewrite: nil
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: heistURL.appendingPathComponent("plan.json").path))
        guard case .heistStopped(let path, let swiftPath, let stepCount) = response else {
            return XCTFail("Expected heistStopped response")
        }
        XCTAssertEqual(path, heistURL.path)
        XCTAssertNil(swiftPath)
        XCTAssertEqual(stepCount, 2)
    }

    @ButtonHeistActor
    func testInvalidSwiftOutputPathFailsBeforeStoppingRecording() async throws {
        let tempDirectory = TempDirectoryFixture.make(prefix: "recorded-invalid-swift-path")
        defer { TempDirectoryFixture.remove(tempDirectory) }
        let fence = TheFence(configuration: .init())

        _ = try fence.handleStartHeist(.init(app: "com.example.app", identifier: "RecordedSearch"))
        try fence.heistStore.appendSteps(recordedSearchPlan().body)

        XCTAssertThrowsError(try fence.handleStopHeist(.init(
            outputPath: tempDirectory.appendingPathComponent("recording.heist").path,
            swiftOutputPath: "../recording.swift",
            sampleRewrite: nil
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("Invalid Swift output path"))
        }
        XCTAssertTrue(fence.heistStore.isRecordingHeist)
    }

    @ButtonHeistActor
    func testSwiftExportRenderFailureStillWritesHeistOutput() async throws {
        let tempDirectory = TempDirectoryFixture.make(prefix: "recorded-swift-render-failure")
        defer { TempDirectoryFixture.remove(tempDirectory) }
        let heistURL = tempDirectory.appendingPathComponent("recording.heist")
        let swiftURL = tempDirectory.appendingPathComponent("recording.swift")
        let fence = TheFence(configuration: .init())

        _ = try fence.handleStartHeist(.init(app: "com.example.app", identifier: "RecordedSearch"))
        try fence.heistStore.appendSteps(recordedSearchPlan().body)

        XCTAssertThrowsError(try fence.handleStopHeist(.init(
            outputPath: heistURL.path,
            swiftOutputPath: swiftURL.path,
            sampleRewrite: .init(parameterName: "not valid", sampleValue: "milk")
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("invalid sample rewrite parameter"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: heistURL.appendingPathComponent("plan.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: swiftURL.path))
    }

    @ButtonHeistActor
    func testInvalidSampleRewriteRequestFailsBeforeStoppingRecording() async throws {
        let tempDirectory = TempDirectoryFixture.make(prefix: "recorded-invalid-sample-rewrite")
        defer { TempDirectoryFixture.remove(tempDirectory) }
        let heistURL = tempDirectory.appendingPathComponent("recording.heist")
        let swiftURL = tempDirectory.appendingPathComponent("recording.swift")
        let fence = TheFence(configuration: .init())

        _ = try fence.handleStartHeist(.init(app: "com.example.app", identifier: "RecordedSearch"))
        defer { fence.heistStore.abandonRecording() }
        try fence.heistStore.appendSteps(recordedSearchPlan().body)

        let invalidCases: [(values: [String: HeistValue], message: String)] = [
            ([
                "output": .string(heistURL.path),
                "sampleParameter": .string("query"),
                "sampleValue": .string("milk"),
            ], "sample rewrite requires swiftOutput"),
            ([
                "output": .string(heistURL.path),
                "swiftOutput": .string(swiftURL.path),
                "sampleParameter": .string("not valid"),
                "sampleValue": .string("milk"),
            ], "sample rewrite parameter must be a Swift-style identifier"),
            ([
                "output": .string(heistURL.path),
                "swiftOutput": .string(swiftURL.path),
                "sampleParameter": .string("query"),
                "sampleValue": .string(""),
            ], "sample rewrite value must not be empty"),
            ([
                "output": .string(heistURL.path),
                "swiftOutput": .string(swiftURL.path),
                "sampleParameter": .string("query"),
            ], "sample rewrite requires both sampleParameter and sampleValue"),
        ]

        for invalidCase in invalidCases {
            XCTAssertThrowsError(try fence.parseRequest(command: .stopHeist, values: invalidCase.values)) { error in
                XCTAssertTrue(String(describing: error).contains(invalidCase.message), "\(error)")
            }
            XCTAssertTrue(fence.heistStore.isRecordingHeist)
        }
    }

    private func recordedSearchPlan() throws -> HeistPlan {
        let searchValueExpectation = AccessibilityPredicate.state(.present(
            ElementPredicate.element(label: "Search", value: "milk")
        ))
        return try HeistPlan(name: "RecordedSearch", body: [
            .action(try ActionStep(
                command: .typeText(
                    text: .literal("milk"),
                    target: .target(.label("Search"))
                ),
                expectation: WaitStep(
                    predicate: searchValueExpectation,
                    timeout: 2
                )
            )),
            .action(try ActionStep(
                command: .activate(.target(.label("Search"))),
                expectation: WaitStep(predicate: .changed(.screen()), timeout: 5)
            )),
        ])
    }

    #if SWIFT_PACKAGE && (os(macOS) || os(Linux))
    private func compileExportedHeist(_ source: String) async throws -> HeistPlan {
        let tempDirectory = TempDirectoryFixture.make(prefix: "recorded-swift-compile")
        defer { TempDirectoryFixture.remove(tempDirectory) }
        let sourceURL = tempDirectory.appendingPathComponent("Recorded.swift")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        let result = await HeistCompiler(configuration: .init(packageRoot: buttonHeistPackageRoot()))
            .compileFile(sourceURL, entry: "heist")
        switch result {
        case .success(let plan, _):
            return plan
        case .failure(let diagnostics):
            throw CompileBackFailure(diagnostics: diagnostics.map(\.description))
        }
    }

    private func buttonHeistPackageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
    #endif
}

#if SWIFT_PACKAGE && (os(macOS) || os(Linux))
private struct CompileBackFailure: Error, CustomStringConvertible {
    let diagnostics: [String]

    var description: String {
        diagnostics.joined(separator: "\n")
    }
}
#endif

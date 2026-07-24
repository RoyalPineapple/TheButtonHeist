import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

@Test
func `plan loading loads generated heist artifact source`() throws {
    let temp = try PlansTemporaryDirectory()
    let artifactURL = temp.url.appendingPathComponent("SearchFlow.heist")
    let plan = try representativeArtifactPlan()
    try HeistArtifactCodec.writePlan(plan, to: artifactURL)

    let request = try HeistPlanSourceAdmission.admit(
        commandName: "run_heist",
        path: artifactURL.path,
        inlineDSL: nil
    )
    let loaded = try HeistPlanLoading.loadValidated(from: request)

    #expect(loaded == plan)
}

@Test
func `plan loading compiles inline ButtonHeist DSL source`() throws {
    let request = try HeistPlanSourceAdmission.admit(
        commandName: "run_heist",
        path: nil,
        inlineDSL: """
        HeistPlan("sourceFlow") {
        Warn("from source")
        }
        """
    )
    let loaded = try HeistPlanLoading.loadValidated(from: request)

    #expect(loaded.name == "sourceFlow")
    #expect(loaded.body == [.warn(WarnStep(message: "from source"))])
}

@Test
func `plan source admission raw IR keys map to a closed rejected field set`() throws {
    let fields = HeistPlanRejectedPublicSourceField.sourceFields(in: [
        "version",
        "path",
        "body",
        "argument",
    ])

    #expect(fields == [.version, .body])
}

@Test
func `plan source admission rejects missing public source`() throws {
    let diagnostic = try buildDiagnostic {
        try HeistPlanSourceAdmission.admit(
            commandName: "run_heist",
            path: nil,
            inlineDSL: nil
        )
    }
    #expect(diagnostic.message.contains(
        "run_heist requires exactly one plan source"
    ))
}

@Test
func `plan source admission rejects multiple public sources`() throws {
    let diagnostic = try buildDiagnostic {
        try HeistPlanSourceAdmission.admit(
            commandName: "run_heist",
            path: "/tmp/SearchFlow.heist",
            inlineDSL: #"HeistPlan("searchFlow") { Warn("from source") }"#
        )
    }
    #expect(diagnostic.message.contains(
        "run_heist accepts exactly one plan source"
    ))
}

@Test
func `plan source admission rejects inline source when policy is artifact only`() throws {
    let diagnostic = try buildDiagnostic {
        try HeistPlanSourceAdmission.admit(
            commandName: "heist-plan",
            path: nil,
            inlineDSL: #"HeistPlan("searchFlow") { Warn("from source") }"#,
            sourcePolicy: .artifactOnly
        )
    }
    #expect(diagnostic.message.contains(
        "heist-plan does not accept inline ButtonHeist DSL source"
    ))
}

@Test
func `plan loading rejects standalone raw json path as public source`() throws {
    let temp = try PlansTemporaryDirectory()
    let jsonURL = temp.url.appendingPathComponent("SearchFlow.json")
    try representativeArtifactPlan().canonicalHeistJSONData().write(to: jsonURL)

    let message = try buildDiagnostic {
        try HeistPlanLoading.loadValidated(from: HeistPlanLoadRequest(
            commandName: "run_heist",
            source: .artifactPath(jsonURL.path)
        ))
    }.message

    #expect(message.contains("raw `.json` HeistPlan IR"))
    #expect(message.contains("not public run input"))
}

@Test
func `plan source admission rejects raw structured JSON IR fields`() throws {
    let message = try buildDiagnostic {
        try HeistPlanSourceAdmission.rejectRawStructuredJSONIRSourceFields(
            commandName: "run_heist",
            fields: [.version, .body]
        )
    }.message

    #expect(message.contains("raw JSON HeistPlan IR field"))
    #expect(message.contains("ButtonHeist DSL"))
    #expect(message.contains(".heist"))
}

private func buildDiagnostic<Value>(_ operation: () throws -> Value) throws -> HeistBuildDiagnostic {
    do {
        _ = try operation()
        throw PlansTestFailure("Expected plan build to fail")
    } catch let error as HeistPlanBuildError {
        return try #require(error.diagnostics.first)
    }
}

private struct PlansTestFailure: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

@Test
func `raw JSON with heist extension fails`() throws {
    let temp = try PlansTemporaryDirectory()
    let artifactURL = temp.url.appendingPathComponent("SearchFlow.heist")
    try representativeArtifactPlan().canonicalHeistJSONData().write(to: artifactURL)

    #expect(throws: HeistArtifactCodecError.self) {
        try HeistArtifactCodec.readPlan(from: artifactURL)
    }
}

@Test
func `plan JSON admission rejects non object JSON with explicit diagnostic`() throws {
    let url = URL(fileURLWithPath: "/tmp/non-object-plan.json")

    do {
        _ = try HeistArtifactCodec.decodeAdmissionCandidateJSON(Data(#"["not an object"]"#.utf8), at: url)
        Issue.record("Expected non-object plan JSON to fail")
    } catch {
        #expect(String(describing: error).contains(
            "Invalid heist plan at /tmp/non-object-plan.json: expected JSON object"
        ))
    }
}

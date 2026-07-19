import Testing
@testable import ThePlans

func assertCanonicalRoundTrip(_ plan: HeistPlan) throws {
    let source = try plan.canonicalSwiftDSL()
    let compiled = try HeistSourceCompilation.compile(source)
    #expect(compiled == plan, "Rendered source did not compile back to the same plan:\n\(source)")
}

func compileError(_ source: String) -> String {
    do {
        _ = try HeistSourceCompilation.compile(source)
        Issue.record("Expected source to fail: \(source)")
        return ""
    } catch {
        return String(describing: error)
    }
}

func compileDiagnostic(_ source: String) -> HeistBuildDiagnostic {
    do {
        _ = try HeistSourceCompilation.compile(source)
        Issue.record("Expected source to fail: \(source)")
        return HeistBuildDiagnostic(
            externalBoundaryRawCode: "test.missing_diagnostic",
            phase: .sourceCompilation,
            message: "Expected source to fail"
        )
    } catch let error as HeistSourceCompilationError {
        return error.diagnostic
    } catch {
        Issue.record("Expected HeistSourceCompilationError, got \(error)")
        return HeistBuildDiagnostic(
            externalBoundaryRawCode: "test.unexpected_error",
            phase: .sourceCompilation,
            message: String(describing: error)
        )
    }
}

func root(_ body: String) -> String {
    """
    HeistPlan {
    \(body)
    }
    """
}

func expect(_ string: String, contains substring: String) {
    if !string.contains(substring) {
        Issue.record("Expected error to contain '\(substring)', got: \(string)")
    }
    #expect(string.contains(substring))
}

@Test func `inline plan source RunHeist syntax validates through normal runtime pipeline`() throws {
    let diagnostic = compileDiagnostic(root("""
    RunHeist("CartScreen.checkout")
    """))

    #expect(diagnostic.code.rawValue == "heist.plan.runtime_safety")
    #expect(diagnostic.kind == .error)
    #expect(diagnostic.phase == .planValidation)
    #expect(diagnostic.path == "$.body[0].invoke.path")
}

@Test func `non-durable action admission exposes source diagnostic code and path`() throws {
    let raw = HeistPlanAdmissionCandidate(body: [
        .action(ActionStep(command: .scroll(ScrollTarget(direction: .down)))),
    ])
    guard case .failure(let diagnostics) = raw.runtimeSafetyValidationResult(),
          let diagnostic = diagnostics.first else {
        Issue.record("Expected non-durable action to fail runtime safety admission")
        return
    }

    #expect(diagnostics.count == 1)
    #expect(diagnostic.code == .nonDurableAction)
    #expect(diagnostic.code.rawValue == "heist.plan.non_durable_action")
    #expect(diagnostic.kind == .error)
    #expect(diagnostic.phase == .planValidation)
    #expect(diagnostic.path == "$.body[0].action.command")
    #expect(
        diagnostic.message ==
            "durable heist action; observed scroll is a direct client command, " +
            "not a durable heist action"
    )
    #expect(diagnostic.hint == nonDurableHeistActionRepairHint)
}

@Test func `inline plan source unsupported Swift syntax is rejected`() throws {
    for source in [
        "let x = 1",
        "FileManager.default",
        "Process()",
        #"await Warn("x")"#,
    ] {
        #expect(throws: HeistSourceCompilationError.self) {
            _ = try HeistSourceCompilation.compile(source)
        }
    }
}

@Test func `inline plan source syntax errors expose typed diagnostic fields`() throws {
    let diagnostic = compileDiagnostic("""
    HeistPlan {
        let label = "Pay"
        Activate(.label(label))
    }
    """)

    #expect(diagnostic.code.rawValue == "heist.source.invalid_syntax")
    #expect(diagnostic.kind == .error)
    #expect(diagnostic.phase == .sourceCompilation)
    #expect(diagnostic.sourceSpan?.sourceName == "inline-heist-plan")
    #expect(diagnostic.sourceSpan?.line == 2)
    #expect(diagnostic.sourceSpan?.column == 5)
}

@Test func `planning admission exposes typed diagnostics before rendering`() {
    let result = HeistPlanSourceAdmission.rejectRawStructuredJSONIRSourceFields(
        commandName: "run_heist",
        fields: [.body, .version]
    )

    guard let diagnostic = result.failureDiagnostics?.first else {
        Issue.record("Expected raw JSON IR fields to fail planning admission")
        return
    }

    #expect(diagnostic.code.rawValue == "heist.planning.raw_json_ir_fields")
    #expect(diagnostic.kind == .error)
    #expect(diagnostic.phase == .planning)
    #expect(diagnostic.sourceSpan == nil)
}

@Test func `canonical ForEach string compiles without body try`() throws {
    let plan = try HeistSourceCompilation.compile(root("""
    ForEach("a") { item in
        TypeText(item)
    }
    """))
    let expected = try HeistPlan(body: [
        .forEachString(try ForEachStringStep(
            values: ["a"],
            parameter: "item",
            body: [
                .action(ActionStep(command: .typeText(reference: "item", target: nil))),
            ]
        )),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source import Foundation is rejected`() throws {
    #expect(throws: HeistSourceCompilationError.self) {
        _ = try HeistSourceCompilation.compile("""
        import Foundation
        Activate(.label("Pay"))
        """)
    }
}

@Test func `inline plan source while true is rejected`() throws {
    #expect(throws: HeistSourceCompilationError.self) {
        _ = try HeistSourceCompilation.compile("""
        while true {
            Activate(.label("Pay"))
        }
        """)
    }
}

@Test func `inline plan source arbitrary function declaration is rejected`() throws {
    #expect(throws: HeistSourceCompilationError.self) {
        _ = try HeistSourceCompilation.compile("""
        func pay() {
            Activate(.label("Pay"))
        }
        """)
    }
}

private let nonDurableHeistActionRepairHint =
    "Use a direct client command for debug/session actions, or replace " +
    "this with a canonical durable DSL action."

@Test func `runtime source compilation rejects standard definition cap`() throws {
    let definitions = (0...250).map { index in
        """
            HeistDef<String>("Definitions.definition\(index)", parameter: "value") { value in
                Activate(.label(value))
            }
        """
    }.joined(separator: "\n\n")
    let source = """
    HeistPlan("tooManyDefinitions") {
    \(definitions)

        Warn("body")
    }
    """

    let diagnostic = compileError(source)

    expect(diagnostic, contains: "max total heist definitions")
    expect(diagnostic, contains: "252 definitions")

    let typedDiagnostic = compileDiagnostic(source)
    #expect(typedDiagnostic.code.rawValue == "heist.plan.runtime_safety")
    #expect(typedDiagnostic.phase == .planValidation)
    #expect(typedDiagnostic.path == "$.definitions[0].definitions")
    #expect(typedDiagnostic.hint == "Use 250 definitions or fewer.")
}

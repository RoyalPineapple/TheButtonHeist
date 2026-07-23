import Testing
@testable import ThePlans

@Test func `validationResult map preserves success diagnostics`() {
    let warning = validationDiagnostic(.warning, "kept")
    let result = ValidationResult<Int, HeistBuildDiagnostic>
        .success(2, diagnostics: [warning])
        .map { "\($0)" }

    #expect(result.value == "2")
    #expect(result.diagnostics == [warning])
}

@Test func `validationResult flatMap carries prior warnings into downstream failure`() {
    let warning = validationDiagnostic(.warning, "upstream")
    let error = validationDiagnostic(.error, "downstream")
    let result: ValidationResult<String, HeistBuildDiagnostic> = ValidationResult<Int, HeistBuildDiagnostic>
        .success(1, diagnostics: [warning])
        .flatMap { _ in .failure([error]) }

    #expect(result.failureDiagnostics == [warning, error])
}

@Test func `validationResult mapDiagnostics transforms success and failure diagnostics`() {
    let warning = validationDiagnostic(.warning, "warning")
    let error = validationDiagnostic(.error, "error")
    let success = ValidationResult<Int, HeistBuildDiagnostic>
        .success(1, diagnostics: [warning])
        .mapDiagnostics(\.message)
    let failure = ValidationResult<Int, HeistBuildDiagnostic>
        .failure([error])
        .mapDiagnostics(\.message)

    #expect(success.diagnostics == ["warning"])
    #expect(failure.failureDiagnostics == ["error"])
}

@Test func `validationResult value throws constructed failure error`() throws {
    let error = validationDiagnostic(.error, "failed")

    do {
        _ = try ValidationResult<Int, HeistBuildDiagnostic>
            .failure([error])
            .value(orThrow: ValidationResultTestError.init(diagnostics:))
        Issue.record("Expected value(orThrow:) to throw")
    } catch let thrown as ValidationResultTestError {
        #expect(thrown.diagnostics == [error])
    }
}

@Test func `collectValidationResults preserves values and diagnostics in order`() {
    let firstWarning = validationDiagnostic(.warning, "first")
    let secondWarning = validationDiagnostic(.warning, "second")
    let results: [ValidationResult<String, HeistBuildDiagnostic>] = [
        .success("one", diagnostics: [firstWarning]),
        .success("two", diagnostics: [secondWarning]),
    ]
    let collected = results.collectValidationResults()

    #expect(collected.value == ["one", "two"])
    #expect(collected.diagnostics == [firstWarning, secondWarning])
}

@Test func `collectValidationResults carries success warnings into collected failure`() {
    let warning = validationDiagnostic(.warning, "compiled")
    let error = validationDiagnostic(.error, "failed")
    let results: [ValidationResult<String, HeistBuildDiagnostic>] = [
        .success("one", diagnostics: [warning]),
        .failure([error]),
    ]
    let collected = results.collectValidationResults()

    #expect(collected.failureDiagnostics == [warning, error])
}

private struct ValidationResultTestError: Error, Equatable {
    let diagnostics: [HeistBuildDiagnostic]
}

private func validationDiagnostic(
    _ kind: HeistBuildDiagnosticKind,
    _ message: String
) -> HeistBuildDiagnostic {
    HeistBuildDiagnostic(
        externalBoundaryRawCode: "heist.validation_result.test",
        kind: kind,
        phase: .planValidation,
        message: message
    )
}

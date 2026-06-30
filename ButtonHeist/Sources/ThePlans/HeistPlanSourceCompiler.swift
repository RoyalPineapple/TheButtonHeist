import Foundation

package struct HeistPlanSourceCompiler: Sendable {
    package init() {}

    package func compileResult(
        _ source: String,
        sourceName: String = "inline-heist-plan"
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        do {
            var lexer = HeistPlanSourceLexer(source: source, sourceName: sourceName)
            let tokens = try lexer.lex()
            var parser = HeistPlanSourceParser(tokens: tokens, sourceName: sourceName)
            let plan = try parser.parseProgram()
            return plan.semanticValidationResult()
        } catch let error as HeistPlanSourceCompilerError {
            return .failure(error.diagnostics)
        } catch let error as HeistPlanRuntimeSafetyError {
            return .failure(error.diagnostics)
        } catch {
            return .failure([HeistBuildDiagnostic(
                code: .planRuntimeSafety,
                phase: .planValidation,
                message: "ButtonHeist source failed runtime safety: \(String(describing: error))"
            )])
        }
    }

    package func compile(
        _ source: String,
        sourceName: String = "inline-heist-plan"
    ) throws -> HeistPlan {
        try compileResult(source, sourceName: sourceName)
            .get(orThrow: HeistPlanSourceCompilerError.init(diagnostics:))
    }
}

package struct HeistPlanSourceCompilerError: Error, Sendable, Equatable, CustomStringConvertible {
    package let diagnostics: [HeistBuildDiagnostic]

    package var diagnostic: HeistBuildDiagnostic { diagnostics.first ?? HeistBuildDiagnostic(
        code: .sourceInvalidSyntax,
        phase: .sourceCompilation,
        message: "ButtonHeist source failed without diagnostics"
    ) }
    package var message: String { diagnostics.map(\.message).joined(separator: "\n") }
    package var sourceName: String { diagnostic.sourceSpan?.sourceName ?? "" }
    package var offset: Int { diagnostic.sourceSpan?.offset ?? 0 }
    package var line: Int { diagnostic.sourceSpan?.line ?? 1 }
    package var column: Int { diagnostic.sourceSpan?.column ?? 1 }

    package var description: String {
        diagnostics.map(\.renderedMessage).joined(separator: "\n")
    }

    package init(
        code: String = "heist.source.invalid_syntax",
        phase: HeistBuildPhase = .sourceCompilation,
        message: String,
        sourceName: String,
        offset: Int,
        line: Int,
        column: Int,
        length: Int? = nil,
        hint: String? = nil
    ) {
        self.init(diagnostic: HeistBuildDiagnostic(
            code: code,
            phase: phase,
            sourceSpan: HeistBuildSourceSpan(
                sourceName: sourceName,
                offset: offset,
                line: line,
                column: column,
                length: length
            ),
            message: message,
            hint: hint
        ))
    }

    package init(diagnostic: HeistBuildDiagnostic) {
        self.init(diagnostics: [diagnostic])
    }

    package init(diagnostics: [HeistBuildDiagnostic]) {
        self.diagnostics = diagnostics.isEmpty
            ? [HeistBuildDiagnostic(
                code: .sourceInvalidSyntax,
                phase: .sourceCompilation,
                message: "ButtonHeist source failed without diagnostics"
            )]
            : diagnostics
    }
}

public extension HeistPlanning {
    static func compileHeistPlanSource(
        _ source: String,
        sourceName: String = "inline-heist-plan"
    ) throws -> HeistPlan {
        try HeistPlanSourceCompiler().compile(source, sourceName: sourceName)
    }
}

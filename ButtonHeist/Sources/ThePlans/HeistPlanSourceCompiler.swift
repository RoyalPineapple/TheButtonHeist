import Foundation

public struct HeistPlanSourceCompiler: Sendable {
    public init() {}

    public func compile(
        _ source: String,
        sourceName: String = "inline-heist-plan"
    ) throws -> HeistPlan {
        do {
            var lexer = HeistPlanSourceLexer(source: source, sourceName: sourceName)
            let tokens = try lexer.lex()
            var parser = HeistPlanSourceParser(tokens: tokens, sourceName: sourceName)
            let plan = try parser.parseProgram()
            switch plan.runtimeSafetyValidationResult() {
            case .success(let validated, _):
                return validated
            case .failure(let diagnostics):
                throw HeistPlanSourceCompilerError(diagnostic: diagnostics[0])
            }
        } catch let error as HeistPlanSourceCompilerError {
            throw error
        } catch let error as HeistPlanRuntimeSafetyError {
            throw HeistPlanSourceCompilerError(diagnostic: error.diagnostics.first ?? HeistBuildDiagnostic(
                code: "heist.plan.runtime_safety",
                phase: .planValidation,
                message: error.description
            ))
        } catch {
            throw HeistPlanSourceCompilerError(
                code: "heist.plan.runtime_safety",
                phase: .planValidation,
                message: "ButtonHeist source failed runtime safety: \(String(describing: error))",
                sourceName: sourceName,
                offset: 0,
                line: 1,
                column: 1
            )
        }
    }
}

public struct HeistPlanSourceCompilerError: Error, Sendable, Equatable, CustomStringConvertible {
    public let diagnostic: HeistBuildDiagnostic

    public var message: String { diagnostic.message }
    public var sourceName: String { diagnostic.sourceSpan?.sourceName ?? "" }
    public var offset: Int { diagnostic.sourceSpan?.offset ?? 0 }
    public var line: Int { diagnostic.sourceSpan?.line ?? 1 }
    public var column: Int { diagnostic.sourceSpan?.column ?? 1 }

    public var description: String {
        diagnostic.renderedMessage
    }

    public init(
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

    public init(diagnostic: HeistBuildDiagnostic) {
        self.diagnostic = diagnostic
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

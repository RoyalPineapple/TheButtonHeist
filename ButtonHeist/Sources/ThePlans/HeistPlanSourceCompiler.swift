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
            return try plan.validatedForRuntime()
        } catch let error as HeistPlanSourceCompilerError {
            throw error
        } catch {
            throw HeistPlanSourceCompilerError(
                message: "ButtonHeist source failed runtime validation: \(String(describing: error))",
                sourceName: sourceName,
                offset: 0,
                line: 1,
                column: 1
            )
        }
    }
}

public struct HeistPlanSourceCompilerError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public let sourceName: String
    public let offset: Int
    public let line: Int
    public let column: Int

    public var description: String {
        "\(sourceName):\(line):\(column): \(message)"
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

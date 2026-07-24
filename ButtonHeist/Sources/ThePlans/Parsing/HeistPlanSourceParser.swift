import Foundation

struct HeistPlanSourceParser {
    let tokens: [HeistPlanSourceToken]

    var index: Int = 0
    var scope = HeistPlanSourceScope()

    init(tokens: [HeistPlanSourceToken]) {
        self.tokens = tokens
    }

    mutating func parseProgram() throws -> HeistPlan {
        if startsRootHeistPlan {
            let root = try parseRootHeistPlan()
            try expect(.eof)
            var validator = HeistPlanRuntimeSafetyValidator(limits: .standard)
            return try validator.admit(root)
        }

        try rejectForbiddenStatementSyntax()
        throw error(currentToken, "ButtonHeist source must be a canonical root plan: `HeistPlan { ... }`")
    }
}

import Foundation

struct HeistPlanSourceParser {
    let tokens: [HeistPlanSourceToken]
    let sourceName: String

    var index: Int = 0
    var scope = HeistPlanSourceScope()

    init(tokens: [HeistPlanSourceToken], sourceName: String) {
        self.tokens = tokens
        self.sourceName = sourceName
    }

    mutating func parseProgram() throws -> HeistPlanAdmissionCandidate {
        if startsRootHeistPlan {
            let root = try parseRootHeistPlan()
            try expect(.eof)
            return root
        }

        try rejectForbiddenStatementSyntax()
        throw error(currentToken, "ButtonHeist source must be a canonical root plan: `HeistPlan { ... }`")
    }
}

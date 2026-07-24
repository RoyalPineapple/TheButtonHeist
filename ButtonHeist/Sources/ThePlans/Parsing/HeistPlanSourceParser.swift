import Foundation

struct HeistPlanSourceParser {
    let tokens: [HeistPlanSourceToken]

    var index: Int = 0
    var scope = HeistPlanSourceScope()

    init(tokens: [HeistPlanSourceToken]) {
        self.tokens = tokens
    }

}

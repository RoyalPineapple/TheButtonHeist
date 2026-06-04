import ThePlans

public struct HeistRunRequest: Sendable, Equatable {
    public let heistPlan: HeistPlan

    public init(_ plan: HeistPlan) {
        self.heistPlan = plan
    }
}

public func runHeist<Result: Sendable>(
    _ plan: HeistPlan,
    using execute: @Sendable (HeistPlan) async throws -> Result
) async throws -> Result {
    try await execute(plan)
}

public func runHeist<Result: Sendable>(
    @HeistBuilder _ content: () throws -> some HeistContent,
    using execute: @Sendable (HeistPlan) async throws -> Result
) async throws -> Result {
    try await runHeist(try HeistPlan(content), using: execute)
}

import TheScore

public struct HeistRunRequest: Sendable, Equatable {
    public let plan: HeistPlan

    public init(_ heist: Heist) {
        self.plan = heist.plan
    }

    public init(_ plan: HeistPlan) {
        self.plan = plan
    }
}

public func runHeist<Result: Sendable>(
    _ heist: Heist,
    using execute: @Sendable (HeistPlan) async throws -> Result
) async throws -> Result {
    try await execute(heist.plan)
}

public func runHeist<Result: Sendable>(
    @HeistBuilder _ content: () -> some HeistContent,
    using execute: @Sendable (HeistPlan) async throws -> Result
) async throws -> Result {
    try await runHeist(Heist(content), using: execute)
}

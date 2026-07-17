extension TheFence {
    /// Execute one user intent.
    ///
    /// Durable executable UI actions and the `wait` command run as a one-step
    /// `HeistPlan` on the device — the same engine that runs a composed heist.
    /// Transient runtime actions that are not durable heist primitives fall
    /// through to direct client dispatch. Non-action commands (interface,
    /// screen, session, the `get_pasteboard` read) keep their dedicated handler.
    @_spi(ButtonHeistTooling) public func execute(_ request: FenceOperationRequest) async throws -> FenceResponse {
        try await ensureConnectedIfNeeded(for: request.command)
        do {
            return try await dispatch(request)
        } catch let error as SchemaValidationError {
            return .failure(error)
        }
    }

    private func ensureConnectedIfNeeded(for command: Command) async throws {
        guard !handoff.connectionLifecycle.isConnected, command.descriptor.requiresConnectionBeforeDispatch else { return }
        try await start()
    }
}

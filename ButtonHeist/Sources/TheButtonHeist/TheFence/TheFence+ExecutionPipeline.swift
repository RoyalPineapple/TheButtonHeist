extension TheFence {
    /// Execute one user intent.
    ///
    /// Durable executable UI actions and the `wait` command run as a one-step
    /// `HeistPlan` on the device — the same engine that runs a composed heist.
    /// Transient runtime actions that are not durable heist primitives execute
    /// directly. Non-action commands retain their dedicated response operation.
    @_spi(ButtonHeistTooling) public func execute(_ admittedCommand: AdmittedFenceCommand) async throws -> FenceResponse {
        try await connectIfRequired(for: admittedCommand.command)
        do {
            switch admittedCommand.execution {
            case .singleStepHeist(let step):
                return try await executeSingleStepHeist(step)
            case .directAction(let action):
                return try await executeDirectAction(action, command: admittedCommand.command)
            case .response(let operation):
                return try await operation(self)
            }
        } catch let error as SchemaValidationError {
            return .failure(error)
        }
    }

    private func connectIfRequired(for command: Command) async throws {
        guard !handoff.connectionLifecycle.isConnected,
              command.descriptor.requiresConnectionBeforeDispatch else { return }
        try await start()
    }
}

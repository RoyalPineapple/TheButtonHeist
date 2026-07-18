enum HeistActionPayloadAdmission {
    static func resolve(
        _ command: HeistActionCommand,
        in environment: HeistExecutionEnvironment
    ) throws -> ResolvedHeistActionCommand {
        let resolved = try command.resolve(in: environment)
        guard case .rotor(let selection, let target, let direction) = resolved else {
            return resolved
        }
        return .rotor(
            selection: try RotorSelection.decode(
                name: selection.rotorName,
                index: selection.rotorIndex,
                codingPath: []
            ),
            target: target,
            direction: direction
        )
    }
}

enum HeistActionPayloadAdmission {
    static func resolve(
        _ command: HeistActionCommand,
        in environment: HeistExecutionEnvironment
    ) throws -> ResolvedHeistActionCommand {
        let resolved = try command.resolve(in: environment)
        if case .rotor(selection: .index(let index), target: _, direction: _) = resolved,
           index < 0 {
            throw HeistActionPayloadAdmissionError.negativeRotorIndex(index)
        }
        return resolved
    }
}

private enum HeistActionPayloadAdmissionError: Error, CustomStringConvertible {
    case negativeRotorIndex(Int)

    var description: String {
        switch self {
        case .negativeRotorIndex(let index):
            return "rotorIndex must be non-negative, got \(index)"
        }
    }
}

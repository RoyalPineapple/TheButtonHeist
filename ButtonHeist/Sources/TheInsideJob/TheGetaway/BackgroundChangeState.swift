#if canImport(UIKit)
#if DEBUG

struct BackgroundChangeState: Sendable, Equatable {
    private var progress: ChangeProgress = .caughtUp(generation: 0)
    private(set) var phase: Phase = .idle

    /// Encodes whether background parsing is caught up; `.pending` is only
    /// used when `parsedThroughGeneration < latestGeneration`.
    private enum ChangeProgress: Sendable, Equatable {
        case caughtUp(generation: UInt64)
        case pending(latestGeneration: UInt64, parsedThroughGeneration: UInt64)

        init(latestGeneration: UInt64, parsedThroughGeneration: UInt64) {
            if parsedThroughGeneration >= latestGeneration {
                self = .caughtUp(generation: latestGeneration)
            } else {
                self = .pending(
                    latestGeneration: latestGeneration,
                    parsedThroughGeneration: parsedThroughGeneration
                )
            }
        }

        var latestGeneration: UInt64 {
            switch self {
            case .caughtUp(let generation):
                return generation
            case .pending(let latestGeneration, _):
                return latestGeneration
            }
        }

        var parsedThroughGeneration: UInt64 {
            switch self {
            case .caughtUp(let generation):
                return generation
            case .pending(_, let parsedThroughGeneration):
                return parsedThroughGeneration
            }
        }

        var hasPendingSettledChange: Bool {
            if case .pending = self { return true }
            return false
        }

        mutating func noteChange() {
            self = ChangeProgress(
                latestGeneration: latestGeneration &+ 1,
                parsedThroughGeneration: parsedThroughGeneration
            )
        }

        mutating func markObserved(through generation: UInt64) {
            self = ChangeProgress(
                latestGeneration: latestGeneration,
                parsedThroughGeneration: max(parsedThroughGeneration, min(generation, latestGeneration))
            )
        }
    }

    enum Phase: Sendable, Equatable {
        case idle
        case command(count: Int)
        case settledParse(claimedGeneration: UInt64, commandCount: Int)
    }

    var latestGeneration: UInt64 {
        progress.latestGeneration
    }

    var parsedThroughGeneration: UInt64 {
        progress.parsedThroughGeneration
    }

    var hasPendingSettledChange: Bool {
        progress.hasPendingSettledChange
    }

    var canBeginSettledParse: Bool {
        phase == .idle && hasPendingSettledChange
    }

    var isCommandInFlight: Bool {
        switch phase {
        case .command(let count), .settledParse(_, let count):
            return count > 0
        case .idle:
            return false
        }
    }

    var isSettledParseInFlight: Bool {
        if case .settledParse = phase { return true }
        return false
    }

    mutating func noteChange() {
        progress.noteChange()
    }

    mutating func markObserved(through generation: UInt64) {
        progress.markObserved(through: generation)
    }

    mutating func beginCommand() {
        switch phase {
        case .idle:
            phase = .command(count: 1)
        case .command(let count):
            phase = .command(count: count + 1)
        case .settledParse(let claimedGeneration, let commandCount):
            phase = .settledParse(claimedGeneration: claimedGeneration, commandCount: commandCount + 1)
        }
    }

    mutating func finishCommand() {
        switch phase {
        case .idle:
            return
        case .command(let count):
            phase = count > 1 ? .command(count: count - 1) : .idle
        case .settledParse(let claimedGeneration, let commandCount):
            guard commandCount > 0 else { return }
            phase = .settledParse(claimedGeneration: claimedGeneration, commandCount: commandCount - 1)
        }
    }

    mutating func beginSettledParse() -> UInt64? {
        guard phase == .idle, hasPendingSettledChange else { return nil }
        let claim = latestGeneration
        phase = .settledParse(claimedGeneration: claim, commandCount: 0)
        return claim
    }

    mutating func finishSettledParse(claimedGeneration: UInt64) {
        guard case .settledParse(let currentClaim, let commandCount) = phase,
              currentClaim == claimedGeneration else {
            return
        }
        progress.markObserved(through: claimedGeneration)
        if commandCount > 0 {
            phase = .command(count: commandCount)
        } else {
            phase = .idle
        }
    }

    mutating func reset() {
        progress = .caughtUp(generation: 0)
        phase = .idle
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

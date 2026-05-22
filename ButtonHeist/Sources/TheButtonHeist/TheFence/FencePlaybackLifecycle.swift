import Foundation

/// Owns heist playback re-entrancy state for TheFence.
@ButtonHeistActor
final class FencePlaybackLifecycle {
    struct Snapshot: Equatable {
        let isPlaying: Bool
        let startedAt: Date?
    }

    private enum Phase {
        case idle
        case playing(startedAt: Date)
    }

    private var phase: Phase = .idle

    var snapshot: Snapshot {
        switch phase {
        case .idle:
            return Snapshot(isPlaying: false, startedAt: nil)
        case .playing(let startedAt):
            return Snapshot(isPlaying: true, startedAt: startedAt)
        }
    }

    var isIdle: Bool {
        if case .idle = phase { return true }
        return false
    }

    func requireIdle() throws {
        guard isIdle else {
            throw FenceError.invalidRequest("Cannot nest play_heist inside an active playback")
        }
    }

    func begin(startedAt: Date = Date()) throws {
        try requireIdle()
        phase = .playing(startedAt: startedAt)
    }

    func end() {
        phase = .idle
    }
}

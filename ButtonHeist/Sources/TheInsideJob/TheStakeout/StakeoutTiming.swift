import Foundation

import TheScore

struct StakeoutTiming: Equatable {
    let maxDuration: TimeInterval
    let inactivityTimeout: TimeInterval?
}

func resolvedStakeoutTiming(for config: RecordingConfig) -> StakeoutTiming {
    let maxDuration = max(1.0, config.maxDuration ?? 60.0)
    let inactivityTimeout = config.inactivityTimeout.map { max(1.0, $0) }
    return StakeoutTiming(maxDuration: maxDuration, inactivityTimeout: inactivityTimeout)
}

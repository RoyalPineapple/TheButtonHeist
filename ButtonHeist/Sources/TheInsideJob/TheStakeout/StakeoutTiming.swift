import Foundation

import TheScore

struct StakeoutTiming: Equatable {
    let maxDuration: TimeInterval
    let inactivityTimeout: TimeInterval
}

func resolvedStakeoutTiming(for config: RecordingConfig) -> StakeoutTiming {
    let maxDuration = max(1.0, config.maxDuration ?? 60.0)
    let inactivityTimeout = max(1.0, config.inactivityTimeout ?? maxDuration)
    return StakeoutTiming(maxDuration: maxDuration, inactivityTimeout: inactivityTimeout)
}

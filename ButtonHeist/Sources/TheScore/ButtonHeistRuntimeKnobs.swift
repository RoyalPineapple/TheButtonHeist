import Foundation

public struct ButtonHeistRuntimeKnobs: Equatable, Sendable {
    public let postScrollLayoutFrames: Int
    public let tripwirePulseFramesPerSecond: Int
    public let maxScrollsPerContainer: Int
    public let maxScrollsPerDiscovery: Int
    public let visibleElementBudget: Int

    public static let defaultPostScrollLayoutFrames = 3
    public static let defaultTripwirePulseFramesPerSecond = 10
    public static let defaultMaxScrollsPerContainer = 200
    public static let defaultMaxScrollsPerDiscovery = 200
    public static let defaultVisibleElementBudget = 100

    public static var current: ButtonHeistRuntimeKnobs {
        resolve()
    }

    public var singleTripwireTickSettleTimeout: TimeInterval {
        max(0.05, 2.0 / Double(tripwirePulseFramesPerSecond))
    }

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ButtonHeistRuntimeKnobs {
        ButtonHeistRuntimeKnobs(
            postScrollLayoutFrames: intOverride(
                keys: ["BH_POST_SCROLL_LAYOUT_FRAMES", "BUTTONHEIST_POST_SCROLL_LAYOUT_FRAMES"],
                environment: environment,
                defaultValue: defaultPostScrollLayoutFrames,
                range: 0...10
            ),
            tripwirePulseFramesPerSecond: intOverride(
                keys: ["BH_TRIPWIRE_PULSE_HZ", "BUTTONHEIST_TRIPWIRE_PULSE_HZ"],
                environment: environment,
                defaultValue: defaultTripwirePulseFramesPerSecond,
                range: 1...120
            ),
            maxScrollsPerContainer: intOverride(
                keys: ["BH_MAX_SCROLLS_PER_CONTAINER", "BUTTONHEIST_MAX_SCROLLS_PER_CONTAINER"],
                environment: environment,
                defaultValue: defaultMaxScrollsPerContainer,
                range: 1...2_000
            ),
            maxScrollsPerDiscovery: intOverride(
                keys: ["BH_MAX_SCROLLS_PER_DISCOVERY", "BUTTONHEIST_MAX_SCROLLS_PER_DISCOVERY"],
                environment: environment,
                defaultValue: defaultMaxScrollsPerDiscovery,
                range: 1...2_000
            ),
            visibleElementBudget: intOverride(
                keys: [
                    "BH_SCROLL_SUBTREE_ELEMENT_BUDGET",
                    "BUTTONHEIST_SCROLL_SUBTREE_ELEMENT_BUDGET",
                    "BH_VISIBLE_ELEMENT_BUDGET",
                    "BUTTONHEIST_VISIBLE_ELEMENT_BUDGET",
                ],
                environment: environment,
                defaultValue: defaultVisibleElementBudget,
                range: 0...1_000
            )
        )
    }

    private static func intOverride(
        keys: [String],
        environment: [String: String],
        defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        for key in keys {
            if let value = boundedInt(environment[key], range: range) {
                return value
            }
            if let value = boundedInt(environment["TEST_RUNNER_\(key)"], range: range) {
                return value
            }
        }
        return defaultValue
    }

    private static func boundedInt(_ rawValue: String?, range: ClosedRange<Int>) -> Int? {
        guard let rawValue, let value = Int(rawValue) else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

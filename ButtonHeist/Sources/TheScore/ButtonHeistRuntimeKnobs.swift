import Foundation

public struct RuntimeKnobEnvironmentKey: Hashable, Sendable {
    fileprivate let rawValue: String

    fileprivate init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var testRunnerPrefixed: RuntimeKnobEnvironmentKey {
        RuntimeKnobEnvironmentKey("TEST_RUNNER_\(rawValue)")
    }

    public static let postScrollLayoutFrames = RuntimeKnobEnvironmentKey("BH_POST_SCROLL_LAYOUT_FRAMES")
    public static let buttonHeistPostScrollLayoutFrames = RuntimeKnobEnvironmentKey("BUTTONHEIST_POST_SCROLL_LAYOUT_FRAMES")
    public static let tripwirePulseFramesPerSecond = RuntimeKnobEnvironmentKey("BH_TRIPWIRE_PULSE_HZ")
    public static let buttonHeistTripwirePulseFramesPerSecond = RuntimeKnobEnvironmentKey("BUTTONHEIST_TRIPWIRE_PULSE_HZ")
    public static let maxScrollsPerContainer = RuntimeKnobEnvironmentKey("BH_MAX_SCROLLS_PER_CONTAINER")
    public static let buttonHeistMaxScrollsPerContainer = RuntimeKnobEnvironmentKey("BUTTONHEIST_MAX_SCROLLS_PER_CONTAINER")
    public static let maxScrollsPerDiscovery = RuntimeKnobEnvironmentKey("BH_MAX_SCROLLS_PER_DISCOVERY")
    public static let buttonHeistMaxScrollsPerDiscovery = RuntimeKnobEnvironmentKey("BUTTONHEIST_MAX_SCROLLS_PER_DISCOVERY")
    public static let scrollSubtreeElementBudget = RuntimeKnobEnvironmentKey("BH_SCROLL_SUBTREE_ELEMENT_BUDGET")
    public static let buttonHeistScrollSubtreeElementBudget = RuntimeKnobEnvironmentKey("BUTTONHEIST_SCROLL_SUBTREE_ELEMENT_BUDGET")
    public static let visibleElementBudget = RuntimeKnobEnvironmentKey("BH_VISIBLE_ELEMENT_BUDGET")
    public static let buttonHeistVisibleElementBudget = RuntimeKnobEnvironmentKey("BUTTONHEIST_VISIBLE_ELEMENT_BUDGET")
    public static let totalNodeBudget = RuntimeKnobEnvironmentKey("BH_TOTAL_NODE_BUDGET")
    public static let buttonHeistTotalNodeBudget = RuntimeKnobEnvironmentKey("BUTTONHEIST_TOTAL_NODE_BUDGET")

    fileprivate static let processProjectionKeys: [RuntimeKnobEnvironmentKey] = {
        let aliases: [RuntimeKnobEnvironmentKey] = [
            .postScrollLayoutFrames,
            .buttonHeistPostScrollLayoutFrames,
            .tripwirePulseFramesPerSecond,
            .buttonHeistTripwirePulseFramesPerSecond,
            .maxScrollsPerContainer,
            .buttonHeistMaxScrollsPerContainer,
            .maxScrollsPerDiscovery,
            .buttonHeistMaxScrollsPerDiscovery,
            .scrollSubtreeElementBudget,
            .buttonHeistScrollSubtreeElementBudget,
            .visibleElementBudget,
            .buttonHeistVisibleElementBudget,
            .totalNodeBudget,
            .buttonHeistTotalNodeBudget,
        ]
        return aliases + aliases.map(\.testRunnerPrefixed)
    }()
}

public struct RuntimeKnobEnvironment: Equatable, Sendable {
    public static let empty = RuntimeKnobEnvironment()

    private let values: [RuntimeKnobEnvironmentKey: String]

    public init(values: [RuntimeKnobEnvironmentKey: String] = [:]) {
        self.values = values
    }

    fileprivate init(rawValues: [String: String]) {
        self.values = Dictionary(uniqueKeysWithValues: RuntimeKnobEnvironmentKey.processProjectionKeys.compactMap { key in
            rawValues[key.rawValue].map { (key, $0) }
        })
    }

    fileprivate subscript(key: RuntimeKnobEnvironmentKey) -> String? {
        values[key]
    }
}

public enum RuntimeKnobEnvironmentBridge {
    public static func current() -> RuntimeKnobEnvironment {
        RuntimeKnobEnvironment(rawValues: ProcessInfo.processInfo.environment)
    }
}

public struct ButtonHeistRuntimeKnobs: Equatable, Sendable {
    public let postScrollLayoutFrames: Int
    public let tripwirePulseFramesPerSecond: Int
    public let maxScrollsPerContainer: Int
    public let maxScrollsPerDiscovery: Int
    public let visibleElementBudget: Int
    public let totalNodeBudget: Int

    public static let defaultPostScrollLayoutFrames = 3
    public static let defaultTripwirePulseFramesPerSecond = 10
    public static let defaultMaxScrollsPerContainer = 200
    public static let defaultMaxScrollsPerDiscovery = 200
    public static let defaultVisibleElementBudget = 300
    public static let defaultTotalNodeBudget = 5_000

    public static var current: ButtonHeistRuntimeKnobs {
        resolve()
    }

    public var singleTripwireTickSettleTimeout: TimeInterval {
        max(0.05, 2.0 / Double(tripwirePulseFramesPerSecond))
    }

    public static func resolve(
        environment: RuntimeKnobEnvironment = RuntimeKnobEnvironmentBridge.current()
    ) -> ButtonHeistRuntimeKnobs {
        ButtonHeistRuntimeKnobs(
            postScrollLayoutFrames: intOverride(
                keys: [.postScrollLayoutFrames, .buttonHeistPostScrollLayoutFrames],
                environment: environment,
                defaultValue: defaultPostScrollLayoutFrames,
                range: 0...10
            ),
            tripwirePulseFramesPerSecond: intOverride(
                keys: [.tripwirePulseFramesPerSecond, .buttonHeistTripwirePulseFramesPerSecond],
                environment: environment,
                defaultValue: defaultTripwirePulseFramesPerSecond,
                range: 1...120
            ),
            maxScrollsPerContainer: intOverride(
                keys: [.maxScrollsPerContainer, .buttonHeistMaxScrollsPerContainer],
                environment: environment,
                defaultValue: defaultMaxScrollsPerContainer,
                range: 1...2_000
            ),
            maxScrollsPerDiscovery: intOverride(
                keys: [.maxScrollsPerDiscovery, .buttonHeistMaxScrollsPerDiscovery],
                environment: environment,
                defaultValue: defaultMaxScrollsPerDiscovery,
                range: 1...2_000
            ),
            visibleElementBudget: intOverride(
                keys: [
                    .scrollSubtreeElementBudget,
                    .buttonHeistScrollSubtreeElementBudget,
                    .visibleElementBudget,
                    .buttonHeistVisibleElementBudget,
                ],
                environment: environment,
                defaultValue: defaultVisibleElementBudget,
                range: 0...1_000
            ),
            totalNodeBudget: intOverride(
                keys: [.totalNodeBudget, .buttonHeistTotalNodeBudget],
                environment: environment,
                defaultValue: defaultTotalNodeBudget,
                range: 0...5_000
            )
        )
    }

    private static func intOverride(
        keys: [RuntimeKnobEnvironmentKey],
        environment: RuntimeKnobEnvironment,
        defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        for key in keys {
            if let value = boundedInt(environment[key], range: range) {
                return value
            }
            if let value = boundedInt(environment[key.testRunnerPrefixed], range: range) {
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

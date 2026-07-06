import Foundation

package struct RuntimeKnobEnvironmentKey: Hashable, Sendable {
    fileprivate let rawValue: String

    fileprivate init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    package var testRunnerPrefixed: RuntimeKnobEnvironmentKey {
        RuntimeKnobEnvironmentKey("TEST_RUNNER_\(rawValue)")
    }

    package static let postScrollLayoutFrames = RuntimeKnobEnvironmentKey("BH_POST_SCROLL_LAYOUT_FRAMES")
    package static let tripwirePulseFramesPerSecond = RuntimeKnobEnvironmentKey("BH_TRIPWIRE_PULSE_HZ")
    package static let maxScrollsPerContainer = RuntimeKnobEnvironmentKey("BH_MAX_SCROLLS_PER_CONTAINER")
    package static let maxScrollsPerDiscovery = RuntimeKnobEnvironmentKey("BH_MAX_SCROLLS_PER_DISCOVERY")
    package static let scrollSubtreeElementBudget = RuntimeKnobEnvironmentKey("BH_SCROLL_SUBTREE_ELEMENT_BUDGET")
    package static let totalNodeBudget = RuntimeKnobEnvironmentKey("BH_TOTAL_NODE_BUDGET")
}

package struct RuntimeKnobEnvironment: Equatable, Sendable {
    package static let empty = RuntimeKnobEnvironment()

    private let values: [String: String]

    package init(values: [RuntimeKnobEnvironmentKey: String] = [:]) {
        self.values = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
    }

    fileprivate init(rawValues: [String: String]) {
        self.values = rawValues
    }

    fileprivate subscript(key: RuntimeKnobEnvironmentKey) -> String? {
        values[key.rawValue]
    }
}

package enum RuntimeKnobEnvironmentBridge {
    package static func current() -> RuntimeKnobEnvironment {
        RuntimeKnobEnvironment(rawValues: ProcessInfo.processInfo.environment)
    }
}

package struct ButtonHeistRuntimeKnobs: Equatable, Sendable {
    package let postScrollLayoutFrames: Int
    package let tripwirePulseFramesPerSecond: Int
    package let maxScrollsPerContainer: Int
    package let maxScrollsPerDiscovery: Int
    package let visibleElementBudget: Int
    package let totalNodeBudget: Int

    package static let defaultPostScrollLayoutFrames = 3
    package static let defaultTripwirePulseFramesPerSecond = 10
    package static let defaultMaxScrollsPerContainer = 200
    package static let defaultMaxScrollsPerDiscovery = 200
    package static let defaultVisibleElementBudget = 300
    package static let defaultTotalNodeBudget = 5_000

    package static var current: ButtonHeistRuntimeKnobs {
        resolve()
    }

    package var singleTripwireTickSettleTimeout: TimeInterval {
        max(0.05, 2.0 / Double(tripwirePulseFramesPerSecond))
    }

    package static func resolve(
        environment: RuntimeKnobEnvironment = RuntimeKnobEnvironmentBridge.current()
    ) -> ButtonHeistRuntimeKnobs {
        ButtonHeistRuntimeKnobs(
            postScrollLayoutFrames: intOverride(
                key: .postScrollLayoutFrames,
                environment: environment,
                defaultValue: defaultPostScrollLayoutFrames,
                range: 0...10
            ),
            tripwirePulseFramesPerSecond: intOverride(
                key: .tripwirePulseFramesPerSecond,
                environment: environment,
                defaultValue: defaultTripwirePulseFramesPerSecond,
                range: 1...120
            ),
            maxScrollsPerContainer: intOverride(
                key: .maxScrollsPerContainer,
                environment: environment,
                defaultValue: defaultMaxScrollsPerContainer,
                range: 1...2_000
            ),
            maxScrollsPerDiscovery: intOverride(
                key: .maxScrollsPerDiscovery,
                environment: environment,
                defaultValue: defaultMaxScrollsPerDiscovery,
                range: 1...2_000
            ),
            visibleElementBudget: intOverride(
                key: .scrollSubtreeElementBudget,
                environment: environment,
                defaultValue: defaultVisibleElementBudget,
                range: 0...1_000
            ),
            totalNodeBudget: intOverride(
                key: .totalNodeBudget,
                environment: environment,
                defaultValue: defaultTotalNodeBudget,
                range: 0...5_000
            )
        )
    }

    private static func intOverride(
        key: RuntimeKnobEnvironmentKey,
        environment: RuntimeKnobEnvironment,
        defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        if let value = boundedInt(environment[key], range: range) {
            return value
        }
        if let value = boundedInt(environment[key.testRunnerPrefixed], range: range) {
            return value
        }
        return defaultValue
    }

    private static func boundedInt(_ rawValue: String?, range: ClosedRange<Int>) -> Int? {
        guard let rawValue, let value = Int(rawValue) else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

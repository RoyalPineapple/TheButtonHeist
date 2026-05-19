import Foundation

import TheScore

extension TheFence {
    struct TypedHeistPlayback: Sendable {
        let app: String
        let steps: [PlaybackOperation]

        init(wire playback: HeistPlayback) throws {
            app = playback.app
            steps = try playback.steps.enumerated().map { index, evidence in
                try PlaybackOperation(evidence: evidence, index: index)
            }
        }

        var totalStepCount: Int {
            steps.count
        }
    }

    struct PlaybackOperation: Sendable {
        let command: Command
        let target: ElementMatcher?
        let ordinal: Int?
        let payload: PlaybackPayload

        init(evidence: HeistEvidence, index: Int) throws {
            let payload = PlaybackPayload(values: evidence.arguments)
            var operationArguments = payload.dispatchBridgeArguments()
            operationArguments["command"] = evidence.command

            let operation: NormalizedOperation
            switch FenceOperationCatalog.normalizePlaybackStep(operationArguments) {
            case .success(let normalized):
                operation = normalized
            case .failure(let error):
                throw FenceError.invalidRequest(
                    "Invalid heist step \(index): \(error.message)"
                )
            }

            self.init(
                command: operation.command,
                target: evidence.target,
                ordinal: evidence.ordinal,
                payload: payload
            )
        }

        private init(
            command: Command,
            target: ElementMatcher?,
            ordinal: Int?,
            payload: PlaybackPayload
        ) {
            self.command = command
            self.target = target
            self.ordinal = ordinal
            self.payload = payload
        }

        var commandName: String {
            command.rawValue
        }

        /// Bridge typed playback data into the legacy handler argument shape.
        ///
        /// Playback never uses this for command selection: command routing is
        /// already bound to `TheFence.Command`. This is the single execution
        /// edge where existing handlers still consume schema-checked
        /// `[String: Any]` arguments.
        func dispatchBridgeArguments() -> [String: Any] {
            var arguments = payload.dispatchBridgeArguments()
            arguments["command"] = command.rawValue

            if let target {
                if let label = target.label { arguments["label"] = label }
                if let matchIdentifier = target.identifier { arguments["identifier"] = matchIdentifier }
                if let matchValue = target.value { arguments["value"] = matchValue }
                if let matchTraits = target.traits { arguments["traits"] = matchTraits.map(\.rawValue) }
                if let matchExclude = target.excludeTraits { arguments["excludeTraits"] = matchExclude.map(\.rawValue) }
            }
            if let ordinal { arguments["ordinal"] = ordinal }

            return arguments
        }
    }

    struct PlaybackPayload: Sendable, Equatable {
        private let values: [String: HeistValue]

        init(values: [String: HeistValue]) {
            self.values = values
        }

        subscript(key: String) -> HeistValue? {
            values[key]
        }

        func dispatchBridgeArguments() -> [String: Any] {
            values.mapValues { $0.toAny() }
        }
    }
}

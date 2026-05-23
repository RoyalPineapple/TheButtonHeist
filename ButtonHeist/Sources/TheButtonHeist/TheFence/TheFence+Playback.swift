import Foundation

import TheScore

extension TheFence {
    struct TypedHeistPlayback: Sendable {
        let app: String
        let steps: [PlaybackOperation]

        @ButtonHeistActor
        init(contentsOf url: URL) throws {
            try self.init(wire: TheBookKeeper.readHeist(from: url))
        }

        init(wire playback: HeistPlayback) throws {
            guard playback.version == HeistPlayback.currentVersion else {
                throw FenceError.invalidRequest(
                    "Unsupported heist file version \(playback.version). " +
                        "This Button Heist build supports version \(HeistPlayback.currentVersion). " +
                        "Re-record the heist with the current format."
                )
            }

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

            let command: Command
            switch FenceOperationCatalog.normalizePlaybackStep(
                commandName: evidence.command,
                arguments: payload.values
            ) {
            case .success(let normalizedCommand):
                command = normalizedCommand
            case .failure(let error):
                throw FenceError.invalidRequest(
                    "Invalid heist step \(index): \(error.message)"
                )
            }

            self.init(
                command: command,
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

        func requestDecodeInputArguments() -> [String: Any] {
            commandArgumentEnvelope().decodeEdgeRawDictionary()
        }

        func normalizedOperation() -> NormalizedOperation {
            NormalizedOperation(
                command: command,
                arguments: commandArgumentEnvelope()
            )
        }

        private func commandArgumentEnvelope() -> CommandArgumentEnvelope {
            var arguments = payload.values.mapValues(CommandArgumentValue.init)

            if let target {
                if let label = target.label { arguments["label"] = .string(label) }
                if let matchIdentifier = target.identifier { arguments["identifier"] = .string(matchIdentifier) }
                if let matchValue = target.value { arguments["value"] = .string(matchValue) }
                if let matchTraits = target.traits {
                    arguments["traits"] = .array(matchTraits.map { .string($0.rawValue) })
                }
                if let matchExclude = target.excludeTraits {
                    arguments["excludeTraits"] = .array(matchExclude.map { .string($0.rawValue) })
                }
            }
            if let ordinal { arguments["ordinal"] = .int(ordinal) }

            return CommandArgumentEnvelope(values: arguments)
        }
    }

    struct PlaybackPayload: Sendable, Equatable {
        let values: [String: HeistValue]

        init(values: [String: HeistValue]) {
            self.values = values
        }

        subscript(key: String) -> HeistValue? {
            values[key]
        }

    }
}

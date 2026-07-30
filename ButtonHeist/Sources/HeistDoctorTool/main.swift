import ArgumentParser
import Foundation
import HeistDoctorCore
import TheScore

enum HeistDoctorToolOutput {
    static func writeLine(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func writeErrorLine(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

@main
struct HeistDoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "heist-doctor",
        abstract: "Alpha: suggest offline heist target repairs from two HeistResult recordings",
        discussion: """
            heist-doctor is an alpha, suggestion-only offline tool.

            heist-doctor reads canonical HeistResultRecording JSON/JSON.gz
            artifacts, not raw HeistResult or public run_heist JSON. It compares
            a last passing run with a new failing run and prints repair candidates
            for the failed action step. It never connects to an app, reruns a
            heist, edits a plan, or changes playback behavior.

            Examples:
              heist-doctor --last-pass last-pass.json --new-fail new-fail.json
              heist-doctor --last-pass last-pass.json.gz --new-fail new-fail.json.gz
              heist-doctor --last-pass-dir main-results --new-fail-dir pr-results
              heist-doctor --last-pass last-pass.json --new-fail new-fail.json --format json
              heist-doctor --last-pass last-pass.json --new-fail new-fail.json --step-path '$.body[2]'
            """
    )

    @Option(
        name: .long,
        help: "Path to the canonical last-passing HeistResultRecording JSON/JSON.gz artifact."
    )
    var lastPass: String?

    @Option(
        name: .long,
        help: "Path to the canonical new-failing HeistResultRecording JSON/JSON.gz artifact."
    )
    var newFail: String?

    @Option(name: .long, help: "Directory containing passed HeistResultRecording artifacts.")
    var lastPassDir: String?

    @Option(name: .long, help: "Directory containing failed HeistResultRecording artifacts.")
    var newFailDir: String?

    @Option(name: .long, help: "Optional action step path to compare instead of the first failed step.")
    var stepPath: String?

    @Option(name: .long, help: "Output format: human or json.")
    var format: HeistDoctorOutputFormat = .human

    mutating func run() throws {
        let input = try validatedInput()
        let urls: (lastPass: URL, newFail: URL)
        switch input {
        case .files(let lastPass, let newFail):
            urls = (lastPass, newFail)
        case .directories(let lastPass, let newFail):
            let selection = try HeistResultPairSelection.select(
                lastPassDirectory: lastPass,
                newFailDirectory: newFail
            )
            for warning in selection.warnings {
                HeistDoctorToolOutput.writeErrorLine(
                    "Warning: ignoring invalid heist result recording "
                        + "\(warning.recording.path): \(warning.reason)"
                )
            }
            guard case .selected(let lastPass, let newFail, let fingerprint, _) = selection else {
                throw ValidationError(
                    "no doctor-ready result pair found. Need a failed recording and a prior "
                        + "passed recording with the same decoded plan fingerprint."
                )
            }
            HeistDoctorToolOutput.writeLine(
                """
                Selected doctor result pair:
                  fingerprint: \(fingerprint)
                  last pass:   \(lastPass.path)
                  new fail:    \(newFail.path)

                """
            )
            urls = (lastPass, newFail)
        }

        let lastPassResult = try Self.decodeResult(at: urls.lastPass)
        let newFailResult = try Self.decodeResult(at: urls.newFail)
        let requestedStepPath = try stepPath.map(HeistExecutionPath.init(validating:))
        let diagnosis = try HeistDoctor.diagnosis(
            lastPass: lastPassResult,
            newFail: newFailResult,
            stepPath: requestedStepPath
        )

        switch format {
        case .human:
            HeistDoctorToolOutput.writeLine(Self.humanReport(diagnosis))
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(diagnosis)
            guard let json = String(data: data, encoding: .utf8) else {
                throw ValidationError("failed to encode heist-doctor JSON diagnosis")
            }
            HeistDoctorToolOutput.writeLine(json)
        }
    }

    private func validatedInput() throws -> Input {
        switch (lastPass, newFail, lastPassDir, newFailDir) {
        case (.some(let lastPass), .some(let newFail), .none, .none):
            return .files(lastPass: Self.url(for: lastPass), newFail: Self.url(for: newFail))
        case (.none, .none, .some(let lastPass), .some(let newFail)):
            return .directories(lastPass: Self.url(for: lastPass), newFail: Self.url(for: newFail))
        default:
            throw ValidationError(
                "provide exactly one complete input mode: --last-pass with --new-fail, "
                    + "or --last-pass-dir with --new-fail-dir"
            )
        }
    }

    private static func url(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static func decodeResult(at url: URL) throws -> HeistResult {
        do {
            return try HeistResultCodec.decode(contentsOf: url).result
        } catch let error as DecodingError {
            throw ValidationError(
                "failed to decode canonical HeistResultRecording JSON/JSON.gz "
                    + "at \(url.path): \(error)"
            )
        } catch let error as HeistResultCodecError {
            throw ValidationError(
                "failed to decompress canonical HeistResultRecording JSON.gz "
                    + "at \(url.path): \(error)"
            )
        } catch {
            throw ValidationError(
                "failed to read canonical HeistResultRecording JSON/JSON.gz "
                    + "at \(url.path): \(error)"
            )
        }
    }

    private static func humanReport(_ diagnosis: HeistRepairDiagnosis) -> String {
        let suggestions: [HeistRepairSuggestion]
        switch diagnosis {
        case .suggested(let suggested):
            suggestions = suggested.suggestions
        case .refused(let refused):
            return "No repair suggestions (\(refused.refusal.stage.rawValue)/"
                + "\(refused.refusal.reason.rawValue)): \(refused.refusal.message)"
        }

        var lines = ["Repair suggestions (\(suggestions.count))"]
        for (index, suggestion) in suggestions.enumerated() {
            lines.append("")
            lines.append("[\(index + 1)] \(suggestion.failureKind.rawValue) confidence=\(suggestion.confidence.rawValue)")
            lines.append("step: \(suggestion.stepPath)")
            lines.append("old target: \(suggestion.oldTarget)")
            lines.append("new target: \(suggestion.newTarget)")
            lines.append("old element: \(elementEvidenceLine(suggestion.oldResolvedElement))")
            lines.append("new element: \(elementEvidenceLine(suggestion.newResolvedElement))")
            appendSection("reasons", suggestion.reasons.map(\.reportText), to: &lines)
            appendSection("caveats", suggestion.caveats.map(\.reportText), to: &lines)
        }
        return lines.joined(separator: "\n")
    }

    private static func appendSection(
        _ title: String,
        _ values: [String],
        to lines: inout [String]
    ) {
        guard !values.isEmpty else { return }
        lines.append("\(title):")
        lines.append(contentsOf: values.map { "  - \($0)" })
    }

    private static func elementEvidenceLine(_ evidence: HeistRepairElementEvidence) -> String {
        let assertable = evidence.element.semantics.assertable
        let traitSummary = assertable.orderedTraits.map(\.rawValue).joined(separator: ",")
        return [
            assertable.label.map { "label=\"\($0)\"" },
            assertable.value.map { "value=\"\($0)\"" },
            assertable.identifier.map { "identifier=\"\($0)\"" },
            traitSummary.isEmpty ? nil : "traits=\(traitSummary)",
        ].compactMap { $0 }.joined(separator: " ")
    }
}

private enum Input {
    case files(lastPass: URL, newFail: URL)
    case directories(lastPass: URL, newFail: URL)
}

enum HeistDoctorOutputFormat: String, ExpressibleByArgument {
    case human
    case json
}

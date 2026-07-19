import ArgumentParser
import Foundation
import HeistDoctorCore
import TheScore

enum HeistDoctorToolOutput {
    static func writeLine(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

@main
struct HeistDoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "heist-doctor",
        abstract: "Alpha: suggest offline heist target repairs from two execution results",
        discussion: """
            heist-doctor is an alpha, suggestion-only offline tool.

            heist-doctor reads durable HeistResult JSON results. It
            compares a last passing run with a new failing run and prints repair
            candidates for the failed action step. It never connects to an app,
            reruns a heist, edits a plan, or changes playback behavior.
            Result inputs may be plain JSON or gzip-compressed JSON.

            Examples:
              heist-doctor --last-pass last-pass.json --new-fail new-fail.json
              heist-doctor --last-pass last-pass.json.gz --new-fail new-fail.json.gz
              heist-doctor --last-pass last-pass.json --new-fail new-fail.json --format json
              heist-doctor --last-pass last-pass.json --new-fail new-fail.json --step-path '$.body[2]'
            """
    )

    @Option(name: .long, help: "Path to the last passing HeistResult JSON or JSON.gz result.")
    var lastPass: String

    @Option(name: .long, help: "Path to the new failing HeistResult JSON or JSON.gz result.")
    var newFail: String

    @Option(name: .long, help: "Optional action step path to compare instead of the first failed step.")
    var stepPath: String?

    @Option(name: .long, help: "Output format: human or json.")
    var format: HeistDoctorOutputFormat = .human

    mutating func run() throws {
        let lastPassResult = try Self.decodeResult(at: lastPass)
        let newFailResult = try Self.decodeResult(at: newFail)
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

    private static func decodeResult(at path: String) throws -> HeistResult {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            return try HeistResultCodec.decode(contentsOf: url)
        } catch let error as DecodingError {
            throw ValidationError("failed to decode HeistResult at \(path): \(error)")
        } catch let error as HeistResultCodecError {
            throw ValidationError("failed to decompress HeistResult at \(path): \(error)")
        } catch {
            throw ValidationError("failed to read result at \(path): \(error)")
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
        let element = evidence.element
        let traitSummary = element.traits.map(\.rawValue).joined(separator: ",")
        return [
            element.label.map { "label=\"\($0)\"" },
            element.value.map { "value=\"\($0)\"" },
            element.identifier.map { "identifier=\"\($0)\"" },
            traitSummary.isEmpty ? nil : "traits=\(traitSummary)",
        ].compactMap { $0 }.joined(separator: " ")
    }
}

enum HeistDoctorOutputFormat: String, ExpressibleByArgument {
    case human
    case json
}

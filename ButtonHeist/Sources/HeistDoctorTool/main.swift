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
        abstract: "Alpha: suggest offline heist target repairs from two execution receipts",
        discussion: """
            heist-doctor is an alpha, suggestion-only offline tool.

            heist-doctor reads durable HeistExecutionResult JSON receipts. It
            compares a last passing run with a new failing run and prints repair
            candidates for the failed action step. It never connects to an app,
            reruns a heist, edits a plan, or changes playback behavior.
            Receipt inputs may be plain JSON or gzip-compressed JSON.

            Examples:
              heist-doctor --last-pass last-pass.json --new-fail new-fail.json
              heist-doctor --last-pass last-pass.json.gz --new-fail new-fail.json.gz
              heist-doctor --last-pass last-pass.json --new-fail new-fail.json --format json
              heist-doctor --last-pass last-pass.json --new-fail new-fail.json --step-path '$.body[2]'
            """
    )

    @Option(name: .long, help: "Path to the last passing HeistExecutionResult JSON or JSON.gz receipt.")
    var lastPass: String

    @Option(name: .long, help: "Path to the new failing HeistExecutionResult JSON or JSON.gz receipt.")
    var newFail: String

    @Option(name: .long, help: "Optional action step path to compare instead of the first failed step.")
    var stepPath: String?

    @Option(name: .long, help: "Output format: human or json.")
    var format: HeistDoctorOutputFormat = .human

    mutating func run() throws {
        let lastPassReceipt = try Self.decodeReceipt(at: lastPass)
        let newFailReceipt = try Self.decodeReceipt(at: newFail)
        let suggestions = try HeistDoctor.suggestions(
            lastPass: lastPassReceipt,
            newFail: newFailReceipt,
            stepPath: stepPath
        )

        switch format {
        case .human:
            HeistDoctorToolOutput.writeLine(Self.humanReport(suggestions))
        case .json:
            let report = HeistDoctorReport(suggestions: suggestions)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            guard let json = String(data: data, encoding: .utf8) else {
                throw ValidationError("failed to encode heist-doctor JSON report")
            }
            HeistDoctorToolOutput.writeLine(json)
        }
    }

    private static func decodeReceipt(at path: String) throws -> HeistExecutionResult {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            return try HeistReceiptCodec.decode(contentsOf: url)
        } catch let error as DecodingError {
            throw ValidationError("failed to decode HeistExecutionResult at \(path): \(error)")
        } catch let error as HeistReceiptCodecError {
            throw ValidationError("failed to decompress HeistExecutionResult at \(path): \(error)")
        } catch {
            throw ValidationError("failed to read receipt at \(path): \(error)")
        }
    }

    private static func humanReport(_ suggestions: [HeistRepairSuggestion]) -> String {
        guard !suggestions.isEmpty else {
            return "No repair suggestions."
        }

        var lines = ["Repair suggestions (alpha, \(suggestions.count))"]
        for (index, suggestion) in suggestions.enumerated() {
            lines.append("")
            lines.append("[\(index + 1)] \(suggestion.failureKind.rawValue) confidence=\(suggestion.confidence.rawValue)")
            lines.append("step: \(suggestion.stepPath)")
            lines.append("old target: \(suggestion.oldTarget)")
            lines.append("new target: \(suggestion.newTarget)")
            lines.append("old element: \(elementSummaryLine(suggestion.oldResolvedElement))")
            lines.append("new element: \(elementSummaryLine(suggestion.newResolvedElement))")
            appendSection("reasons", suggestion.reasons, to: &lines)
            appendSection("caveats", suggestion.caveats, to: &lines)
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

    private static func elementSummaryLine(_ element: ElementSummary) -> String {
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

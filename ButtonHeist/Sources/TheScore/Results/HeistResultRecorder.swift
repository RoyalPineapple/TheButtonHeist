import CryptoKit
import Foundation
import OSLog
import ThePlans

private let heistResultLogger = ButtonHeistLog.logger(.score(.results))

public enum HeistResultRecordingMode: String, Sendable, Equatable {
    case off
    case failures
    case all

    public init?(environmentValue: String?) {
        guard let environmentValue = environmentValue?.nilIfBlank else {
            self = .failures
            return
        }
        guard let mode = Self(rawValue: environmentValue) else { return nil }
        self = mode
    }

    func shouldRecord(_ result: HeistResult) -> Bool {
        switch (self, result.outcome) {
        case (.off, _):
            return false
        case (.failures, .failed):
            return true
        case (.failures, .passed):
            return false
        case (.all, _):
            return true
        }
    }
}

public struct HeistResultRecordingConfiguration: Sendable, Equatable {
    public static let processTemporaryDirectoryValue = "process-temporary-directory"

    public let rootDirectory: URL
    public let mode: HeistResultRecordingMode

    public init(
        rootDirectory: URL,
        mode: HeistResultRecordingMode = .failures
    ) {
        self.rootDirectory = rootDirectory
        self.mode = mode
    }

    public static var environment: HeistResultRecordingConfiguration? {
        guard let directory = EnvironmentKey.buttonheistResultsDir.value?.nilIfBlank else {
            return nil
        }
        guard let mode = HeistResultRecordingMode(environmentValue: EnvironmentKey.buttonheistResultsMode.value) else {
            return nil
        }
        return HeistResultRecordingConfiguration(rootDirectory: rootDirectory(for: directory), mode: mode)
    }

    private static func rootDirectory(for value: String) -> URL {
        switch value {
        case processTemporaryDirectoryValue:
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("buttonheist-results", isDirectory: true)
        default:
            let expandedDirectory = (value as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expandedDirectory, isDirectory: true)
        }
    }
}

public struct HeistResultRecording: Sendable, Equatable {
    public let url: URL
    public let heistName: HeistPlanName?
    public let fingerprint: String
}

public enum HeistResultRecorder {
    @discardableResult
    public static func recordIfEnabled(
        _ result: HeistResult,
        plan: HeistPlan
    ) -> HeistResultRecording? {
        guard let configuration = HeistResultRecordingConfiguration.environment else {
            return nil
        }
        do {
            return try write(result, plan: plan, configuration: configuration)
        } catch {
            heistResultLogger.warning("Failed to record heist result: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    public static func write(
        _ result: HeistResult,
        plan: HeistPlan,
        configuration: HeistResultRecordingConfiguration
    ) throws -> HeistResultRecording? {
        guard configuration.mode.shouldRecord(result) else {
            return nil
        }

        let fingerprint = try heistFingerprint(for: plan)
        let directory = configuration.rootDirectory
            .appendingPathComponent(directoryName(name: plan.name, fingerprint: fingerprint), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(fileName(for: result), isDirectory: false)
        try HeistResultCodec.write(result, to: url)
        return HeistResultRecording(
            url: url,
            heistName: plan.name,
            fingerprint: fingerprint
        )
    }

    public static func heistFingerprint(for plan: HeistPlan) throws -> String {
        let data = try plan.canonicalHeistJSONData()
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func directoryName(name: HeistPlanName?, fingerprint: String) -> String {
        "\(slug(name?.description ?? "unnamed-heist"))-\(fingerprint)"
    }

    private static func fileName(for result: HeistResult) -> String {
        let outcome = switch result.outcome {
        case .passed: "passed"
        case .failed: "failed"
        }
        return "\(timestamp())-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)-\(outcome).json.gz"
    }

    private static func timestamp(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: date)
    }

    private static func slug(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .lowercased()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "unnamed-heist" : collapsed
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

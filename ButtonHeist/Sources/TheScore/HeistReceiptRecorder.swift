import CryptoKit
import Foundation
import OSLog
import ThePlans

private let heistReceiptLogger = Logger(subsystem: "com.buttonheist.thescore", category: "receipts")

public enum HeistReceiptRecordingMode: String, Sendable, Equatable {
    case off
    case failures
    case failingAndPassing = "failing-and-passing"
    case all

    public init(environmentValue: String?) {
        switch environmentValue?.lowercased() {
        case "off", "false", "0", "no":
            self = .off
        case "all", "always":
            self = .all
        case "passing-and-failing", "failing-and-passing":
            self = .failingAndPassing
        case "failures", "failure", "failing", "failed", nil:
            self = .failures
        default:
            self = .failures
        }
    }

    func shouldRecord(_ status: HeistReceiptRecordingStatus) -> Bool {
        switch (self, status) {
        case (.off, _):
            return false
        case (.failures, .failed):
            return true
        case (.failures, .passed):
            return false
        case (.failingAndPassing, _), (.all, _):
            return true
        }
    }
}

public struct HeistReceiptRecordingConfiguration: Sendable, Equatable {
    public static let processTemporaryDirectoryValue = "process-temporary-directory"

    public let rootDirectory: URL
    public let mode: HeistReceiptRecordingMode

    public init(
        rootDirectory: URL,
        mode: HeistReceiptRecordingMode = .failures
    ) {
        self.rootDirectory = rootDirectory
        self.mode = mode
    }

    public static var environment: HeistReceiptRecordingConfiguration? {
        guard let directory = EnvironmentKey.buttonheistReceiptsDir.value?.nilIfBlank else {
            return nil
        }
        return HeistReceiptRecordingConfiguration(
            rootDirectory: rootDirectory(for: directory),
            mode: HeistReceiptRecordingMode(environmentValue: EnvironmentKey.buttonheistReceiptsMode.value)
        )
    }

    private static func rootDirectory(for value: String) -> URL {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case processTemporaryDirectoryValue, "temporary-directory", "__tmp__":
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("buttonheist-receipts", isDirectory: true)
        default:
            let expandedDirectory = (value as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expandedDirectory, isDirectory: true)
        }
    }
}

public enum HeistReceiptRecordingStatus: String, Sendable, Equatable {
    case passed
    case failed
}

public struct HeistReceiptRecording: Sendable, Equatable {
    public let url: URL
    public let status: HeistReceiptRecordingStatus
    public let heistName: String?
    public let fingerprint: String
}

public enum HeistReceiptRecorder {
    @discardableResult
    public static func recordIfEnabled(
        _ result: HeistExecutionResult,
        plan: HeistPlan
    ) -> HeistReceiptRecording? {
        guard let configuration = HeistReceiptRecordingConfiguration.environment else {
            return nil
        }
        do {
            return try write(result, plan: plan, configuration: configuration)
        } catch {
            heistReceiptLogger.warning("Failed to record heist receipt: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    public static func write(
        _ result: HeistExecutionResult,
        plan: HeistPlan,
        configuration: HeistReceiptRecordingConfiguration
    ) throws -> HeistReceiptRecording? {
        let status: HeistReceiptRecordingStatus = result.isFailure ? .failed : .passed
        guard configuration.mode.shouldRecord(status) else {
            return nil
        }

        let fingerprint = try heistFingerprint(for: plan)
        let directory = configuration.rootDirectory
            .appendingPathComponent(directoryName(name: plan.name, fingerprint: fingerprint), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(fileName(status: status), isDirectory: false)
        try HeistReceiptCodec.write(result, to: url)
        return HeistReceiptRecording(
            url: url,
            status: status,
            heistName: plan.name,
            fingerprint: fingerprint
        )
    }

    public static func heistFingerprint(for plan: HeistPlan) throws -> String {
        let data = try plan.canonicalHeistJSONData()
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func directoryName(name: String?, fingerprint: String) -> String {
        "\(slug(name ?? "unnamed-heist"))-\(fingerprint)"
    }

    private static func fileName(status: HeistReceiptRecordingStatus) -> String {
        "\(timestamp())-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)-\(status.rawValue).json.gz"
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

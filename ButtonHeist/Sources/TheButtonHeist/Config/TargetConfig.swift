import Foundation
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "config")

/// A named connection target: device address + optional auth token.
public struct TargetConfig: Codable, Sendable, Equatable {
    public let device: String
    public let token: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case device
        case token
    }

    public init(device: String, token: String? = nil) {
        self.device = device
        self.token = token
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownFields(allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        device = try container.decode(String.self, forKey: .device)
        token = try container.decodeIfPresent(String.self, forKey: .token)
    }
}

/// Config file schema for `.buttonheist.json` or `~/.config/buttonheist/config.json`.
/// Contains named targets and an optional default.
struct ButtonHeistFileConfig: Codable, Sendable, Equatable {
    let targets: [String: TargetConfig]
    let defaultTarget: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case targets
        case defaultTarget = "default"
    }

    init(targets: [String: TargetConfig], defaultTarget: String? = nil) {
        self.targets = targets
        self.defaultTarget = defaultTarget
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownFields(allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targets = try container.decode([String: TargetConfig].self, forKey: .targets)
        defaultTarget = try container.decodeIfPresent(String.self, forKey: .defaultTarget)
    }
}

/// Diagnostic failure produced when a config path cannot be loaded.
public struct TargetConfigLoadError: Error, LocalizedError, Sendable {
    /// High-level loading phase that failed.
    public enum Kind: String, Sendable {
        case readFailed = "read_failed"
        case decodeFailed = "decode_failed"

        /// Stable diagnostic error code for this load failure kind.
        public var errorCode: String {
            switch self {
            case .readFailed:
                return "config.read_failed"
            case .decodeFailed:
                return "config.decode_failed"
            }
        }
    }

    /// Expanded filesystem path that failed to load.
    public let path: String
    /// Load failure kind used for diagnostics and machine-readable error codes.
    public let kind: Kind
    /// Human-readable description of the underlying file or JSON error.
    public let underlyingDescription: String

    /// User-facing diagnostic message.
    public var errorDescription: String? {
        switch kind {
        case .readFailed:
            return "Failed to read config at \(path): \(underlyingDescription)"
        case .decodeFailed:
            return "Failed to decode config at \(path): \(underlyingDescription)"
        }
    }

    /// Machine-readable failure metadata for formatted diagnostics.
    public var failureDetails: FailureDetails {
        FailureDetails(
            errorCode: kind.errorCode,
            phase: .setup,
            retryable: false,
            hint: "Verify the config path points to a readable JSON file matching the Button Heist config schema."
        )
    }
}

/// Resolves connection parameters from config files and environment variables.
/// Resolution order: env vars > config file targets.
enum TargetConfigResolver {

    /// Standard search paths for the config file, in priority order.
    static let searchPaths: [String] = [
        ".buttonheist.json",
        "~/.config/buttonheist/config.json",
    ]

    /// Load and parse the first config file found in the provided default search paths.
    static func loadConfig(searchPaths paths: [String]) throws -> ButtonHeistFileConfig? {
        for path in paths {
            let url = configURL(for: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw TargetConfigLoadError(
                    path: url.path,
                    kind: .readFailed,
                    underlyingDescription: error.localizedDescription
                )
            }
            let config: ButtonHeistFileConfig
            do {
                config = try JSONDecoder().decode(ButtonHeistFileConfig.self, from: data)
            } catch {
                logger.error("Failed to decode config \(url.path): \(error)")
                throw TargetConfigLoadError(
                    path: url.path,
                    kind: .decodeFailed,
                    underlyingDescription: error.localizedDescription
                )
            }
            return config
        }
        return nil
    }

    /// Load and parse a user-provided config path.
    static func loadConfig(from explicitPath: String) throws -> ButtonHeistFileConfig {
        let url = configURL(for: explicitPath)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TargetConfigLoadError(
                path: url.path,
                kind: .readFailed,
                underlyingDescription: error.localizedDescription
            )
        }

        do {
            return try JSONDecoder().decode(ButtonHeistFileConfig.self, from: data)
        } catch {
            throw TargetConfigLoadError(
                path: url.path,
                kind: .decodeFailed,
                underlyingDescription: error.localizedDescription
            )
        }
    }

    /// Resolve connection parameters with full precedence:
    /// 1. Env vars (BUTTONHEIST_DEVICE / BUTTONHEIST_TOKEN) override everything
    /// 2. Named target from config file
    /// 3. Default target from config file
    static func resolveEffective(
        targetName: String? = nil,
        config: ButtonHeistFileConfig? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> TargetConfig? {
        let envDevice = env[EnvironmentKey.buttonheistDevice.rawValue]
        let envToken = env[EnvironmentKey.buttonheistToken.rawValue]

        if let envDevice {
            return TargetConfig(device: envDevice, token: envToken)
        }

        guard let config else { return nil }

        let name = targetName ?? config.defaultTarget
        guard let name else { return nil }

        guard var target = config.targets[name] else { return nil }

        if let envToken {
            target = TargetConfig(device: target.device, token: envToken)
        }
        return target
    }

    private static func configURL(for path: String) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded)
    }
}

private struct UnknownConfigField: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension Decoder {
    func rejectUnknownFields<K: CodingKey & CaseIterable>(allowed: K.Type) throws where K.AllCases: Collection {
        let allowedNames = Set(allowed.allCases.map(\.stringValue))
        let container = try container(keyedBy: UnknownConfigField.self)
        if let unknown = container.allKeys.first(where: { !allowedNames.contains($0.stringValue) }) {
            throw DecodingError.dataCorruptedError(
                forKey: unknown,
                in: container,
                debugDescription: "Unknown config field \"\(unknown.stringValue)\""
            )
        }
    }
}

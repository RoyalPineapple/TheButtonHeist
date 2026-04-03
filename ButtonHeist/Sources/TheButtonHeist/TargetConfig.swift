import Foundation
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "config")

/// A named connection target: device address + optional auth token.
public struct TargetConfig: Codable, Sendable, Equatable {
    public let device: String
    public let token: String?

    public init(device: String, token: String? = nil) {
        self.device = device
        self.token = token
    }
}

/// Config file schema for `.buttonheist.json` or `~/.config/buttonheist/config.json`.
/// Contains named targets and an optional default.
public struct ButtonHeistFileConfig: Codable, Sendable, Equatable {
    public let targets: [String: TargetConfig]
    public let defaultTarget: String?

    enum CodingKeys: String, CodingKey {
        case targets
        case defaultTarget = "default"
    }

    public init(targets: [String: TargetConfig], defaultTarget: String? = nil) {
        self.targets = targets
        self.defaultTarget = defaultTarget
    }
}

/// Resolves connection parameters from config files and environment variables.
/// Resolution order: env vars > config file targets.
public enum TargetConfigResolver {

    /// Standard search paths for the config file, in priority order.
    static let searchPaths: [String] = [
        ".buttonheist.json",
        "~/.config/buttonheist/config.json",
    ]

    /// Load and parse the first config file found in the search paths.
    public static func loadConfig(from explicitPath: String? = nil) -> ButtonHeistFileConfig? {
        let paths: [String]
        if let explicitPath {
            paths = [explicitPath]
        } else {
            paths = searchPaths
        }

        let fm = FileManager.default
        for path in paths {
            let expanded = NSString(string: path).expandingTildeInPath
            let url: URL
            if expanded.hasPrefix("/") {
                url = URL(fileURLWithPath: expanded)
            } else {
                url = URL(fileURLWithPath: fm.currentDirectoryPath)
                    .appendingPathComponent(expanded)
            }

            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                if explicitPath != nil {
                    logger.error("Failed to read config at \(url.path): \(error)")
                }
                continue
            }
            let config: ButtonHeistFileConfig
            do {
                config = try JSONDecoder().decode(ButtonHeistFileConfig.self, from: data)
            } catch {
                logger.warning("Skipping malformed config \(url.path): \(error)")
                continue
            }
            return config
        }
        return nil
    }

    /// Resolve a named target from the config file.
    public static func resolve(
        targetName: String,
        config: ButtonHeistFileConfig
    ) -> TargetConfig? {
        config.targets[targetName]
    }

    /// Resolve connection parameters with full precedence:
    /// 1. Env vars (BUTTONHEIST_DEVICE / BUTTONHEIST_TOKEN) override everything
    /// 2. Named target from config file
    /// 3. Default target from config file
    public static func resolveEffective(
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
}

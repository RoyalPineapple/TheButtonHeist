import Foundation

/// Resolved configuration from environment variables, config files, and explicit overrides.
/// Use `resolve()` to build this from the current environment, then access `.fenceConfiguration`
/// to create a `TheFence`.
public struct EnvironmentConfig: Sendable {
    public let deviceFilter: String?
    public let token: String?
    public let driverId: String?
    public let sessionTimeout: TimeInterval
    public let connectionTimeout: TimeInterval
    public let fileConfig: ButtonHeistFileConfig?
    public let autoReconnect: Bool

    /// Build a `TheFence.Configuration` from this resolved config.
    public var fenceConfiguration: TheFence.Configuration {
        .init(
            deviceFilter: deviceFilter,
            connectionTimeout: connectionTimeout,
            token: token,
            autoReconnect: autoReconnect,
            fileConfig: fileConfig
        )
    }

    /// Resolve configuration with full precedence:
    /// 1. Explicit parameters (from CLI flags, etc.) — highest priority
    /// 2. Environment variables (`BUTTONHEIST_DEVICE`, `BUTTONHEIST_TOKEN`, etc.)
    /// 3. Config file (`.buttonheist.json` or `~/.config/buttonheist/config.json`)
    /// 4. Built-in defaults — lowest priority
    public static func resolve(
        deviceFilter: String? = nil,
        token: String? = nil,
        driverId: String? = nil,
        sessionTimeout: Double? = nil,
        connectionTimeout: Double? = nil,
        autoReconnect: Bool = true,
        configPath: String? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> EnvironmentConfig {
        let fileConfig = TargetConfigResolver.loadConfig(from: configPath)

        let resolvedDevice = deviceFilter ?? env["BUTTONHEIST_DEVICE"]
        let resolvedToken = token ?? env["BUTTONHEIST_TOKEN"]
        let resolvedDriverId = driverId ?? env["BUTTONHEIST_DRIVER_ID"]

        let resolvedSessionTimeout: TimeInterval
        if let explicit = sessionTimeout, explicit > 0 {
            resolvedSessionTimeout = explicit
        } else if let envStr = env["BUTTONHEIST_SESSION_TIMEOUT"],
                  let parsed = Double(envStr), parsed > 0 {
            resolvedSessionTimeout = parsed
        } else {
            resolvedSessionTimeout = 60.0
        }

        let resolvedConnectionTimeout = connectionTimeout ?? 30.0

        return EnvironmentConfig(
            deviceFilter: resolvedDevice,
            token: resolvedToken,
            driverId: resolvedDriverId,
            sessionTimeout: resolvedSessionTimeout,
            connectionTimeout: resolvedConnectionTimeout,
            fileConfig: fileConfig,
            autoReconnect: autoReconnect
        )
    }
}

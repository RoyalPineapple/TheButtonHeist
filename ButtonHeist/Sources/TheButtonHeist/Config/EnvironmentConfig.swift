import Foundation
import TheScore

/// Typed client environment projection used by configuration resolution.
public struct ButtonHeistEnvironment: Equatable, Sendable {
    public static let empty = ButtonHeistEnvironment()

    private let values: [EnvironmentKey: String]

    public init(
        device: String? = nil,
        token: String? = nil,
        sessionTimeout: String? = nil,
        connectionTimeout: String? = nil
    ) {
        var values: [EnvironmentKey: String] = [:]
        values[.buttonheistDevice] = device
        values[.buttonheistToken] = token
        values[.buttonheistSessionTimeout] = sessionTimeout
        values[.buttonheistConnectionTimeout] = connectionTimeout
        self.values = values
    }

    fileprivate init(rawValues: [String: String]) {
        self.values = Dictionary(uniqueKeysWithValues: [
            EnvironmentKey.buttonheistDevice,
            .buttonheistToken,
            .buttonheistSessionTimeout,
            .buttonheistConnectionTimeout,
        ].compactMap { key in
            rawValues[key.rawValue].map { (key, $0) }
        })
    }

    var device: String? {
        values[.buttonheistDevice]
    }

    var token: String? {
        values[.buttonheistToken]
    }

    var sessionTimeout: String? {
        values[.buttonheistSessionTimeout]
    }

    var connectionTimeout: String? {
        values[.buttonheistConnectionTimeout]
    }
}

/// Foundation bridge for capturing the current process environment.
public enum ButtonHeistEnvironmentBridge {
    public static func current() -> ButtonHeistEnvironment {
        ButtonHeistEnvironment(rawValues: ProcessInfo.processInfo.environment)
    }
}

/// Resolved configuration from environment variables, config files, and explicit overrides.
/// Use `resolve()` to build this from the current environment, then access `.fenceConfiguration`
/// to create a `TheFence`.
public struct EnvironmentConfig: Sendable {
    public let deviceFilter: String?
    let token: String?
    public let sessionTimeout: TimeInterval
    let connectionTimeout: TimeInterval
    let fileConfig: ButtonHeistFileConfig?
    let directDevice: DiscoveredDevice?
    let autoReconnect: Bool

    /// Build a `TheFence.Configuration` from this resolved config.
    public var fenceConfiguration: TheFence.Configuration {
        .init(
            deviceFilter: deviceFilter,
            connectionTimeout: connectionTimeout,
            token: token,
            autoReconnect: autoReconnect,
            fileConfig: fileConfig,
            directDevice: directDevice
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
        sessionTimeout: TimeInterval? = nil,
        connectionTimeout: TimeInterval? = nil,
        autoReconnect: Bool = true,
        environment: ButtonHeistEnvironment = ButtonHeistEnvironmentBridge.current()
    ) throws -> EnvironmentConfig {
        resolve(
            deviceFilter: deviceFilter,
            token: token,
            sessionTimeout: sessionTimeout,
            connectionTimeout: connectionTimeout,
            autoReconnect: autoReconnect,
            fileConfig: try TargetConfigResolver.loadConfig(searchPaths: TargetConfigResolver.searchPaths),
            environment: environment
        )
    }

    /// Resolve configuration with an optional config path from a caller-owned source.
    /// A nil path uses the default search paths; a non-nil path is an explicit config path.
    public static func resolve(
        deviceFilter: String? = nil,
        token: String? = nil,
        sessionTimeout: TimeInterval? = nil,
        connectionTimeout: TimeInterval? = nil,
        autoReconnect: Bool = true,
        configPath: String?,
        environment: ButtonHeistEnvironment = ButtonHeistEnvironmentBridge.current()
    ) throws -> EnvironmentConfig {
        guard let configPath else {
            return try resolve(
                deviceFilter: deviceFilter,
                token: token,
                sessionTimeout: sessionTimeout,
                connectionTimeout: connectionTimeout,
                autoReconnect: autoReconnect,
                environment: environment
            )
        }
        return try resolve(
            deviceFilter: deviceFilter,
            token: token,
            sessionTimeout: sessionTimeout,
            connectionTimeout: connectionTimeout,
            autoReconnect: autoReconnect,
            configPath: configPath,
            environment: environment
        )
    }

    /// Resolve configuration with an explicit user-provided config path.
    /// Missing or malformed explicit config files are diagnostic failures, not
    /// alternate config searches.
    public static func resolve(
        deviceFilter: String? = nil,
        token: String? = nil,
        sessionTimeout: TimeInterval? = nil,
        connectionTimeout: TimeInterval? = nil,
        autoReconnect: Bool = true,
        configPath: String,
        environment: ButtonHeistEnvironment = ButtonHeistEnvironmentBridge.current()
    ) throws -> EnvironmentConfig {
        let fileConfig = try TargetConfigResolver.loadConfig(from: configPath)
        return resolve(
            deviceFilter: deviceFilter,
            token: token,
            sessionTimeout: sessionTimeout,
            connectionTimeout: connectionTimeout,
            autoReconnect: autoReconnect,
            fileConfig: fileConfig,
            environment: environment
        )
    }

    static func resolve(
        deviceFilter: String?,
        token: String?,
        sessionTimeout: TimeInterval?,
        connectionTimeout: TimeInterval?,
        autoReconnect: Bool,
        fileConfig: ButtonHeistFileConfig?,
        environment: ButtonHeistEnvironment
    ) -> EnvironmentConfig {

        let envDevice = environment.device
        let envToken = environment.token
        let configTarget = TargetConfigResolver.resolveEffective(config: fileConfig, environment: environment)

        let resolvedDevice: String?
        let resolvedToken: String?
        let directDevice: DiscoveredDevice?
        if let explicitOrEnvDevice = deviceFilter ?? envDevice {
            resolvedDevice = explicitOrEnvDevice
            resolvedToken = token ?? envToken
            directDevice = nil
        } else if let configTarget {
            resolvedDevice = configTarget.device
            resolvedToken = token ?? configTarget.token
            directDevice = DiscoveredDevice.fromHostPort(
                configTarget.device,
                id: "config-\(fileConfig?.defaultTarget ?? configTarget.device)",
                name: fileConfig?.defaultTarget
            )
        } else {
            resolvedDevice = nil
            resolvedToken = token ?? envToken
            directDevice = nil
        }

        let resolvedSessionTimeout: TimeInterval
        if let explicit = sessionTimeout, explicit > 0 {
            resolvedSessionTimeout = explicit
        } else if let envStr = environment.sessionTimeout,
                  let parsed = Double(envStr), parsed > 0 {
            resolvedSessionTimeout = parsed
        } else {
            resolvedSessionTimeout = 60.0
        }

        let resolvedConnectionTimeout: TimeInterval
        if let explicit = connectionTimeout, explicit > 0 {
            resolvedConnectionTimeout = explicit
        } else if let envStr = environment.connectionTimeout,
                  let parsed = Double(envStr), parsed > 0 {
            resolvedConnectionTimeout = parsed
        } else {
            resolvedConnectionTimeout = 30.0
        }

        return EnvironmentConfig(
            deviceFilter: resolvedDevice,
            token: resolvedToken,
            sessionTimeout: resolvedSessionTimeout,
            connectionTimeout: resolvedConnectionTimeout,
            fileConfig: fileConfig,
            directDevice: directDevice,
            autoReconnect: autoReconnect
        )
    }
}

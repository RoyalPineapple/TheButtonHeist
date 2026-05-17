#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

enum StartupConfigurationSource: String, Sendable {
    case api
    case environment
    case infoPlist
    case defaultValue = "default"
    case generated

    var label: String {
        switch self {
        case .api:
            return "api"
        case .environment:
            return "environment"
        case .infoPlist:
            return "Info.plist"
        case .defaultValue:
            return "default"
        case .generated:
            return "generated"
        }
    }
}

struct ResolvedStartupValue<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let source: StartupConfigurationSource
}

enum StartupConfigurationWarning: Equatable, Sendable {
    case emptyValueIgnored(key: String, source: StartupConfigurationSource)
    case invalidValueIgnored(key: String, source: StartupConfigurationSource, value: String)

    var message: String {
        switch self {
        case .emptyValueIgnored(let key, let source):
            return "Ignoring empty \(key) from \(source.label)"
        case .invalidValueIgnored(let key, let source, let value):
            return "Ignoring invalid \(key) from \(source.label): \(value)"
        }
    }
}

enum StartupInfoPlistKey: String {
    case disableAutoStart = "InsideJobDisableAutoStart"
    case token = "InsideJobToken"
    case instanceId = "InsideJobInstanceId"
    case pollingInterval = "InsideJobPollingInterval"
    case port = "InsideJobPort"
    case scope = "InsideJobScope"
    case sessionTimeout = "InsideJobSessionTimeout"
}

struct StartupConfiguration: Equatable, Sendable {
    static let defaultPollingInterval: TimeInterval = 1.0
    static let minimumPollingInterval: TimeInterval = 0.5
    static let defaultSessionTimeout: TimeInterval = 30.0
    static let minimumSessionTimeout: TimeInterval = 1.0
    static let maximumSessionTimeout: TimeInterval = 3600.0

    let disableAutoStart: ResolvedStartupValue<Bool>
    let token: ResolvedStartupValue<String?>
    let instanceId: ResolvedStartupValue<String?>
    let preferredPort: ResolvedStartupValue<UInt16>
    let pollingInterval: ResolvedStartupValue<TimeInterval>
    let allowedScopes: ResolvedStartupValue<Set<ConnectionScope>>
    let sessionTimeout: ResolvedStartupValue<TimeInterval>
    let warnings: [StartupConfigurationWarning]

    static func resolve(
        env: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> StartupConfiguration {
        var warnings: [StartupConfigurationWarning] = []
        let plist = infoDictionary ?? [:]
        let disableAutoStart = resolveBool(
            envKey: .insideJobDisable,
            plistKey: .disableAutoStart,
            defaultValue: false,
            env: env,
            plist: plist,
            warnings: &warnings
        )
        let token = resolveString(
            envKey: .insideJobToken,
            plistKey: .token,
            env: env,
            plist: plist,
            fallbackSource: .generated,
            warnings: &warnings
        )
        let instanceId = resolveString(
            envKey: .insideJobId,
            plistKey: .instanceId,
            env: env,
            plist: plist,
            fallbackSource: .generated,
            warnings: &warnings
        )
        let preferredPort = resolvePort(env: env, plist: plist, warnings: &warnings)
        let pollingInterval = resolveTimeInterval(
            envKey: .insideJobPollingInterval,
            plistKey: .pollingInterval,
            defaultValue: defaultPollingInterval,
            clamp: { max(minimumPollingInterval, $0) },
            env: env,
            plist: plist,
            warnings: &warnings
        )
        let allowedScopes = resolveAllowedScopes(env: env, plist: plist, warnings: &warnings)
        let sessionTimeout = resolveTimeInterval(
            envKey: .insideJobSessionTimeout,
            plistKey: .sessionTimeout,
            defaultValue: defaultSessionTimeout,
            clamp: { min(max(minimumSessionTimeout, $0), maximumSessionTimeout) },
            env: env,
            plist: plist,
            warnings: &warnings
        )

        return StartupConfiguration(
            disableAutoStart: disableAutoStart,
            token: token,
            instanceId: instanceId,
            preferredPort: preferredPort,
            pollingInterval: pollingInterval,
            allowedScopes: allowedScopes,
            sessionTimeout: sessionTimeout,
            warnings: warnings
        )
    }

    private static func resolveString(
        envKey: EnvironmentKey,
        plistKey: StartupInfoPlistKey,
        env: [String: String],
        plist: [String: Any],
        fallbackSource: StartupConfigurationSource,
        warnings: inout [StartupConfigurationWarning]
    ) -> ResolvedStartupValue<String?> {
        if let envValue = env[envKey.rawValue] {
            if !envValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ResolvedStartupValue(value: envValue, source: .environment)
            }
            warnings.append(.emptyValueIgnored(key: envKey.rawValue, source: .environment))
        }

        if let plistValue = plist[plistKey.rawValue] as? String {
            if !plistValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ResolvedStartupValue(value: plistValue, source: .infoPlist)
            }
            warnings.append(.emptyValueIgnored(key: plistKey.rawValue, source: .infoPlist))
        }

        return ResolvedStartupValue(value: nil, source: fallbackSource)
    }

    private static func resolvePort(
        env: [String: String],
        plist: [String: Any],
        warnings: inout [StartupConfigurationWarning]
    ) -> ResolvedStartupValue<UInt16> {
        if let envValue = env[EnvironmentKey.insideJobPort.rawValue] {
            if let parsed = parsePort(envValue) {
                return ResolvedStartupValue(value: parsed, source: .environment)
            }
            warnings.append(.invalidValueIgnored(
                key: EnvironmentKey.insideJobPort.rawValue,
                source: .environment,
                value: envValue
            ))
        }

        if let plistValue = plist[StartupInfoPlistKey.port.rawValue],
           let parsed = parsePort(plistValue) {
            return ResolvedStartupValue(value: parsed, source: .infoPlist)
        } else if let plistValue = plist[StartupInfoPlistKey.port.rawValue] {
            warnings.append(.invalidValueIgnored(
                key: StartupInfoPlistKey.port.rawValue,
                source: .infoPlist,
                value: String(describing: plistValue)
            ))
        }

        return ResolvedStartupValue(value: 0, source: .defaultValue)
    }

    private static func parsePort(_ value: Any) -> UInt16? {
        if let string = value as? String {
            return UInt16(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let int = value as? Int, int >= 0, int <= Int(UInt16.max) {
            return UInt16(int)
        }
        if let double = value as? Double,
           double.rounded(.towardZero) == double,
           double >= 0,
           double <= Double(UInt16.max) {
            return UInt16(double)
        }
        return nil
    }

    private static func resolveTimeInterval(
        envKey: EnvironmentKey,
        plistKey: StartupInfoPlistKey,
        defaultValue: TimeInterval,
        clamp: (TimeInterval) -> TimeInterval,
        env: [String: String],
        plist: [String: Any],
        warnings: inout [StartupConfigurationWarning]
    ) -> ResolvedStartupValue<TimeInterval> {
        if let envValue = env[envKey.rawValue] {
            if let parsed = parseTimeInterval(envValue) {
                return ResolvedStartupValue(value: clamp(parsed), source: .environment)
            }
            warnings.append(.invalidValueIgnored(key: envKey.rawValue, source: .environment, value: envValue))
        }

        if let plistValue = plist[plistKey.rawValue] {
            if let parsed = parseTimeInterval(plistValue) {
                return ResolvedStartupValue(value: clamp(parsed), source: .infoPlist)
            }
            warnings.append(.invalidValueIgnored(
                key: plistKey.rawValue,
                source: .infoPlist,
                value: String(describing: plistValue)
            ))
        }

        return ResolvedStartupValue(value: defaultValue, source: .defaultValue)
    }

    private static func parseTimeInterval(_ value: Any) -> TimeInterval? {
        if let string = value as? String {
            return TimeInterval(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return TimeInterval(int)
        }
        return nil
    }

    private static func resolveAllowedScopes(
        env: [String: String],
        plist: [String: Any],
        warnings: inout [StartupConfigurationWarning]
    ) -> ResolvedStartupValue<Set<ConnectionScope>> {
        if let envValue = env[EnvironmentKey.insideJobScope.rawValue] {
            if let parsed = ConnectionScope.parse(envValue) {
                return ResolvedStartupValue(value: parsed, source: .environment)
            }
            warnings.append(.invalidValueIgnored(
                key: EnvironmentKey.insideJobScope.rawValue,
                source: .environment,
                value: envValue
            ))
        }

        if let plistValue = plist[StartupInfoPlistKey.scope.rawValue] {
            if let parsed = parseScopes(plistValue) {
                return ResolvedStartupValue(value: parsed, source: .infoPlist)
            }
            warnings.append(.invalidValueIgnored(
                key: StartupInfoPlistKey.scope.rawValue,
                source: .infoPlist,
                value: String(describing: plistValue)
            ))
        }

        return ResolvedStartupValue(value: ConnectionScope.default, source: .defaultValue)
    }

    private static func parseScopes(_ value: Any) -> Set<ConnectionScope>? {
        if let string = value as? String {
            return ConnectionScope.parse(string)
        }
        if let strings = value as? [String] {
            return ConnectionScope.parse(strings.joined(separator: ","))
        }
        return nil
    }

    private static func resolveBool(
        envKey: EnvironmentKey,
        plistKey: StartupInfoPlistKey,
        defaultValue: Bool,
        env: [String: String],
        plist: [String: Any],
        warnings: inout [StartupConfigurationWarning]
    ) -> ResolvedStartupValue<Bool> {
        if let envValue = env[envKey.rawValue] {
            if let parsed = parseBool(envValue) {
                return ResolvedStartupValue(value: parsed, source: .environment)
            }
            warnings.append(.invalidValueIgnored(key: envKey.rawValue, source: .environment, value: envValue))
        }

        if let plistValue = plist[plistKey.rawValue] {
            if let parsed = parseBool(plistValue) {
                return ResolvedStartupValue(value: parsed, source: .infoPlist)
            }
            warnings.append(.invalidValueIgnored(
                key: plistKey.rawValue,
                source: .infoPlist,
                value: String(describing: plistValue)
            ))
        }

        return ResolvedStartupValue(value: defaultValue, source: .defaultValue)
    }

    private static func parseBool(_ value: Any) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

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

enum StartupInfoPlistKey: String, CaseIterable, Sendable {
    case disableAutoStart = "InsideJobDisableAutoStart"
    case token = "InsideJobToken"
    case instanceId = "InsideJobInstanceId"
    case port = "InsideJobPort"
    case scope = "InsideJobScope"
    case sessionTimeout = "InsideJobSessionTimeout"
}

private struct StartupInfoPlist: Equatable, Sendable {
    private let values: [StartupInfoPlistKey: InfoPlistValue]

    init(values: [StartupInfoPlistKey: InfoPlistValue]) {
        self.values = values
    }

    subscript(key: StartupInfoPlistKey) -> InfoPlistValue? {
        values[key]
    }
}

private struct InfoPlistValue: Equatable, Sendable, CustomStringConvertible {
    let bool: Bool?
    let string: String?
    let integer: Int?
    let double: Double?
    let stringArray: [String]?

    private let displayValue: String

    init(_ value: Any) {
        bool = value as? Bool
        string = value as? String
        integer = value as? Int
        double = value as? Double
        stringArray = value as? [String]
        displayValue = String(describing: value)
    }

    var description: String {
        displayValue
    }
}

struct StartupConfiguration: Equatable, Sendable {
    static let defaultSessionTimeout: TimeInterval = 30.0
    static let minimumSessionTimeout: TimeInterval = 1.0
    static let maximumSessionTimeout: TimeInterval = 3600.0

    let disableAutoStart: ResolvedStartupValue<Bool>
    let token: ResolvedStartupValue<String?>
    let instanceId: ResolvedStartupValue<String?>
    let preferredPort: ResolvedStartupValue<UInt16>
    let allowedScopes: ResolvedStartupValue<Set<ConnectionScope>>
    let sessionTimeout: ResolvedStartupValue<TimeInterval>
    let warnings: [StartupConfigurationWarning]

    static func resolve(
        env: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> StartupConfiguration {
        var warnings: [StartupConfigurationWarning] = []
        let plist = makeInfoPlist(from: infoDictionary)
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
            absentSource: .generated,
            warnings: &warnings
        )
        let instanceId = resolveString(
            envKey: .insideJobId,
            plistKey: .instanceId,
            env: env,
            plist: plist,
            absentSource: .generated,
            warnings: &warnings
        )
        let preferredPort = resolvePort(env: env, plist: plist, warnings: &warnings)
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
            allowedScopes: allowedScopes,
            sessionTimeout: sessionTimeout,
            warnings: warnings
        )
    }

    private static func makeInfoPlist(from infoDictionary: [String: Any]?) -> StartupInfoPlist {
        // Foundation boundary: normalize Bundle.infoDictionary's Any values once.
        var values: [StartupInfoPlistKey: InfoPlistValue] = [:]
        for key in StartupInfoPlistKey.allCases {
            if let value = infoDictionary?[key.rawValue] {
                values[key] = InfoPlistValue(value)
            }
        }
        return StartupInfoPlist(values: values)
    }

    private static func resolveString(
        envKey: EnvironmentKey,
        plistKey: StartupInfoPlistKey,
        env: [String: String],
        plist: StartupInfoPlist,
        absentSource: StartupConfigurationSource,
        warnings: inout [StartupConfigurationWarning]
    ) -> ResolvedStartupValue<String?> {
        if let envValue = env[envKey.rawValue] {
            if !envValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ResolvedStartupValue(value: envValue, source: .environment)
            }
            warnings.append(.emptyValueIgnored(key: envKey.rawValue, source: .environment))
        }

        if let plistValue = plist[plistKey]?.string {
            if !plistValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ResolvedStartupValue(value: plistValue, source: .infoPlist)
            }
            warnings.append(.emptyValueIgnored(key: plistKey.rawValue, source: .infoPlist))
        }

        return ResolvedStartupValue(value: nil, source: absentSource)
    }

    private static func resolvePort(
        env: [String: String],
        plist: StartupInfoPlist,
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

        if let plistValue = plist[.port],
           let parsed = parsePort(plistValue) {
            return ResolvedStartupValue(value: parsed, source: .infoPlist)
        } else if let plistValue = plist[.port] {
            warnings.append(.invalidValueIgnored(
                key: StartupInfoPlistKey.port.rawValue,
                source: .infoPlist,
                value: String(describing: plistValue)
            ))
        }

        return ResolvedStartupValue(value: 0, source: .defaultValue)
    }

    private static func parsePort(_ value: String) -> UInt16? {
        UInt16(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parsePort(_ value: InfoPlistValue) -> UInt16? {
        if let string = value.string {
            return UInt16(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let int = value.integer, int >= 0, int <= Int(UInt16.max) {
            return UInt16(int)
        }
        if let double = value.double,
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
        plist: StartupInfoPlist,
        warnings: inout [StartupConfigurationWarning]
    ) -> ResolvedStartupValue<TimeInterval> {
        if let envValue = env[envKey.rawValue] {
            if let parsed = parseTimeInterval(envValue) {
                return ResolvedStartupValue(value: clamp(parsed), source: .environment)
            }
            warnings.append(.invalidValueIgnored(key: envKey.rawValue, source: .environment, value: envValue))
        }

        if let plistValue = plist[plistKey] {
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

    private static func parseTimeInterval(_ value: String) -> TimeInterval? {
        TimeInterval(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parseTimeInterval(_ value: InfoPlistValue) -> TimeInterval? {
        if let string = value.string {
            return TimeInterval(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let double = value.double {
            return double
        }
        if let int = value.integer {
            return TimeInterval(int)
        }
        return nil
    }

    private static func resolveAllowedScopes(
        env: [String: String],
        plist: StartupInfoPlist,
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

        if let plistValue = plist[.scope] {
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

    private static func parseScopes(_ value: InfoPlistValue) -> Set<ConnectionScope>? {
        if let string = value.string {
            return ConnectionScope.parse(string)
        }
        if let strings = value.stringArray {
            return ConnectionScope.parse(strings.joined(separator: ","))
        }
        return nil
    }

    private static func resolveBool(
        envKey: EnvironmentKey,
        plistKey: StartupInfoPlistKey,
        defaultValue: Bool,
        env: [String: String],
        plist: StartupInfoPlist,
        warnings: inout [StartupConfigurationWarning]
    ) -> ResolvedStartupValue<Bool> {
        if let envValue = env[envKey.rawValue] {
            if let parsed = parseBool(envValue) {
                return ResolvedStartupValue(value: parsed, source: .environment)
            }
            warnings.append(.invalidValueIgnored(key: envKey.rawValue, source: .environment, value: envValue))
        }

        if let plistValue = plist[plistKey] {
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

    private static func parseBool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }

    private static func parseBool(_ value: InfoPlistValue) -> Bool? {
        if let bool = value.bool {
            return bool
        }
        if let string = value.string {
            return parseBool(string)
        }
        return nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

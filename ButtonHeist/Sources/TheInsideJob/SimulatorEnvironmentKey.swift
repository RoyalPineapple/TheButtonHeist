#if canImport(UIKit)
#if DEBUG
import Foundation

enum SimulatorEnvironmentKey: String, Sendable {
    case udid = "SIMULATOR_UDID"
}

extension Dictionary where Key == String, Value == String {
    subscript(_ key: SimulatorEnvironmentKey) -> String? {
        self[key.rawValue]
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

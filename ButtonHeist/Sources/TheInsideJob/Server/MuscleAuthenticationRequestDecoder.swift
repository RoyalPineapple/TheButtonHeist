#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension ClientAdmission.Authentication {
    static func decode(_ data: Data) -> RequestEnvelope? {
        do {
            return try RequestEnvelope.decoded(from: data)
        } catch {
            muscleLogger.error("Failed to decode client message: \(error)")
            return nil
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

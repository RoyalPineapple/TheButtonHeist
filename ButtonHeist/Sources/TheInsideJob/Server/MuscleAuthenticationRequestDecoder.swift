#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct MuscleAuthenticationRequestDecoder {
    static func decode(_ data: Data) -> RequestEnvelope? {
        do {
            return try RequestEnvelope.decoded(from: data)
        } catch {
            muscleAuthenticationLogger.error("Failed to decode client message: \(error)")
            return nil
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

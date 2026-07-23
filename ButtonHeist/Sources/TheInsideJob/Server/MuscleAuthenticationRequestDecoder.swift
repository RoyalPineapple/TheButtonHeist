#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension ClientAdmission.Authentication {
    static func decode(_ data: Data) -> RequestEnvelope? {
        try? RequestEnvelope.decoded(from: data)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

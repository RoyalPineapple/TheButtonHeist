#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

/// Off-MainActor ping fast path.
///
/// Keepalive pings must be answered even when the main actor is busy with a
/// long-running command (accessibility parse, post-action settle, exploration).
/// If pongs are gated on `@MainActor` availability, a major UIKit transition
/// can stall ping handling long enough for the client's keepalive to time out
/// and force-disconnect.
///
/// `encodedPong(for:)` is `nonisolated` and pure: it decodes the request,
/// matches `.ping`, and returns an encoded `ResponseEnvelope` carrying `.pong`.
/// Callers run it on the network queue before bridging to `@MainActor`, so
/// pongs leave the wire without waiting on main.
enum PingFastPath {

    /// Returns an encoded `.pong` `ResponseEnvelope` if `data` is a `.ping`
    /// request, otherwise `nil`. Returning `nil` means the caller must fall
    /// through to the normal `@MainActor` dispatch path — never treat `nil`
    /// as an error.
    static func encodedPong(for data: Data) -> Data? {
        let envelope: RequestEnvelope
        do {
            envelope = try RequestEnvelope.decoded(from: data)
        } catch {
            return nil
        }
        guard case .ping = envelope.message else { return nil }
        do {
            return try ResponseEnvelope(requestId: envelope.requestId, message: .pong).encoded()
        } catch {
            insideJobLogger.error("PingFastPath: failed to encode pong: \(error.localizedDescription)")
            return nil
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

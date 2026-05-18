#if canImport(UIKit)
#if DEBUG
import TheScore

/// Constructs ActionResult values with compile-time separation of success and failure paths.
///
/// The builder captures screen context (screenName/screenId) from either a snapshot array or
/// explicit values. Calling `.success()` vs `.failure()` enforces that error-only fields
/// (errorKind) cannot appear on success results.
///
/// Usage:
///     var builder = ActionResultBuilder(method: .activate, snapshot: afterSnapshot)
///     builder.message = "Tapped Sign In"
///     builder.accessibilityDelta = delta
///     return builder.success()
///
/// `@MainActor` justification: builder reads from MainActor-bound state during
/// construction; the produced ActionResult is Sendable but the builder itself
/// stages MainActor data.
@MainActor struct ActionResultBuilder { // swiftlint:disable:this agent_main_actor_value_type
    let method: ActionMethod
    let screenName: String?
    let screenId: String?
    var message: String?
    var accessibilityDelta: AccessibilityTrace.Delta?
    var accessibilityTrace: AccessibilityTrace?
    var settled: Bool?
    var settleTimeMs: Int?

    /// Create a builder deriving screenName/screenId from a ScreenElement snapshot.
    init(method: ActionMethod, snapshot: [TheStash.ScreenElement]) {
        self.method = method
        self.screenName = snapshot.screenName
        self.screenId = snapshot.screenId
    }

    /// Create a builder deriving screenName/screenId from an accessibility
    /// capture receipt.
    init(method: ActionMethod, capture: AccessibilityTrace.Capture) {
        self.method = method
        self.screenName = capture.interface.elements
            .first(where: { $0.traits.contains(.header) })
            .flatMap(\.label)
        self.screenId = capture.context.screenId ?? capture.interface.screenId
    }

    /// Create a builder with explicit screen context (when no snapshot is available).
    init(method: ActionMethod, screenName: String?, screenId: String?) {
        self.method = method
        self.screenName = screenName
        self.screenId = screenId
    }

    func success(payload: ResultPayload? = nil) -> ActionResult {
        ActionResult(
            success: true,
            method: method,
            message: message,
            payload: payload,
            accessibilityDelta: accessibilityDelta,
            accessibilityTrace: accessibilityTrace,
            screenName: screenName,
            screenId: screenId,
            settled: settled,
            settleTimeMs: settleTimeMs
        )
    }

    func failure(errorKind: ErrorKind = .actionFailed, payload: ResultPayload? = nil) -> ActionResult {
        ActionResult(
            success: false,
            method: method,
            message: message,
            errorKind: errorKind,
            payload: payload,
            accessibilityDelta: accessibilityDelta,
            accessibilityTrace: accessibilityTrace,
            screenName: screenName,
            screenId: screenId,
            settled: settled,
            settleTimeMs: settleTimeMs
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

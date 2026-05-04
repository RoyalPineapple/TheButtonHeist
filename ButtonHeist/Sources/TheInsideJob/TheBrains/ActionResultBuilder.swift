#if canImport(UIKit)
#if DEBUG
import TheScore

/// Constructs ActionResult values with compile-time separation of success and failure paths.
///
/// The builder captures screen context (screenName/screenId) from either a snapshot array or
/// explicit values. Calling `.success()` vs `.failure()` enforces that error-only fields
/// (errorKind) cannot appear on success results, and post-action element metadata cannot
/// appear on failure results.
///
/// Usage:
///     var builder = ActionResultBuilder(method: .activate, snapshot: afterSnapshot)
///     builder.message = "Tapped Sign In"
///     builder.interfaceDelta = delta
///     return builder.success(elementLabel: "Sign In", elementTraits: [.button])
@MainActor
struct ActionResultBuilder {
    let method: ActionMethod
    let screenName: String?
    let screenId: String?
    var message: String?
    var value: String?
    var interfaceDelta: InterfaceDelta?
    var settled: Bool?
    var settleTimeMs: Int?

    /// Create a builder deriving screenName/screenId from a ScreenElement snapshot.
    init(method: ActionMethod, snapshot: [TheStash.ScreenElement]) {
        self.method = method
        self.screenName = snapshot.screenName
        self.screenId = snapshot.screenId
    }

    /// Create a builder with explicit screen context (when no snapshot is available).
    init(method: ActionMethod, screenName: String?, screenId: String?) {
        self.method = method
        self.screenName = screenName
        self.screenId = screenId
    }

    func success(
        elementLabel: String? = nil,
        elementValue: String? = nil,
        elementTraits: [HeistTrait]? = nil,
        scrollSearchResult: ScrollSearchResult? = nil,
        exploreResult: ExploreResult? = nil
    ) -> ActionResult {
        ActionResult(
            success: true,
            method: method,
            message: message,
            value: value,
            interfaceDelta: interfaceDelta,
            elementLabel: elementLabel,
            elementValue: elementValue,
            elementTraits: elementTraits,
            screenName: screenName,
            screenId: screenId,
            scrollSearchResult: scrollSearchResult,
            exploreResult: exploreResult,
            settled: settled,
            settleTimeMs: settleTimeMs
        )
    }

    func failure(errorKind: ErrorKind = .actionFailed) -> ActionResult {
        ActionResult(
            success: false,
            method: method,
            message: message,
            errorKind: errorKind,
            value: value,
            interfaceDelta: interfaceDelta,
            screenName: screenName,
            screenId: screenId,
            settled: settled,
            settleTimeMs: settleTimeMs
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

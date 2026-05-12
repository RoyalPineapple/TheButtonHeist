// MARK: - AccessibilityPolicy

/// Single source of truth for trait-related rules-of-the-world.
///
/// Every site that encodes a rule *about traits* — which are transient,
/// which are interactive, which drive heistId synthesis, which are
/// purely descriptive — reads from this namespace. Adding or moving a
/// trait policy is a one-file edit; downstream sites are pure consumers.
///
/// The policy lives in TheScore so both client-side recording
/// (TheBookKeeper, which builds minimal matchers) and server-side
/// parsing (TheInsideJob, which assigns heistIds and writes the wire
/// format) read the same `Set<HeistTrait>`. UIKit-bitmask derivations
/// live in TheInsideJob as `AccessibilityPolicy+UIKit`.
///
/// Rules:
/// - Add a new transient trait → edit `transientTraits` only.
/// - Add a new interactive trait → edit `interactiveTraits` only.
/// - Reorder heistId synthesis → edit `synthesisPriority` only and run
///   `SynthesisDeterminismTests` (changes here are wire-format breaks).
public enum AccessibilityPolicy {

    // MARK: - Transient Traits

    /// Traits whose presence is *state*, not *identity*.
    ///
    /// An element gaining or losing one of these between parses keeps the
    /// same heistId — these traits do not contribute to element identity.
    /// Consumed by:
    /// - `TheBurglar.hasSameMinimumMatcher` (content-space disambiguation)
    /// - `TheStash.WireConversion.identitySignature` (functional-move pairing)
    /// - `TheBookKeeper.buildMinimalMatcher` (recording-time matcher
    ///   construction — strips state from minimal matchers)
    public static let transientTraits: Set<HeistTrait> = [
        .selected,
        .notEnabled,
        .isEditing,
        .inactive,
        .visited,
        .updatesFrequently,
    ]

    // MARK: - Interactive Traits

    /// Traits that signal "user can interact with this element".
    ///
    /// Consumed by `TheStash.Interactivity.isInteractive` to gate whether
    /// `activate` should attempt synthetic events for an element with no
    /// explicit accessibility action.
    public static let interactiveTraits: Set<HeistTrait> = [
        .button,
        .link,
        .adjustable,
        .searchField,
        .keyboardKey,
        .backButton,
        .switchButton,
    ]

    // MARK: - Static-Only Traits

    /// Traits that are purely descriptive — elements bearing *only* these
    /// traits, no custom actions, and no `respondsToUserInteraction` are
    /// expected to be non-interactive. Used by
    /// `TheStash.Interactivity.checkInteractivity` to surface an advisory
    /// warning when an `activate` is dispatched against such an element.
    public static let staticOnlyTraits: Set<HeistTrait> = [
        .staticText,
        .image,
        .header,
    ]

    // MARK: - Synthesis Priority

    /// Trait priority for `heistId` synthesis — the first trait an element
    /// carries from this list becomes its heistId suffix.
    ///
    /// Consumed by `TheStash.IdAssignment.synthesizeBaseId`. The ordering
    /// is locked by `SynthesisDeterminismTests` — changes to this list are
    /// wire-format breaks and require a coordinated release.
    ///
    /// Ordering rationale: navigation/role-defining traits (`backButton`,
    /// `tabBarItem`) win first because they uniquely identify a screen-level
    /// affordance. Input-shape traits (`searchField`, `textEntry`,
    /// `switchButton`, `adjustable`) come next — they tell the agent what
    /// kind of interaction the element accepts. `header` ranks above the
    /// generic `button`/`link` so a tappable section header synthesizes as
    /// `*_header` (the more identifying role) rather than `*_button`.
    public static let synthesisPriority: [HeistTrait] = [
        .backButton,
        .tabBarItem,
        .searchField,
        .textEntry,
        .switchButton,
        .adjustable,
        .header,
        .button,
        .link,
        .image,
        .tabBar,
    ]

    // MARK: - Tab Switch Persistence Threshold

    /// Persistence ratio below which a tab bar content swap counts as a
    /// tab switch (screen change) rather than a scroll.
    ///
    /// When comparing two parses that both contain a tab bar, the parser
    /// computes the fraction of non-tab-bar content labels that persist
    /// across the snapshots. If fewer than this fraction persist, the
    /// transition is classified as a screen change. Consumed by
    /// `TheBurglar.isTopologyChanged` (server-side topology detection),
    /// whose result flows into `TheBrains.actionResultWithDelta` and
    /// `TheBrains.computeDelta` to decide whether an action produced a
    /// new screen.
    ///
    /// Locked at `0.4` by `AccessibilityPolicyTests`. Changes to this
    /// threshold alter screen-change semantics and should be made with a
    /// clear empirical justification.
    public static let tabSwitchPersistThreshold: Double = 0.4
}

# Activation Policy

The `activate` decision tree in VoiceOver order: refresh semantic resolution and live geometry, ask UIKit to perform the element's primary accessibility activation, and only when UIKit declines deliver a tap at the element's own declared activation point. This diagram answers "which mechanism actually pressed the button, and how do I know?"

**Illustrates:** [ACCESSIBILITY-CONTRACT.md](../ACCESSIBILITY-CONTRACT.md), [API.md](../API.md)
**Source of truth:** `ButtonHeist/Sources/TheInsideJob/TheBrains/ActivationPolicy.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/AccessibilityActionDispatcher.swift`, `ButtonHeist/Sources/TheInsideJob/TheStash/Interactivity.swift`, `ButtonHeist/Sources/TheScore/AccessibilityPolicy.swift`

```mermaid
flowchart TD
    START["activate command"] --> CHECK["Interactivity.checkInteractivity"]
    CHECK -- "traits contain notEnabled" --> BLOCKED["blocked — element is disabled"]
    CHECK -- "only static traits, no activation support,<br/>no interactive traits, no custom actions" --> WARN["interactive with warning:<br/>'tap may not work' — proceed anyway"]
    CHECK -- "otherwise" --> PROCEED["interactive"]
    WARN --> REFRESH
    PROCEED --> REFRESH["refreshAndResolve<br/>semantic refresh + fresh live geometry"]
    REFRESH -- "failure" --> FAIL1["InteractionResult failure<br/>ActivationTrace: axActivateReturned nil,<br/>tapActivationDispatched false"]
    REFRESH -- "resolved" --> AXACT["accessibilityActivate()<br/>on the live element"]
    AXACT -- ".success" --> OK1["success, method .activate<br/>ActivationTrace: axActivateReturned true,<br/>tapActivationDispatched false"]
    AXACT -- ".refused or .objectDeallocated" --> TAP["activationPointDispatch at the element's<br/>declared activationPoint — not a computed frame point"]
    TAP -- "true" --> OK2["success, method .activate<br/>ActivationTrace: tapActivationDispatched true,<br/>tapActivationPoint, tapActivationSucceeded true"]
    TAP -- "false" --> FAIL2["failure with diagnostic message<br/>ActivationTrace: tapActivationSucceeded false"]
```

Notes:

- The order is deliberate: `accessibilityActivate()` is what VoiceOver invokes, so it is attempted first against fresh live geometry. The activation-point tap is the same `activate` command delivered mechanically, not a different command.
- The no-activatability-indication path **warns and proceeds** (current behavior — warn, not refuse): `Interactivity.checkInteractivity` attaches the warning to `.interactive` and the caller decides whether to log it. The trait sets consulted (`interactiveTraits`, `staticOnlyTraits`, `activationAffordanceEvidenceTraits`) live in `AccessibilityPolicy`.
- The receipt records which path ran in `ActivationTrace`: `axActivateReturned` (`true` / `false` / `nil` when the live object deallocated), `tapActivationDispatched`, `tapActivationPoint`, and `tapActivationSucceeded`.

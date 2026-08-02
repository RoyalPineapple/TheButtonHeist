# Activation Policy

The `activate` decision tree uses VoiceOver order. Button Heist refreshes the target and calls the primary accessibility action. It sends a tap only after consecutive stable captures prove quiescence.

**Illustrates:** [ACCESSIBILITY-CONTRACT.md](../ACCESSIBILITY-CONTRACT.md), [API.md](../API.md)
**Source of truth:** `ButtonHeist/Sources/TheInsideJob/TheBrains/ActivationPolicy.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/AccessibilityActionDispatcher.swift`, `ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream+ActivationSettlement.swift`, `ButtonHeist/Sources/TheInsideJob/TheVault/Interactivity.swift`, `ButtonHeist/Sources/TheScore/AccessibilityPolicy.swift`

```mermaid
flowchart TD
    START["activate command"] --> CHECK["Interactivity.checkInteractivity"]
    CHECK -- "traits contain notEnabled" --> BLOCKED["blocked — element is disabled"]
    CHECK -- "advertises no interactivity and<br/>implements no activation" --> WARN["record weak-target warning:<br/>proceed as VoiceOver would"]
    CHECK -- "otherwise" --> PROCEED["interactive"]
    WARN --> REFRESH
    PROCEED --> REFRESH["refreshAndResolve<br/>semantic refresh + fresh live geometry"]
    REFRESH -- "failure" --> FAIL1["ActionDispatchResult failure<br/>ActivationTrace: axActivateReturned nil,<br/>tapActivationDispatched false"]
    REFRESH -- "resolved" --> BOUNDARY["capture the semantic boundary"]
    BOUNDARY --> AXACT["accessibilityActivate()<br/>on the live element"]
    AXACT -- ".success" --> OK1["success, method .activate<br/>ActivationTrace: axActivateReturned true,<br/>tapActivationDispatched false"]
    AXACT -- ".refused" --> OBSERVE["capture the next post-boundary cycle"]
    OBSERVE -- "semantic or geometry change" --> OKFALSE["success, method .activate<br/>ActivationTrace: axActivateReturned false,<br/>tapActivationDispatched false"]
    OBSERVE -- "one stable capture" --> OBSERVE
    OBSERVE -- "required consecutive stable captures" --> DIAG["record implementation introspection<br/>as diagnostic evidence only"]
    OBSERVE -- "deadline or unavailable capture" --> FAILQUIET["failure<br/>tapActivationDispatched false"]
    AXACT -- ".objectDeallocated" --> DIAG
    DIAG --> TAP["activationPointDispatch at the declared<br/>activationPoint — not a computed frame point"]
    TAP -- "true" --> OK2["success, method .activate<br/>ActivationTrace: tapActivationDispatched true,<br/>tapActivationPoint, tapActivationSucceeded true"]
    TAP -- "false" --> FAIL2["failure with diagnostic message<br/>ActivationTrace: tapActivationSucceeded false"]
```

Notes:

- `accessibilityActivate()` is the operation that VoiceOver uses. Button Heist calls it first on the target with fresh live geometry.
- Some UIKit controls return `false` after they change the screen. A post-boundary semantic or geometry change prevents a second dispatch.
- A notification can trigger a capture. The notification alone does not prove that the target action changed the interface.
- One stable capture does not prove quiescence. Button Heist requires two consecutive stable captures before it sends a tap.
- The activation-point tap uses the same `activate` command. Button Heist delivers this command through touch injection.
- An unavailable capture does not permit a tap. The action fails when the deadline cannot prove quiescence.
- Every enabled target enters this policy. `notEnabled` is the only difference from VoiceOver.
- Button Heist does not dispatch to a target with this accessibility state. VoiceOver permits the double-tap and lets the app ignore it.
- Override and block introspection supplies diagnostic evidence only. It is not an accessibility semantic or dispatch gate.
- After a decline, this evidence describes the target implementation. It does not permit the fallback dispatch.
- A weak target warning uses `activation_weak_affordance_evidence`. A later expectation failure keeps this warning in the action result.
- `ActivationTrace` records the path. Its fields describe the AX return, implementation evidence, tap dispatch, tap point, and tap result.

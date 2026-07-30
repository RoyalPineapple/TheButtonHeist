# Observation Ownership Rules

These blocking rules preserve the single production observation pipeline where
Swift file-level access control cannot express the owner boundary. The
`BumperBowling.swift` inclusion list contains production `Sources` directories,
not repository tests or architecture fixtures, so those existing exemptions
remain unchanged.

| Rule ID | Exact owner | Shape and repair | Verification and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.observation_history_construction_ownership` | `ButtonHeist/Sources/TheInsideJob/TheVault/TheVault+State.swift` | This file exclusively constructs `Observation.History`. Other production code must read or mutate the Vault-owned history through `TheVault.State` instead of creating a parallel event record. | `constructionOwnership` has valid-owner and competing-owner fixtures. Delete the rule when the initializer is inaccessible outside the owner. |
| `buttonheist.semantic_observation_commit_ownership` | `ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream+CaptureAdmission.swift` | This file is the sole production caller of `commitObservation`, keeping admission, commit, publication, and waiter completion on one cycle. Other code must request an observation through `Observation.Stream`. | `memberReferenceOwnership` has valid-owner and competing-owner fixtures. Delete the rule when the mutation API is inaccessible outside the owner. |
| `buttonheist.semantic_observation_live_capture_ownership` | `ButtonHeist/Sources/TheInsideJob/TheVault/SemanticObservationStream+CaptureAdmission.swift` | This file exclusively invokes raw `captureVisibleObservation()`. Other production code must request a semantic observation publication. Method-value references used to inject the canonical capture implementation remain legal because they do not perform a capture. | A function-call query has valid-owner, competing-owner, and method-reference control fixtures. Replace it with a standard shaper when Bumper can match a receiver-independent member call without rejecting method-value references; delete it when raw capture is inaccessible outside the owner. |

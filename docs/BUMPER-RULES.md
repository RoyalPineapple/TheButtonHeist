# Bumper Bowling Rules

This is the ownership record for every Bumper Bowling rule enabled by Button
Heist. A rule belongs here only when the Swift compiler and the public type
system cannot make its forbidden state unconstructible.

Every retained rule must answer six questions: what invariant it preserves,
why the compiler cannot enforce it, where it applies, how to repair a failure,
what proves the rule, and what change would let us delete it. Standard shapers
own the mechanical diagnostic wording; this catalog owns the Button Heist
rationale and lifecycle.

## Architecture Rules

| Rule ID | Invariant and reason | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `component_boundary` | Imports between the `plans`, `score`, `doctor`, `runtime`, `testing`, `tools`, `mcp`, and `demo` components follow the dependency graph in `BumperBowling.swift`. Swift can reject a missing module dependency, but it cannot enforce Button Heist's intended dependency direction. | Move the code to its owner, introduce a value at the existing boundary, or declare a dependency only when the architecture genuinely changes. | Bumper derives imports and component ownership. Delete only if build targets encode the same graph and CI proves it. |
| `duplicate_ownership` | Each path and module has one component owner. Multiple owners make every scoped rule ambiguous. | Remove the overlapping `Owns` or `Modules` declaration. | Bumper validates the configuration graph. This is permanent while components are path-configured. |
| `declared_dependency_cycle` | The declared component graph is acyclic. Swift permits cyclic intent spread across targets even when a particular build happens to link. | Move shared values toward `plans` or `score`; do not add the reverse dependency. | Bumper evaluates the declared graph. Delete only if another authoritative graph rejects the same cycles. |
| `forbidden_import` | Component shapes keep value layers free of runtime frameworks. `plans` excludes UIKit, SwiftUI, persistence, testing, ArgumentParser, MCP, Network, Objective-C, and accessibility-parser modules; `score` excludes UIKit, SwiftUI, persistence, and testing. Swift knows imports exist, not whether they violate layer purpose. | Convert boundary evidence into Button Heist values before it enters the value layer. | Bumper's component-shape import tests. Delete individual exclusions when the component is removed or the framework becomes part of its declared responsibility. |

`MayUse` entries on runtime, testing, tool, MCP, and demo components document
capability intent; the rules above and the explicit framework sandbox enforce
the actual import boundaries.

## Import Rules

| Rule ID | Invariant and reason | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.thescore.import_allow_list` | TheScore imports only its repository-wide allowlist. Target dependencies alone are broader than this value-layer contract. | Remove the import, move boundary work out of TheScore, or deliberately update the allowlist and this explanation. | Repository lint plus mutation coverage when the list changes. Delete if TheScore becomes a target whose dependency declaration is exactly this allowlist. |
| `buttonheist.thescore.folder_import_allow_list` | Wire, evidence, receipts, reports, diagnostics, and core files each use their narrower assigned modules. The compiler cannot express folder-level responsibility. | Move the work to the matching folder or remove the excess import. | Repository lint. Delete a folder clause when its responsibility or folder disappears. |
| `buttonheist.framework_import_sandbox` | UIKit, SwiftUI, Network, Security, Objective-C runtime, and AccessibilitySnapshotParser stay in named runtime fiefdoms. These frameworks are allowed tools, but live authority must not spread through the repository. | Move the operation to an existing boundary and pass a typed value inward. | Repository lint over imported modules and paths. Delete a sandbox entry when that framework leaves the repository or a stronger component boundary fully subsumes it. |

## Currency Declarations

Every row produces `buttonheist.architecture_currency.<Symbol>` through
`Rules.singleDeclaration`. The invariant is that the named currency is
declared exactly once in its owner. Swift prevents duplicate declarations in
one module, but not parallel representations across this multi-module tree.
Repair a failure by extending the canonical type or moving the declaration to
the owner. A row can be deleted when the currency is deleted or a single build
module and access control make an alternate declaration impossible.

| Symbol | Canonical owner |
| --- | --- |
| `AccessibilityContainerKind` | `ThePlans/Model/ContainerPredicate.swift` |
| `AccessibilityPredicate` | `ThePlans/Model/AccessibilityPredicate.swift` |
| `AccessibilityTarget` | `ThePlans/Model/AccessibilityTarget.swift` |
| `AccessibilityTrace` | `TheScore/Evidence/AccessibilityTrace.swift` |
| `ActionResultEvidence` | `TheScore/Reports/ActionResultEvidence.swift` |
| `ChangeFact` | `TheScore/Evidence/AccessibilityTrace+ChangeFacts.swift` |
| `ContainerPredicate` | `ThePlans/Model/ContainerPredicate.swift` |
| `ContainerPredicateActions` | `ThePlans/Model/ContainerPredicate.swift` |
| `ContainerPredicateCheck` | `ThePlans/Model/ContainerPredicate.swift` |
| `ContainerPredicateCount` | `ThePlans/Model/ContainerPredicate.swift` |
| `ContainerPredicateFacts` | `ThePlans/Model/ContainerPredicate.swift` |
| `ContainerPredicateRoleFacts` | `ThePlans/Model/ContainerPredicate.swift` |
| `ElementMatchGraph` | `TheScore/Core/ElementPredicate+HeistElement.swift` |
| `Expr` | `ThePlans/Model/StringExpressions.swift` |
| `HeistExecutionEvidenceRollup` | `TheScore/Reports/HeistExecutionResult+Report.swift` |
| `HeistExecutionStepReportFacts` | `TheScore/Reports/HeistExecutionResult+Report.swift` |
| `InterfaceObservation` | `TheInsideJob/TheStash/InterfaceObservation.swift` |
| `InterfaceQuery` | `TheScore/Wire/InterfaceQuery.swift` |
| `InterfaceTree` | `TheInsideJob/TheStash/InterfaceTree.swift` |
| `LiveCapture` | `TheInsideJob/TheStash/LiveCapture.swift` |
| `ObservationWindow` | `TheInsideJob/TheBrains/ObservationWindow.swift` |
| `SemanticContainerPredicate` | `ThePlans/Model/ContainerPredicate.swift` |
| `SemanticObservationLog` | `TheInsideJob/TheStash/SemanticObservationLog.swift` |
| `SemanticObservationPublication` | `TheInsideJob/TheStash/SemanticObservationPublication.swift` |
| `SemanticObservationRuntimeState` | `TheInsideJob/TheStash/SemanticObservationRuntimeState.swift` |
| `SettleLoopMachine` | `TheInsideJob/TheBrains/SettleSession.swift` |
| `SettleLoopRunner` | `TheInsideJob/TheBrains/SettleSession.swift` |
| `SettlePolicy` | `TheInsideJob/TheBrains/SettleSession.swift` |

The mutation harness duplicates a currency outside its owner and asserts the
exact generated rule ID. The repository lint proves every listed declaration
exists under its owner.

## Construction And Spelling

| Rule ID | Invariant and reason | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.canonical_interface_observation_construction` | `InterfaceObservation` construction stays in its owner file; a custom residual check restricts that owner to `InterfaceObservation.build`. | Route parsed tree and live evidence through the canonical builder. | Standard path mutation plus builder-method mutation. Delete when its initializer becomes private to a type that exposes only `build`. |
| `buttonheist.canonical_live_capture_construction` | `LiveCapture` construction stays in its owner file; a custom residual check restricts that owner to `LiveCapture.build`. | Route live UIKit evidence through the canonical builder. | Standard path mutation plus builder-method mutation. Delete when its initializer becomes private to a type that exposes only `build`. |
| `buttonheist.canonical_heist_execution_evidence_rollup_construction` | Report rollups are assembled only by the report owner, preventing a second evidence interpretation. | Ask the report owner to produce the rollup. | Standard `canonicalConstruction` mutation. Delete with the type or when its initializer becomes owner-private. |
| `buttonheist.canonical_heist_execution_step_report_facts_construction` | Step report facts have one assembler. | Add inputs to the canonical report assembly. | Standard construction mutation. Delete with the type or an owner-private initializer. |
| `buttonheist.canonical_action_result_evidence_construction` | Action evidence is assembled only at the post-action, wait, capture, and report payload boundaries. | Pass canonical evidence from one of those owners instead of reconstructing it. | Standard construction mutation. Delete when access control can name exactly these owners or construction collapses to one private owner. |
| `buttonheist.canonical_semantic_observation_log_construction` | The semantic observation stream owns the one log. | Inject or read the stream-owned log. | Standard construction mutation. Delete when the initializer is inaccessible outside the stream owner. |
| `buttonheist.canonical_semantic_observation_publication_construction` | Publication assembly stays in `SemanticObservationPublication.make`, preventing the stream and log from growing competing event assemblers. | Add evidence to the publication builder. | Standard construction mutation. Delete when the initializer is private to the publication owner. |
| `buttonheist.canonical_semantic_observation_runtime_state_construction` | `SemanticObservationStream` owns the single lifecycle/lineage/cursor state machine introduced by #1340. | Add a transition to the canonical state machine rather than storing parallel stream state. | Standard construction mutation. Delete when the state type is nested privately inside the stream owner. |
| `buttonheist.canonical_accessibility_target_spelling` | `AccessibilityTarget` is the one target currency. The standard shaper catches aliases outside `AccessibilityPredicate.swift`; a source-shape residual permits only the two phase witnesses inside that file. | Use `AccessibilityTarget` directly outside those witnesses. | Outside-owner and owner-file alias mutations. Delete the residual when Bumper can express nested witness ownership; delete the rule when Swift access control can prevent aliases. |
| `buttonheist.demo_accessibility_identifier` | Demo screens expose real accessibility semantics rather than test-only identifiers; named SPI research harnesses are exempt. A typed member-reference fact is enough, so this policy does not require a raw visitor. | Improve labels, values, traits, hints, or actions. | Positive repository lint plus a demo mutation fixture. Delete when demo and research targets split and the demo target cannot call the identifier API. |

`InterfaceObservation` and `LiveCapture` have an additional builder-only check
inside `buttonheist.swift_source_shape`: even their owner files may construct
them only in `Type.build`. This remains custom because the standard construction
shaper understands paths, not enclosing type and function. Their mutation tests
cover both construction outside the owner and construction inside the owner but
outside `build`.

## Source Shape

`buttonheist.swift_source_shape` is one parse pass with multiple related
checks. They share a visitor for cost, not semantics. Every sub-invariant is
listed here so adding a visitor method cannot hide a new policy.

| Sub-invariant | Why Bumper owns it | Repair | Deletion condition |
| --- | --- | --- | --- |
| Target alias residual | Inside `AccessibilityPredicate.swift`, only the authored and resolved phase witnesses may alias `AccessibilityTarget`; the standard shaper's exception is file-granular. | Use the canonical target directly or keep the alias as a phase associated-type witness. | Bumper gains enclosing-type scope for alias exceptions. |
| `Expr` shape | The expression currency must be the package enum `Expr<Value>` and no second nominal `*Expr` bookkeeping type may appear. Swift cannot reserve a repository-wide suffix. | Extend `Expr` or use a concrete public DSL model. | A Bumper nominal-shape shaper can prove exact name, kind, access, and owner. |
| Observation-log lifecycle | `SemanticObservationLog` exposes retention/advance operations, never destructive clear/reset APIs. | Model a generation transition or retention policy. | The log API becomes private and a typed state machine makes clearing impossible. |
| Interface graph reconstruction | Only the graph owner may call `InterfaceGraph(interface:)`; consumers use `Interface.graph`. | Use the canonical projection. | Argument-label-aware construction ownership can distinguish this initializer. |
| Test semantics | Test support scripts production execution results and observations; it does not interpret `HeistStep` or evaluate predicates itself. | Feed fixtures through production execution/wait code. | Test support loses access to the semantic types or the production test API makes interpretation impossible. |
| Executable request admission | Execution functions accept admitted typed request values, not raw executable parameters. | Parse and validate at the command boundary. | Raw request types become inaccessible to execution code. |
| Container identifier spelling | Container identifiers use `ContainerPredicateCheck.identifier`; no semantic identifier side channel exists. | Add the check to the canonical predicate. | The model type no longer permits another identifier field/case. |
| Receipt warning ownership | Sibling warnings are derived from canonical receipt nodes and action results. | Add evidence to the canonical receipt assembler. | Receipt construction is private to one owner. |
| Selector shortcuts | Exported selector conveniences stay behind named target types and internal helpers. | Accept the typed target or make the helper internal. | Public APIs cannot accept raw selector material. |
| Compatibility surface | Exported declarations do not retain legacy, compatibility, or deprecated alternate spellings. | Remove the shim and migrate callers in the same version. | The repository adopts an API-diff policy that rejects aliases with equivalent coverage. |
| Callback isolation | Stored `onFoo` callbacks declare a global actor or `@Sendable`. | Annotate the closure at its stored boundary. | Swift requires the same isolation for every stored escaping closure. |
| Named cross-file shapes | Exported results, cross-file parameters/properties, and typealiases use named types instead of tuples. | Introduce a domain struct or enum. | Swift gains a repository-configurable ban for these tuple positions. |
| Builder-only live values | `InterfaceObservation` and `LiveCapture` have private initializers and are built only by their own `build` methods. | Route construction through the builder. | Access control and module layout make every alternate call unconstructible. |
| `Any` normalization | `Any` remains at immediate Foundation, Objective-C, or private-SPI boundaries. | Normalize into a Button Heist value in the boundary declaration. | Boundary APIs become typed. |
| Checked concurrency | Production code does not use `@preconcurrency` or broad `nonisolated(unsafe)` escape hatches; the named IOHID loader is the sole narrow exception. | Model isolation or isolate the private SPI behind its owner. | Upstream APIs become concurrency-safe and the exception disappears. |
| Typed JSON values | Raw `[String: HeistValue]` dictionaries stay at codec, schema, CLI, and command-admission boundaries. | Parse into a named request or payload type. | Boundary payloads become fully generated/typed. |
| Settled/live separation | `InterfaceTree` and `ObservationWindow` retain semantic values, never UIKit references or live-capture holders. | Store durable identity and keep UIKit evidence in `LiveCapture`. | The live types become inaccessible to settled modules. |
| JSON boundary | Foundation JSON encoders, decoders, and serialization live only in explicit codec, serializer, wire, or bridge files. | Move serialization to a named boundary. | All serialization is generated behind one inaccessible codec module. |
| Pure reducers | Reducer and evaluation files do not reach scheduling, clocks, notifications, networking, or URL sessions. | Return an effect and perform it at the boundary. | The pure core becomes a module that cannot import effect APIs. |
| Notification normalization | Raw UIKit accessibility notification codes enter only through `AccessibilityNotificationBus`. | Convert the raw code to `AccessibilityNotificationKind` at the bus. | The bus receives a typed system API. |
| Explicit owner access | Owner-scoped pipeline declarations spell access explicitly. | Add the intended access modifier and keep the surface narrow. | Swift package defaults or generated declarations encode the intended access. |

The shell mutation harness currently proves the callback, test-semantics,
currency, construction, expression, graph, observation-log, traversal, and
commit checks. Repository lint is the positive test for the remaining
sub-invariants. New sub-invariants require a focused positive and mutation test;
the long-term target is one `RuleTestHarness` suite instead of shell-generated
fixtures.

## Traversal Rules

| Rule ID | Invariant and reason | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.canonical_plan_traversal` | Recursive `HeistPlan` and `HeistStep` descent goes through the canonical traversal algebra; consumers provide callbacks. Independent recursion loses cases as the language grows. | Use `HeistPlanTraversal` and its visitor. | Positive consumer fixture and structural-recursion mutation. Replace with `Rules.canonicalTraversal` only when it verifies the recursive child expression, not merely a recursive call group. |
| `buttonheist.canonical_accessibility_hierarchy_traversal` | Recursive `.container` descent belongs to `folded`, `foldedPreorder`, `compactingElements`, or the path-indexed graph owner. | Express the operation through one of those algebras. | Positive fold/owner fixtures and out-of-owner recursion mutation. Replace when the standard shaper evaluates `structuralCase` and the child passed recursively. |

## InsideJob Rule

`buttonheist.insidejob_architectural_shape` preserves three related runtime
boundaries that require enclosing-declaration facts:

| Sub-invariant | Repair | Proof and deletion condition |
| --- | --- | --- |
| Reveal retries await settled visible observations, refresh live capture, and resolve before the action deadline; obsolete grace/silent-reparse spellings are forbidden because they imply a second retry pipeline. | Use the settled reveal path. | Repository lint; add a mutation before extending this name-based guard. Delete when the old concepts are absent from reachable history or a typed state machine owns every retry transition. |
| Production commits accept `InterfaceObservationProof`, not raw `InterfaceObservation` or `Screen`. | Settle or explore first, then commit the proof. | Commit mutation fixtures. Delete when raw values are inaccessible to commit owners. |
| `InterfaceObservationProof.testing` is callable only from explicit `ForTesting` fixture methods. | Move the call into a fixture constructor. | Repository lint; add a focused mutation when this API changes. Delete when the testing constructor moves to a test-only module. |

## Rule Lifecycle

Before adding or retaining a rule, record its invariant, highest viable Bumper
rung, rejected higher rung, repair, proof, and deletion condition here. Do not
add checks for malformed Swift, retired names, or states the compiler already
rejects. When a type-system or module-boundary change makes the bad state
unconstructible, delete the rule and its test instead of preserving history.

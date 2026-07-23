# The Button Heist architecture

The Button Heist lets callers write programs against an app's accessibility
contract. Semantic intent enters the runtime; The Button Heist owns target
resolution, reveal, element inflation, action execution, settling, and
evidence; callers receive settled semantic evidence for validation,
reporting, or the next step.

This document names the load-bearing runtime pieces. The canonical product
contract and conformance cases live in [Accessibility Contract](ACCESSIBILITY-CONTRACT.md).
For exhaustive command shapes, wire payloads, and per-module implementation
notes, use the generated or reference docs linked at the end.

## Product Contracts

### Strings Only at Edges

There is one product command contract: `TheFence.Command`. CLI arguments, MCP
JSON, session JSON, and heist files accept canonical command strings such as
`activate`, `type_text`, and `scroll_to_visible`; those strings are parsed once
at the boundary and routed as typed values inside the stack.

Raw command dictionaries end at Fence admission. `FenceCommandInput` is the
unadmitted edge value; `FenceOperationRequest` contains the typed operation that
execution consumes.

ButtonHeistMCP projects one tool per exposed Fence command from the same
contract. Wire message discriminators live one layer lower in TheScore and are
documented separately.

Typed `FenceCommandDescriptor` values are the sole owners of public command
shape. The committed public CLI/MCP command-contract JSON is generated only as
a drift sentinel; it is not a second schema.

ThePlans admits public payload values before they enter a command. Gesture and
wait durations are backed by one bounded-seconds primitive with domain-specific
bounds. Authored strings use distinct currencies for text input, pasteboard
content, custom action names, rotor names, warnings, and failures. Exact
nonblank currencies share the `NonBlankStringValue` construction and
single-value JSON mechanics but remain distinct concrete types that cannot be
interchanged. Text input and pasteboard values retain their different validity
rules. Public Swift construction and decoding call each currency's validating
initializer. Execution therefore consumes admitted values directly and never
clamps or repairs them.

Wire identities follow the same rule. Envelopes decode version and correlation
strings into `ButtonHeistVersion` and `RequestID`; authentication and session
ownership use `SessionAuthToken`, `DriverID`, and `SessionOwner`. These values
encode as single JSON strings but are not interchangeable strings in core logic.

### Trees and Observations Are the Currency

The committed `TheVault.interfaceTree` is the sole current semantic truth.
TheVault privately projects that tree into `AccessibilityTargetMatchInput`; the
shared `AccessibilityTargetMatchGraph` evaluates every element, container,
ordinal, and descendant-scoped `AccessibilityTarget`. TheVault maps the result
paths back to `InterfaceTree` values and current live evidence for diagnostics,
inflation, and dispatch. A delivered `Interface` feeds the same matching graph,
so client predicates and host resolution cannot drift into separate recursive
implementations. `InterfaceGraph` remains the validated structural projection
used for formatting and hierarchy operations. There is no semantic back map,
alternate flat screen, or second target-matching projection.

Parser element actions and custom content are normalized once before any
consumer sees them. `AccessibilityElement.projectedActionSet` is the sole
action projection used by matching, capability diagnostics, wire conversion,
and discovery grafting; live UIKit evidence may only augment that semantic
projection. `AccessibilityElement.projectedCustomContent` is likewise shared by
matching, diagnostics, and wire conversion. Those consumers do not independently
reinterpret parser fields.

`InterfaceObservation` pairs an `InterfaceTree` with the viewport-local
`LiveCapture` from one parser read. Raw parser samples remain live evidence or
failed-settlement diagnostic evidence; they never append temporal history and
do not become targetable semantic truth by themselves. Capture admission
normalizes the sample into `Observation.Snapshot`; UIKit objects remain
capture-boundary evidence and are never durable identity.

`Observation.Store` is the sole semantic state owner. It holds the current
`InterfaceTree`, one `Observation.Log`, generation and sequence lineage,
notification position, and admitted-read state. `Observation.Stream` admits a
capture and asks the Store to commit it. The Store classifies continuity,
derives the event, validates a copied value, records the event in its Log, and
installs the graph, log, lineage, and admitted-read state atomically. The Stream
publishes that same committed event only after the Store exposes it. There is
no parser-to-log path, subscriber-driven graph mutation, compatibility reducer,
or second runtime state projection.

The stream is also the one visible-observation producer. `TheTripwire` is its
serialized refresh trigger: a changed signal invalidates the admitted read,
settled-read admission pauses, and one capture/settle/commit cycle runs.
Concurrent consumers join that cycle. Once a Store commit installs admitted-read
state, waits and action before-state acquisition reuse the committed event until
the next trip, explicit invalidation, or screen replacement. After-action
observation always requests a fresh cycle from the same producer.

The Store's private `Observation.Log` is a `RandomAccessCollection` of ordered
`Observation.Event` values. A snapshot event contains its immutable snapshot
and initial, same-generation, or screen-boundary transition. An
`Observation.Moment` is the snapshot plus its private `Observation.Log.Index`;
it is the invocation baseline passed directly to `Log.events(since:)`.
Collection indices stay private to observation ownership and callers cannot
advance, retain, or manipulate them. Active settlement boundaries temporarily
protect the required history from pruning. No predicate, action, or adapter
owns another log or temporal window.

A raw parser read may replace live object and geometry evidence, but only a
`HeistId` resolved from the committed `InterfaceTree` can select that evidence
for action. Parsed nodes do not become targetable until a proven commit.
`HeistId` is a capture-local join key, not identity across committed captures.
When reveal crosses a capture boundary, element inflation admits one
`AdmittedSemanticTarget`: the resolved target with its terminal ordinal removed,
but only when that target uniquely resolves to the originally selected element
in the complete committed interface. Every later committed capture re-resolves
that semantic target and adopts the matching element's current `HeistId` for
live UIKit handoff. Missing or ambiguous re-resolution fails safely; it never
retains the previous id or substitutes a sibling duplicate.

The Log materializes `AccessibilityTrace` evidence and its ordered
`ChangeFact` values for temporal predicates and results. Current-state
predicates read the returned handoff snapshot through the same target resolver
that actions and `get_interface` use. An action-settlement diagnostic trace is
result-local evidence; it is not committed, targetable, or an observation
baseline. A public response may expose a compact `delta`, but that value is a
one-way, lossy fold of ordered facts and is never fed back into predicate
evaluation.

Agents should start from `get_interface`, then inspect an action result's public
delta before issuing another read. After a screen change, build follow-up
targets from the new interface evidence. See the
[currency types diagram](diagrams/currency-types.md) for the type families and
the [observation pipeline diagram](diagrams/observation-pipeline.md) for the
capture, fact, predicate, and public-fold boundaries.

### Tripwire Triggers, Settle Decides Stable

TheTripwire samples UIKit timing signals: presentation-layer movement, pending
layout, animations, top view-controller identity, navigation state, window
ordering, keyboard state, and first responder state. It never classifies the
accessibility tree.

`Settlement.Executor` is the one operation loop for actions and waits. Its
typed command is the product of an action-or-observation trigger and an
optional resolved predicate. Readiness is mandatory for all four combinations;
an observation-only command is a real trigger, not a fabricated no-op action.
The executor captures the invocation baseline, arms observation,
announcement, readiness, and deadline delivery, and only then dispatches an
action. Every capture follows capture → admit → commit → publish → evaluate.
`Settlement.Reducer` owns the explicit state machine and produces typed effects;
boundary code alone performs UIKit work.

One pure `ScreenClassifier` combines typed snapshots with scoped
`screenChanged`, `elementChanged`, and `announcement` notifications.
`AccessibilityNotificationBus` appends normalized events to one bounded ingress
log. An action window checkpoints retained history without clearing it;
notifications are edge evidence, not a second state model. A scoped screen
notification is authoritative replacement evidence. Element and announcement
notifications keep the edge in the same generation; only an empty or unknown
notification batch permits snapshot inference. An inferred replacement carries
its `AccessibilityObservationFallbackReason` in `transition.fallbackReason`.
Notification delivery is best effort; absence is not evidence of replacement
or stability.

The active Inside Job runtime owns one UIKit idle tracker. Its typed
Objective-C swizzles remain installed from runtime activation until suspension
or stop, call UIKit's original `UIViewAnimationState` start/stop methods first,
and never need to mutate the process-global method table around each action.
One aggregate animation counter runs continuously for that lifecycle, so a
heist can observe an animation that began before its own execution scope.
Outermost active-observation demand only opens permission to wait on that
counter; nested heists and actions share the permission and its one-shot idle
waiters. A public `CFRunLoopObserver` publishes one-shot main-loop
`beforeWaiting` edges. Active settlement starts parsing immediately and races
two proofs within the same authored operation deadline. The UIKit proof waits
for the aggregate animation count to reach zero, rechecks it at a main-loop
idle edge, then admits the first parse from an explicitly registered future
heartbeat only if the count is still zero on that heartbeat. The semantic
proof admits a fingerprint that remains unchanged for
60 ms, so a cosmetic infinite animation cannot pin the operation forever.
Both proofs sample through Button Heist's one CADisplayLink heartbeat. The
UIKit waiter is armed after the first heartbeat so UIKit has a chance to publish
animation starts deferred until transaction commit. The heartbeat runs at the configured
ambient rate and temporarily rises to the active screen's maximum refresh rate
while an immediate one-shot waiter exists, then restores the ambient rate on
observation, cancellation, timeout, or shutdown. No parser-owned timer or
second display link exists. Tripwire generation changes invalidate both proofs
and restart their evidence. If private idle tracking is unavailable, the
semantic quiet-window proof remains sufficient. An already-zero counter
completes its phase immediately, and an unmatched stop clamps at zero. Nested heists inherit
the outermost demand; they never install parallel hooks. Returning to idle
demand cancels pending waiters but preserves lifecycle animation truth. Before
a live heist—or a standalone action without an enclosing active context—opens
its notification attribution scope, it commits one fresh composite baseline.
That boundary prevents pre-existing navigation work from being attributed to
the first action. Runtime release invalidates the observer, cancels waiters,
and safely restores both methods unless a later swizzler superseded Button
Heist's implementation.

Settlement completion is an evidence conjunction: the trigger completed,
readiness is established, the optional predicate is satisfied under its typed
semantics, and an admitted observation belongs to that readiness generation.
If readiness arrives after the last eligible observation, the reducer requests
one handoff capture. A post-readiness observation is reused when available, so
there is no fixed delay or redundant final parse. Readiness invalidation starts
a new generation and makes an older handoff ineligible without erasing latched
transition or announcement evidence.

That shared deadline is an operation bound, not a main-thread responsiveness
probe. A true liveness probe must originate off the main actor, schedule a
round trip onto the main run loop, and win or lose its timeout race without
requiring the main thread to deliver the timeout. Transport-level unresponsive
process diagnosis remains a separate boundary from in-process idle detection.

A scoped screen notification or snapshot-inferred replacement with typed
`fallbackReason` evidence starts a new observation generation. The screen
boundary is normalized as old-tree departures, a `screenChanged` marker, then
new-tree arrivals. Layout, value, and announcement notifications stay in the
same generation. The settle loop can also report unhealthy snapshots rather
than pretending an empty post-navigation parse is stable.

UIKit value changes are not identified by an `elementChanged(.value)` signal
alone. UIKit controls may signal through either element-change subtype or an
announcement, so all three trigger a recapture; the before/after
`accessibilityValue` diff confirms the change. SwiftUI's uniform value
notification follows the same recapture path.
See the [settle loop diagram](diagrams/settle-loop.md) for the state machine
and its constants.

### Observation Has One Owner

`get_interface` returns the app accessibility state for the current screen,
including semantic content The Button Heist can discover in scrollable containers.
`get_screen` returns pixels plus the fresh visible accessibility tree with
geometry. Refresh, exploration, selection, and stale-state decisions live inside
TheInsideJob; clients and adapters send typed observation intent.

Visible observation reduces parser reads through `SettleSession`; only the
semantic stream can admit a settled outcome into the value consumed by the
visible commit path. Discovery uses the same admission and commit boundary.
`Navigation.performViewportTransition`
is the sole product-driven viewport movement operation: page scroll, discovery,
inflation placement, and restoration all provide movement intent to it. After a
successful movement dispatch, its minimal movement-specific settle parses the
new viewport, yields one run-loop turn, and parses again. Matching semantic
fingerprints prove the viewport in one turn; layout churn may consume another
turn, bounded by the 250 ms transition ceiling. Page, edge, swipe, known
content-point reveal, and restore intents all commit their admitted observation into the
canonical Store and produce one settled event. A captured reveal content point
and the semantic `TreePath` of the scroll container whose coordinate space
produced it form one evidence value. Immediately before dispatch, inflation
admits that point only when the live movement candidate has the exact owner
path. This owner-qualified seed is an optional shortcut for a known target;
blank intervening pages are irrelevant when it succeeds. A missing or
mismatched owner skips the seed without donating its coordinate to an ancestor
or sibling, and `ViewportExplorer` continues the established ancestor paging
route. The explorer is also the fallback for unknown targets or missing reveal
evidence. It dispatches exactly one viewport movement,
waits for settle, parse, Store commit, and callback, and only
then may request another movement.

Each scrollable container is searched as two independent directional rays from
its saved visual origin. The caller chooses `ViewportSearchOrder.forwardFirst`
or `.backwardFirst`; after the first ray is depleted, the explorer restores and
commits the saved origin before starting the opposite ray. Empty pages do not
deplete a direction. A ray ends only when its next legal content offset equals
its current legal content offset, the traversal matches, the screen changes, or
a configured budget is exhausted. Off-edge bounce is clamped out before this
comparison, so stretchy overdrag cannot masquerade as another page.

Command discovery and wait discovery use `ViewportExitPosition.origin`: every
touched scroll view is restored and the restored viewport is committed before
the operation returns. Target inflation uses `ViewportExitPosition.current`, so
the requested element remains visible for dispatch. The caller selects this
exit policy before traversal; finalization applies it whether traversal matched,
depleted its rays, hit a budget, or was interrupted after dispatch.
`Navigation.InterfaceExplorationResult` is the finished event and progress for that
traversal; it derives from canonical vault truth and owns no second graph or
commit path. There is no compatibility traversal or commit path.

Each Store commit records its event in the same private `Observation.Log` used
by waits and action expectations. Consumers read it through
`Log.events(since: Observation.Moment)` and receive future committed events from
`Observation.Stream`; they do not subscribe to parser samples, build private
capture arrays, or claim notification events. Retention loss is explicit
incomplete evidence, never an inferred `noChange`.

`waitFor` is the observation-triggered form of `Settlement.Command`. It shares
the same reducer, deadline, readiness, handoff, and projection rules as an
action, but cannot produce a dispatch effect. It establishes its own baseline
Moment and announcement position, so it cannot consume earlier action or heist
evidence. Observation effects may reveal a resolvable target or run canonical
discovery; their graceful stop restores the authored viewport exit position
before settlement finalizes.

An action with `.expect(...)` uses the Moment and announcement position captured
before dispatch. Current-state predicates must hold in the exact returned
handoff snapshot. Positive transitions evaluate direct Log events strictly
after the Moment and latch their first qualifying fact, so a transient
appearance or disappearance remains valid even when absent at the endpoint.
Announcements likewise latch only after the invocation boundary. Every phase
inherits one absolute authored deadline; no follow-on wait or final-validation
budget is added after the action.

Detail level is separate: `detail: "summary"` keeps responses compact, while
`detail: "full"` adds geometry and heavier accessibility fields.

### Element Inflation Is Runtime-Owned

Element inflation is the boundary between a durable semantic target and a fresh
live target that can be acted on now. Callers provide semantic identity. The
runtime owns the bounded viewport and live-geometry work required to execute
that intent.

The pipeline is:

1. Resolve the semantic target against settled accessibility state.
2. Reject missing or ambiguous targets with diagnostics.
3. Derive one deadline from the selected element's scroll-membership graph. If
   reveal will cross a capture boundary, admit an ordinal-free
   `AdmittedSemanticTarget` that still uniquely selects that exact element.
4. Reveal nested scroll ancestors outermost-first when viewport movement is
   required, using the initial capture's `HeistId` only to locate the live scroll
   owner and proving each graph path against current live containment. Each
   captured content point remains paired with its producing container's semantic
   path and is admitted only when that path exactly matches the current movement
   candidate, immediately before dispatch.
5. After every committed capture, re-resolve the admitted semantic target and
   adopt that match's current capture-local `HeistId`. Missing or ambiguous
   resolution ends inflation without a live handoff.
6. Acquire and stabilize fresh live geometry under the same deadline.
7. Execute the accessibility operation or explicit spatial gesture.
8. Return settled semantic evidence through `InteractionCoordinator`.

Predicate evaluation uses semantic observations, not live UIKit geometry. Live
geometry is used for inflation and explicit spatial gesture or viewport commands; it
is not durable identity. `CommittedElementTarget` carries the admitted or
capture-local target together with only the current capture's resolved
`HeistId`; it does not create another semantic identity. If admission,
re-resolution, or live handoff cannot be proven, the command fails with
diagnostics instead of acting on stale or guessed state. See the
[element inflation diagram](diagrams/element-inflation.md) for the resolution
flowchart. Owner-qualified point dispatch is only a seed optimization: if its
owner is missing or mismatched, the runtime does not reuse the coordinate on an
ancestor or sibling and instead continues the existing bounded ancestor paging
route. Both routes keep UIKit movement, transition settlement, Store commit, and
target re-resolution on the same canonical pipelines; they introduce no public
navigation, result, evidence, or metric contract.

### Capture Budgets Precede UIKit Enumeration

TheVault owns offscreen accessibility inventory enumeration. It reads each
admitted scroll container's reported count once in deterministic semantic-path
order, then uses one capture-global `InventoryEnumeration.RequestAdmission`.
Every `accessibilityElement(at:)` call requires an `.admitted` decision first,
so a zero budget performs no individual element requests and nil, represented,
filtered, or uncapturable responses still consume allowance.

`InventoryEnumeration.Result` is the single internal result for this work. It
owns reported count snapshots, attempted indices, captured offscreen elements,
and known unattempted count. TheVault projects those facts into the existing
`ScrollInventory` annotations. TheFence replays the same global admission order
when deriving the existing completeness and truncation projections, so known
omissions are reported at the owning scroll container without adding another
result, evidence, JSON, compact, CLI, MCP, or `.heist` model.

### State Has One Owner

The Button Heist tracks source-of-truth state only at ownership boundaries.
Everything else is a short-lived index, request correlation, lifecycle phase,
durable artifact, or final output formatting.

The approved long-lived owners are:

- `TheVault`: latest disposable `LiveCapture` and live UIKit boundary evidence.
  Its actor-owned `Observation.Store` owns the committed `InterfaceTree`, Log,
  lineage, positions, admitted-read state, and settlement diagnostics.
  `Observation.Stream` is the sole visible-observation producer and delivery
  owner.
- `TheMuscle`: auth, admission, and session state inside the app.
- `ClientDelivery`: the newest admitted callback generation and its current
  callbacks inside the app.
- `TheHandoff`: external connection phase and discovery state outside the app.
- `PendingRequestRegistry`: typed `RequestID` to continuation correlation,
  removed on resolve, timeout, or cancellation.
- `HeistResult`: immutable heist execution evidence. Report facts are
  derived from it, not stored beside it.
- Artifact stores: `.heist` package files and screenshot bytes on disk.

`LiveCapture` is an ephemeral index. Its per-path maps exist to disambiguate a
single capture and must not become stable identity. Transport registries and
auth registries may share a client key, but they stay separate: transport does
not own authentication semantics.

`ClientDelivery` is the canonical callback-generation owner. A begin is
admitted only when its generation is strictly newer than the retained latest
generation. The idle phase retains that latest-generation tombstone, while the
wiring and wired phases carry the current generation; only the wired phase
carries callbacks. Stale begin, installation, invalidation or teardown, event,
and delivery work cannot mutate current callbacks or produce client-visible
delivery. Normal-order work for the exact current generation may install and
invoke the current callbacks. `TheGetaway` issues generations before suspension
and admits matching wiring and events, while `TheMuscle` routes callback effects
through `ClientDelivery` for an exact-generation check at the delivery boundary.

The implementation owners for the bounded coordination and projection
pipelines are explicit:

| Concept | Canonical owner | Thin projections or lifecycle callers |
| --- | --- | --- |
| UI request admission and cancellation | `InteractionRequestExecutor` in `TheBrains.swift` | `TheGetaway+Transport.swift`, `Heist.swift` |
| Callback generation admission and delivery | `ClientDelivery.swift` | `TheGetaway` issues strictly increasing generations and admits matching wiring and events; `TheMuscle` routes generation-scoped callback effects through the owner |
| Drainable callback work | `TaskTracker.swift` | Lifecycle, listener-generation, and delayed-disconnect owners |
| Discovery callback delivery | `DeviceDiscoveryEventStream.swift` | `DeviceDiscovery.swift` |
| Compiler process terminal outcome | `HeistCompilerProcess.Runner` in `HeistCompilerProcess.swift` | `HeistSwiftFileCompilation.swift`; diagnostic rendering lives in `HeistSwiftFileCompilationError.swift` |
| Result construction and relationship validity | `HeistExecutionStepResult+Construction.swift` | Runtime step executors and result decoding |
| Result aggregate admission | `HeistResult.admitStructure` in `HeistResult.swift` | Package initialization and decoding; one ordered-sequence reducer admits regular roots and every recursively visited child sequence, while the root adapter alone admits auxiliary failure-capture evidence |
| Result private storage codec | `HeistExecutionStepNode.swift` and `HeistExecutionStepNode+Codable.swift` | External result JSON projection only |
| Action semantic and wire payload | `ActionResult.Payload` with `ActionResult` custom `Codable` | Runtime construction and wire encoding/decoding |
| Result interpretation | `HeistReport.project(result:)` in `HeistResult+Report.swift` | JSON, compact, human, JUnit, doctor, and metric renderers |
| Result recording decision | `HeistResult.Outcome` and `HeistResultRecordingMode` | `HeistResultRecorder` filesystem boundary |
| Offline validation algebra | `HeistValidation.Result<Value>` composed by `HeistValidation.Report` | Public JSON and text projections |
| Settlement lifecycle | `Settlement.State`, `Settlement.Reducer`, and `Settlement.Executor` | Actions and observation-only waits provide typed commands; boundaries perform effects |
| Semantic observation scheduling | `Observation.Stream` in `SemanticObservationStream.swift` | Capture scheduling, publication, and observation demand |
| Semantic observation state | `Observation.StoreOwner` and `Observation.Store` | Actor-owned atomic commit of graph, Log, lineage, positions, and admitted-read state |
| Semantic observation history | `Observation.Log` in `SemanticObservationHistory.swift` | Private collection indices, Moments, direct `events(since:)`, retention, and typed gaps |
| Result projection | `Settlement.ResultProjector` | Existing action and wait contracts, settlement evidence, and diagnostics |
| Testing request construction | `ButtonHeistTesting.swift` | Synchronous helpers and joined sessions live in their named extension files |
| Fence action JSON | `FenceJSON+Action.swift` and `FenceJSON+HeistExecution.swift`, one result family each | Fence response formatting |
| Exported tuple contract enforcement | The single `buttonheist.exported_tuple_return` Bumper rule | One effective-access projection covers functions, properties, subscripts, protocol requirements, and inherited public or package visibility; private and local tuple scratch values never enter the exported-contract projection |
| Test scheme, destination, and artifact topology | `scripts/test-runner.py` | CI and local invocations |

### Report and Action Evidence Have One Owner

`HeistResult` is execution truth: one admitted semantic step tree, duration, and
an `Outcome` derived from that tree. `HeistReport.project(result:)` walks the
tree once and owns its semantic nodes, summary, metrics, failure and warning
facts, and diagnostics. JSON, compact text, human text, JUnit, doctor, and
metric boundaries render that report instead of interpreting `HeistResult`
independently. There is no competing execution report or Fence-owned report
projection.

The report also owns accessibility-change classification. Its
`AccessibilityChange` is explicitly `notApplicable`, `incomplete`, `unchanged`,
or `changed(trace)`: missing trace evidence is never asked to mean several of
those states. Fence renderers derive `netDelta` only from `changed(trace)` and
cannot independently reclassify execution evidence.

`HeistExecutionStepResult` owns a typed execution path, duration, and one private
`HeistExecutionStepNode` used only for storage and wire projection. Package
callers cannot construct or pass that node. They use the result's per-kind
factories, which are the sole owners of action method, loop progress, iteration,
and repeat predicate relationships. A failed relationship produces no result;
it never creates a provisional result that is admitted or repaired later.
Decoding immediately routes the private decoded node through the same factories
and rejects incompatible external fields. There is no `Result` repair path or
synthetic fallback result. Status and abort paths derive from the private node,
and the wire decoder accepts only fields legal for its `type` and `outcome`.

`ActionDispatchResult` is the one aggregate of app-side action dispatch. Its
outcome is success, with an optional payload and resolved element id, or failure,
with a typed failure kind. `InteractionCoordinator` coordinates settlement and
combines that result with the evidence projected by `ActionEvidenceProjector`
to construct `ActionResult`; it does not translate through a second
interaction-result model.

`ActionResult.Payload` is the sole semantic action payload. Each case determines
its `ActionMethod` and carries only the command-specific value legal for that
method. `ActionResult` custom `Codable` projects the same value directly to the
wire's `method` and optional `payload`, then reconstructs it while
rejecting mismatched method/payload pairs. There is no wire-payload model or
semantic payload wrapper. `ActionResult.success` and `ActionResult.failure`
accept that payload plus observation, subject, and timing values. Activation
trace evidence enters only through the fixed-method activation factories.
`ActionResultSuccessEvidence` and
`ActionResultFailureEvidence` are output projections backed by one common body,
not public assembly inputs. Each result supplies exactly one observation case:
`none`, `announcement`, `trace`, or `settledTrace`; only `settledTrace` carries
the typed settlement duration. Successful activation and text-entry warnings
derive from the method and subject evidence instead of entering as caller data.

`HeistResult.Outcome` is also the only passed/failed truth used by recording.
`HeistResultRecordingMode` decides whether to write by matching that outcome,
and the recorder derives artifact naming from the same value. A
`HeistResultRecording` describes the written artifact; it does not store a
second status.

Offline validation follows the same shape. Package-only
`HeistValidation.Result<Value>` represents `valid(Value)`,
`invalid([HeistBuildDiagnostic])`, or `notEvaluated` for each phase.
`HeistValidation.Report` composes plan, invocation, lint, and canonical-source
facts once. Public JSON and text are projections of that report, not public
copies of the internal validation algebra.

`AccessibilityNotificationBus` owns one retained ingress log. Each action opens
one cursor-bounded attribution window. A successful action settlement checkpoints
that window once as one `AccessibilityNotificationBatch`; a failed settle closes
the attribution window without admitting its evidence. Checkpointing is
non-destructive: the batch selects every retained event after the opening
cursor, the exact through-cursor observed under the same lock, and an explicit
`AccessibilityNotificationGap` when bounded history overflowed. Its
through-cursor is the observation notification cursor; its scoped-screen
watermark is the only committed invalidation watermark. There is no independent
transition cursor, destructive clear, or second notification read.

`AccessibilityNotificationObserver` owns callback registration generations.
Each installed callback captures its generation, and publication accepts only
the active installing or installed generation. A callback retained past
uninstall or replacement is rejected before it can advance notification
sequence or publish into a later action window.

`Observation.Stream` owns notification invalidation. It records the
scoped `screenChanged` sequence covered by the committed batch. A scoped
`screenChanged` recorded after that capture remains beyond the committed
through-cursor and invalidates the fulfilled observation before it can be
served as current.

TheVault owns first-responder capture. A parser read converts responder state
to a capture-local `HeistId`, and `LiveCapture.Snapshot` retains that value with
the capture. Settled storage never retains a UIKit object as responder identity;
TheVault alone projects the captured id once to a semantic `AccessibilityTarget`
through the shared minimum-predicate selector used by semantic and post-action
trace context. First-responder actions pin the captured id before inflation and
fail if either the current responder id or inflated element id differs afterward.

TheVault owns notification-element correlation. While live evidence exists, it
correlates a notification object to a capture node, then emits the reference
from the same canonical tree/graph record used by target resolution. The
reference is the record's `TreePath` and traversal index, never a UIKit object
identity, semantic back map, or parallel element index.

UIKit/ObjC `@unchecked Sendable` is a platform-boundary escape hatch only. Such
uses stay in TheInsideJob, require a synchronization justification directly
above the declaration, and must not cross into typed core or wire/report layers.

### One Driver Owns the Session

The server accepts one active session owner at a time. Ownership is either a
driver ID or an auth token, retaining its provenance instead of encoding it in a
prefixed string. Same-owner reconnects can join the session; different owners
receive `sessionLocked` until the inactivity timer releases the session.

Transport supports multiple TCP connections because one-shot CLI/MCP calls may
connect, run, and disconnect repeatedly, but session ownership remains singular.
Runtime subscriptions are not a public driver surface.

### Screen Classification Is Typed

Screen changes are not guessed from text, timers, or window events. The parser
builds settled captures, `AccessibilityNotificationBus` records scoped screen,
layout, value, and announcement evidence, and `ScreenClassifier` determines
replacement before traces are built. A scoped screen notification is
authoritative and starts a new generation. Element and announcement
notifications never classify a replacement. When the batch has no usable kind,
the classifier may infer replacement from typed settled snapshots and records
the reason in both logs and `fallbackReason`. Notification records remain in
`accessibilityNotifications`; parsed screen IDs, first-responder state,
geometry, and generation counters are not independent screen evidence. The
fact reducer consumes only the notification records or typed
`transition.fallbackReason`, so consumers can distinguish an observed
`screenChanged` notification from an inferred screen boundary.

## Component Map

The full module/dependency graph — every crew member, its responsibility, and
the Codable wire boundary — is drawn in the [crew map diagram](diagrams/crew-map.md).
The [system topology diagram](diagrams/system-topology.md) shows the same
machine at one altitude higher: host tools, the wire, and the `#if DEBUG`
in-app server.

## Execution and Predicate Pipeline

The Button Heist has one current-tree projection and one retained ordered history.
Actions, `get_interface` subtree queries, waits, expectations, and repeat-loop
stop conditions use one `AccessibilityTarget` language. Authored conditions use
the concrete `AccessibilityPredicate` root and `ChangeDeclaration` assertion
types; expression, core, and resolved representations remain package
implementation details. For a single action's end-to-end sequence, see the
[action pipeline diagram](diagrams/action-pipeline.md).

`InteractionRequestExecutor`, owned by `TheBrains`, provides the single FIFO for
UI-facing requests. Transport submits admitted UI work with its client identity,
while direct in-app heists enter the same queue before bootstrap and retain
ownership through the complete plan. Disconnect cancels that client's active and
queued work. Per-client `ClientRequestPipeline` instances preserve frame and
admission order only; control traffic remains outside the interaction executor.

Plan identity follows the same boundary rule. `HeistPlanName` and
`HeistReferenceName` are distinct roles backed by one exact identifier grammar.
Source, JSON, and CLI text is admitted once into those roles,
`HeistDefinitionPath`, or
`HeistInvocationPath`; parser, traversal, catalog, runtime, and result layers
do not split dotted strings or rebuild paths. Definition and invocation paths
remain semantically distinct wrappers over one canonical path-value parser and
single-value wire representation.
Compiler entry symbols reuse that parser as `HeistEntrySymbol`. Structural
plan locations are component-backed `HeistPlanPath` values; only source,
diagnostic, and response rendering turns them into strings.

```mermaid
flowchart TD
    SwiftAuthor["Swift DSL authoring"] --> Fragment["Opaque HeistContent<br/>builder fragment"]
    SourceAuthor["Canonical runtime heist source"] --> Parse["Lex and parse source"]
    Fragment --> Candidate["Package admission shape<br/>HeistPlanAdmissionCandidate"]
    Parse --> Candidate
    Candidate --> Validate["Admit once<br/>semantic validation + runtime bounds"]
    Validate --> Plan["Executable HeistPlan"]
    Validate --> OfflineReport["validate_heist<br/>plan + invocation + lint report"]
    Plan --> FenceCommand["Fence command<br/>run_heist / perform / wait"]
    FenceCommand --> HandoffSocket["Handoff socket<br/>client version == app version"]
    HandoffSocket --> Executor["TheBrains-owned InteractionRequestExecutor<br/>one UI FIFO"]

    Executor --> Resolve["Resolve typed action and predicate"]
    Resolve --> Command["Settlement.Command<br/>trigger × optional predicate"]
    Command --> Baseline["Capture and commit baseline<br/>Observation.Moment + announcement position"]
    Baseline --> Arm["Arm observation, announcement,<br/>readiness, and deadline channels"]
    Arm --> Trigger{"Trigger"}
    Trigger -->|action| Dispatch["Dispatch exactly once"]
    Trigger -->|observation| Observe["No dispatch"]
    Dispatch --> Observe
    Observe --> Commit["capture → admit → commit → publish"]
    Commit --> Reduce["Settlement.Reducer<br/>evaluate typed evidence"]
    Reduce --> Ready{"trigger + predicate + readiness<br/>+ eligible handoff?"}
    Ready -->|no, time remains| Observe
    Ready -->|ready, handoff absent| Handoff["Request one post-readiness capture"]
    Handoff --> Commit
    Ready -->|yes| Result["Settlement.Result"]
    Ready -->|deadline| TimedOut["Independent predicate,<br/>readiness, and handoff evidence"]
    Result --> Project["Canonical result projector"]
    TimedOut --> Project
    Project --> ActionResult["ActionResult"]
    Project --> WaitResult["HeistWaitEvidence"]

    Resolve -->|Action.until / RepeatUntil| LoopBaseline["Read baseline observation<br/>without evaluating stop predicate"]
    LoopBaseline --> RunBody["Run body action<br/>at least once"]
    RunBody --> ProgressGate["Use action Settlement.Result or await<br/>the next committed observation"]
    ProgressGate --> EvaluateStop["Evaluate stop predicate<br/>against retained observations"]
    EvaluateStop --> StopMet{"stop met?"}
    StopMet -->|yes| Done["success"]
    StopMet -->|no, progress + time remains| RunBody
    StopMet -->|no progress or deadline elapsed| Fail["fail / timeout"]
```

`waitFor` and action `.expect(...)` enter the same settlement executor with
different typed triggers:

- `waitFor(...)` uses `.observation`, establishes a new invocation-local
  `Observation.Moment` and announcement position, and never dispatches.
- `Action(...).expect(...)` uses `.action`, establishes those boundaries before
  dispatch, and evaluates while the action is still settling. It never starts a
  second wait after dispatch.
- `RunHeist(...).expect(...)`: baseline is the nested heist boundary and stays
  action-like.
- `RepeatUntil(...)` and action `.until(...)`: a direct semantic observation
  establishes temporal evidence without evaluating the stop predicate. The body
  always executes once. Its settled action trace, or the next settled element
  observation, supplies the post-body state used to evaluate either a current-tree
  existence predicate or an iteration-scoped change predicate. Only an unmet
  result with time remaining starts another iteration. Screen boundaries emit
  element lifecycle facts and therefore participate in the same evaluation.

Each baseline is an `Observation.Moment`: one immutable snapshot paired with a
private index into its owning Log. Settlement consumes direct
`Log.events(since:)` results and never maintains a second capture array,
baseline, or notification claim. Current-state evidence is deliberately not
latched; it must hold in the returned handoff. Positive transitions and
announcements latch their first qualifying post-boundary event. `noChange`
requires complete retained history. Uncommitted diagnostic evidence can never
become a successful predicate verdict.

A scoped screen notification or snapshot-inferred replacement carrying typed
`fallbackReason` evidence ends the current observation generation and starts
the next. The boundary is retained in the same ordered fact stream as three
facts:

1. `elementsChanged` with every node in the old delivered tree disappeared.
2. `screenChanged` as the generation boundary marker.
3. `elementsChanged` with every node in the new delivered tree appeared.

This makes a screen change an element lifecycle change without pretending that
nodes were updated across generations. Only same-generation capture edges can
construct `updated` facts. A target that has the same semantics on both screens
still disappears and appears because its generation changed.

Generation admission is scope-aware. A fresh screen-change notification is
authoritative. Snapshot fallback compares a candidate with the previous capture
in the same scope while that scope is current. When the scope trails the global
generation, it compares the candidate with the latest global source: the same
screen catches up without another increment, while a different screen advances
again. This keeps visible and discovery commits from either hiding a real
boundary or counting the same boundary twice. Each retained event still links
only to the previous event in its own scope.

`Observation.Log.events(since:)` returns ordered committed events or a typed
expired/unavailable result. Ordered `ChangeFact` values derive from those events
plus scoped notification evidence. The evaluator reads neither warning text nor
an endpoint delta. Only complete, fact-free retained history can satisfy
`.noChange`.

The public predicate layer is a concrete root with concrete declaration types:

- Root predicates: `.exists(target)`, `.missing(target)`,
  `.changed(...)`, `.noChange`, and `.announcement(...)`.
- Screen declaration: `.changed(.screen([.exists(target), .missing(target)]))`.
- Elements declaration: `.changed(.elements([.exists(target),
  .missing(target), .appeared(target), .disappeared(target),
  .updated(target, change)]))`.

`exists` and `missing` always evaluate against the current delivered tree,
including elements, containers, and descendant-scoped targets. `appeared`,
`disappeared`, and `updated` consume ordered element facts. The nested
`ChangeDeclaration.ScreenAssertion` and `ChangeDeclaration.ElementAssertion`
types make invalid combinations such as an `updated` screen assertion
unconstructible.

The wait reducer also records a bounded set of semantic candidates from unmet
observations it has already evaluated. On timeout, the projector renders exact
predicate mismatches into the existing failure message and `HeistReport`.
Diagnostics do not schedule another capture, settlement, reveal, discovery,
poll, or predicate evaluation, and they do not add a public option, token,
result shape, or wire field.

## Core Flows

### Read

1. The client sends `get_interface`.
2. TheInsideJob parses until settled, commits the proven graph and log entry,
   and returns the resulting accessibility capture.
3. TheFence formats the capture for CLI/MCP using the requested detail level.

### Act

1. TheFence parses a boundary request into `TheFence.Command`.
2. Fence admission converts `FenceCommandInput` into `FenceOperationRequest`,
   then lowers it into a one-step or composed `HeistPlan` and sends
   `ClientMessage.heistPlan`.
3. TheGetaway routes the plan to TheBrains' heist runtime.
4. TheBrains resolves the semantic target and predicate, then creates one
   `Settlement.Command` with an action trigger and absolute deadline.
5. Settlement captures and commits its baseline Moment, opens the action
   notification window, and arms observation, announcement, readiness, and
   deadline delivery before dispatching exactly once.
6. Each admitted observation atomically updates the Store and Log, publishes
   one event, and is evaluated by the reducer. Successful completion requires
   dispatch, predicate truth when requested, readiness, and an eligible
   post-readiness handoff observation.
7. The response includes the heist execution result. `HeistReport` classifies
   its accumulated accessibility evidence once, and public renderers project
   any resulting delta from that classification.

### Wait

`wait` is a one-step heist projected from an observation-triggered
`Settlement.Command`. It establishes a fresh Moment and announcement position,
arms the same event channels as an action, and performs no dispatch. Already
committed current-state truth remains immediately evaluable, including with a
zero timeout; transition predicates require a later Log event.

Observation effects may reveal one already-resolvable target or run canonical
viewport discovery. Discovery searches both directional rays and exits
`.origin`; graceful stop restores the saved origin before settlement finalizes.
The executor otherwise waits on committed Log/Stream events instead of polling.
A standalone wait cannot consume evidence from a prior action or heist.

Every observation effect, readiness wait, predicate evaluation, and handoff
capture inherits one authored operation deadline. When predicate, readiness,
and handoff evidence are complete, the reducer exits immediately—there is no
extra stability sleep or final predicate revalidation. After a terminal result,
the lifecycle first suppresses new callbacks, then quiesces and joins child
work, and only then releases its outer notification and observation leases.

`.exists(target)` and `.missing(target)` resolve any element, container, or
descendant-scoped `AccessibilityTarget` against current state.
`.changed(.elements(...))` and `.changed(.screen(...))` require their declared
fact evidence; a lifecycle assertion never passes from final state alone.

### Replay

Heist replay executes authored `HeistPlan` artifacts through TheFence, so a
failure points at the accessibility contract that changed.

## Reference Docs

- [Diagrams](diagrams/README.md) - architecture diagrams, one file per
  concern; the [process boundaries diagram](diagrams/process-boundaries.md)
  draws the in-process vs out-of-process argument.
- [Accessibility Contract](ACCESSIBILITY-CONTRACT.md) - canonical product
  contract, boundary map, pipeline, and conformance cases.
- [API Reference](API.md) - public APIs, CLI, MCP tool contract, and command
  catalog notes.
- [Wire Protocol](WIRE-PROTOCOL.md) - TheScore envelopes, transport messages,
  payload schemas, and auth/session details.
- [MCP Agent Guide](MCP-AGENT-GUIDE.md) - practical tool-use patterns for
  agents.
- [Heist Format](HEIST-FORMAT.md) - generated heist artifact and plan IR format.
- [Auth](AUTH.md) - authentication, approval, and session locking.

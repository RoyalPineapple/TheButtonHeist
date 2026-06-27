# Self-Healing Semantic Accessibility Testing: Research Brief

Working notes for a white paper on evidence-driven repair of semantic
accessibility tests.

## Thesis

Self-healing UI test repair is valuable only when it preserves the test's
original semantic intent and refuses to guess when the evidence is weak.

The defensible version is not automatic test mutation. It is an evidence-driven
repair workflow:

1. Preserve the last successful semantic hierarchy and the current failing
   semantic hierarchy.
2. Prove what the old test meant in the last successful run.
3. Explain why the same target now fails.
4. Search for a successor using semantic continuity, neighbor context, and
   optional outcome evidence.
5. Generate a minimum unique replacement matcher in the new hierarchy.
6. Return a structured suggestion or a structured refusal.

This framing separates semantic repair from locator autocorrect. The system is
allowed to say "unable to suggest safely because the successor is ambiguous."
That abstention behavior is part of the feature, not a failure mode.

## Prior Art

### Test Repair Is Not New

WATER, a 2011 web application test repair technique, is a useful anchor. It
compares a test's behavior across two versions of a web application: one where
the test passed and one where it fails, then suggests script repairs from the
execution differences. It explicitly targets changed or displaced elements and
obsolete expected content.

Source: [WATER: Web Application TEst Repair](https://shauvik.com/public/pubs/roychoudhary11etse.pdf)

That maps closely to our receipt-pair model:

- WATER: old passing execution plus new failing execution.
- Button Heist: last successful heist receipt plus current failing heist
  receipt.
- WATER repair target: Selenium/web script.
- Button Heist repair target: durable semantic heist target suggestion.

The important distinction is that Button Heist's repair evidence is the parsed
accessibility contract evidence, not raw DOM position, CSS, XPath, or visual geometry.

### Robust Locators Are Preventive, Not Repair

ROBULA+ is useful as the "make locators less brittle up front" branch of the
literature. It generates robust XPath locators by iteratively refining from a
generic selector until the target element is uniquely selected, and reports
large reductions in locator fragility compared with absolute locators and
Selenium IDE locators.

Source: [ROBULA+: An Algorithm for Generating Robust XPath Locators for Web Testing](https://tsigalko18.github.io/assets/pdf/2016-Leotta-JSEP.pdf)

This is related but distinct from the white paper's thesis:

- Robust locator generation tries to prevent future failures.
- Repair suggestions diagnose a failure after valid product evolution.
- Button Heist still needs a minimum unique matcher, but the matcher is generated
  after successor identity is proven from semantic evidence.

That ordering matters. A unique selector for the wrong successor is still wrong.

### Visual and Hybrid Repair

Vista argues that repair can use visual information because developers often
debug broken UI tests by looking at the GUI, not just source or DOM structure.
WEBRL later combines structural and visual information for web UI test repair.
These approaches are relevant because they broaden evidence beyond raw
selectors, but they still lean on visual/DOM repair signals rather than the
assistive-technology contract itself.

Sources:

- [Visual Web Test Repair](https://tsigalko18.github.io/assets/pdf/2018-Stocco-FSE18.pdf)
- [Enhancing Web Test Script Repair Using Integrated UI Structural and Visual Information](https://seg.nju.edu.cn/uploadPublication/copyright/125627676581.pdf)

For our paper, visual evidence should be treated as an optional escalation, not
the primary identity model. Semantic accessibility hierarchy is the stronger
default because it is already the contract used by assistive technologies and,
on iOS, by UI automation.

### Semantic Repair Has Academic Precedent

Recent work explicitly names semantic test repair for web applications. The ACM
listing for Semter describes it as a semantic repair technique for web test
repair; follow-on literature summarizes it as capturing semantic information
from test executions and computing semantic similarity between elements.

Sources:

- [Semantic Test Repair for Web Applications](https://dl.acm.org/doi/10.1145/3611643.3616324)
- [A Survey on Web Testing: On the Rise of AI and Applications in Industry](https://arxiv.org/html/2503.05378v1)

Our white paper should position Button Heist as a mobile/accessibility-contract
variant of this line of work, with a stronger guardrail stance:

- suggestions, not automatic source mutation
- minimum unique matcher validation
- conservative confidence
- explicit refusal paths
- no durable identity leaks from runtime/capture handles

### Mobile GUI Repair Is Closer to Our Domain

Mobile GUI repair work is especially relevant because mobile tests already
operate through a constrained UI hierarchy rather than a browser DOM.

COSER, published at ICSE 2024, repairs obsolete Android GUI test scripts by
combining "external" GUI semantics from runtime element properties with
"internal" semantics from source code. It reports that COSER made 82% of scripts
and 90% of test actions execute correctly across 20 Android apps, outperforming
METER, AppTestMigrator, and GUIDER. COSER's authors also identify cases where
external semantics can mislead repair, especially when UI properties do not
match actual behavior.

Source: [Comprehensive Semantic Repair of Obsolete GUI Test Scripts for Mobile Applications](https://seg.nju.edu.cn/uploadPublication/copyright/125-1039515427.pdf)

UITESTFIX, for web UI tests, is relevant because it highlights neighbor
relations directly: it improves element matching by using path similarity and
region similarity, arguing that relative positions and neighboring elements
improve matching accuracy. That supports our "neighbor context is required
evidence" rule from an independent direction.

Source: [Automated Fixing of Web UI Tests via Iterative Element Matching](https://gaoxiang9430.github.io/papers/ASE23_UITESTFIX.pdf)

The Button Heist paper can take a different stance from COSER:

- It does not require source-code analysis of the app under test.
- It treats accessibility semantics as the durable public contract.
- It refuses to repair when public semantic evidence is insufficient.
- It optimizes for human-approved suggestion quality, not maximum continued
  action execution.

That is a narrower but cleaner claim. Source-code semantics can repair more, but
they also move the system from black-box accessibility contract testing toward
implementation-aware test migration. The white paper should explicitly choose
the former.

### Commercial and Open-Source Self-Healing Tools

Healenium is a concrete open-source example of runtime self-healing for
Selenium. Its docs describe automatic detection and healing of UI-change
failures such as changed IDs or class names, with proxy and driver-wrapper
integration modes. It stores reference selectors, healing data, reports, and
DOM evidence.

Source: [Healenium documentation overview](https://healenium.io/docs/overview)

This is useful contrast. The mainstream self-healing pitch optimizes for
continued execution and reduced test maintenance. Our thesis optimizes for
evidence quality and product safety. The test should not silently keep going if
the successor is not semantically proven.

### Accessibility-Tree Self-Healing Is Emerging

A 2026 arXiv preprint proposes "zero-cost" self-healing test automation based on
DOM accessibility tree extraction. It uses a priority-ranked locator hierarchy
starting with role-based locators, then falls back through IDs, ARIA labels, CSS
fragments, and visible text. It demonstrates the direction of travel: the
accessibility tree is becoming a repair substrate, not only a test-query
substrate.

Source: [Beyond LLM-Based Test Automation: A Zero-Cost Self-Healing Approach Using DOM Accessibility Tree Extraction](https://arxiv.org/abs/2603.20358)

The contrast is again important. That work centers selector rediscovery and
continued execution. Our proposed contribution centers durable semantic
evidence, local hierarchy context, minimum matcher validation, conservative
confidence, and human-approved suggestions.

### Accessibility-First Testing Is Mainstream

The accessibility tree is not an implementation detail invented for testing. W3C
defines the accessibility tree as a UI structure exposed through platform
accessibility APIs, where nodes carry role, state, properties, and accessible
names.

Source: [W3C Accessible Name and Description Computation](https://www.w3.org/TR/accname-1.1/)

Modern testing frameworks increasingly encode this idea:

- Playwright recommends role locators because they reflect how users and
  assistive technologies perceive the page. It also warns that CSS and XPath can
  be tied to DOM structure and become unstable.
- Testing Library recommends queries accessible to everyone as the highest
  priority, grounded in tests resembling user interaction.
- Playwright ARIA snapshots store and compare a representation of the
  accessibility tree.
- Appium exposes `accessibility id` as a native mobile locator strategy based on
  platform accessibility options.
- Android Jetpack Compose uses a semantics tree for both accessibility services
  and tests. The same semantic properties that let TalkBack describe and
  interact with UI also let the testing framework find nodes, interact with
  them, and assert state.

Sources:

- [Playwright locators](https://playwright.dev/docs/locators)
- [Testing Library queries](https://testing-library.com/docs/queries/about/)
- [Playwright ARIA snapshots](https://playwright.dev/docs/aria-snapshots)
- [Appium finding elements](https://appium.readthedocs.io/en/stable/en/writing-running-appium/finding-elements/)
- [Android Compose semantics](https://developer.android.com/develop/ui/compose/accessibility/semantics)
- [Android Compose testing semantics](https://developer.android.com/develop/ui/compose/testing/semantics)

For iOS specifically, Apple ties UI automation and accessibility together. The
WWDC23 accessibility audits talk notes that UI tests finding elements also
exercises accessibility exposure, while accessibility identifiers allow test
identity without altering the user-facing accessibility experience. The WWDC24
SwiftUI accessibility session describes accessibility elements as the objects
assistive technologies use, carrying attributes and actions.

Sources:

- [Apple WWDC23: Perform accessibility audits for your app](https://developer.apple.com/videos/play/wwdc2023/10035/)
- [Apple WWDC24: Catch up on accessibility in SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10073/)

This lets the paper make a strong claim: semantic accessibility testing is not
just a more stable selector style. It is testing against the same contract used
by accessibility technologies.

One nuance matters for repair receipts: semantic projections can differ.
Compose, for example, distinguishes merged and unmerged semantics trees; tests
use the merged tree by default while accessibility services consume the
unmerged tree and apply merging rules. Button Heist should record which
projection a capture came from, or at least whether local context was explicit
or inferred. Otherwise two receipts may look comparable while actually
describing different semantic views of the same UI.

Playwright's duplicate-control guidance is a useful analogy for neighbor
context. Its locator docs show selecting a product row by `listitem` plus
descendant text such as `Product 2`, then clicking that row's `Add to cart`
button. The repair equivalent is the same idea in reverse: when the button
label drifts, the row/list/header context is the bridge that proves which
successor inherited the old intent.

## Button Heist Positioning

Button Heist already has the right primitives:

- `HeistPlan` stores durable semantic intent, not viewport mechanics.
- Action execution captures settled before and after accessibility evidence.
- Element inflation resolves semantic targets, reveals them if needed, and acts
  on fresh live targets without making geometry durable identity.
- Receipts carry the execution tree and accessibility traces.
- `heist-doctor` consumes last-pass and new-fail receipts and produces structured
  suggestions or explicit no-suggestion reasons.

Local anchors:

- `docs/ACCESSIBILITY-CONTRACT.md`
- `docs/ARCHITECTURE.md`
- `docs/ELEMENT-INFLATION.md`
- `docs/HEIST-FORMAT.md`
- `ButtonHeist/Sources/HeistDoctorCore/HeistRepairSuggestions.swift`

The white paper should use Button Heist as a concrete system, not just an
example implementation. The conceptual contribution is the repair contract:

```text
last successful semantic snapshot
        +
current failing semantic snapshot
        +
original target and step path
        +
optional after-diff / expectation evidence
        v
suggestion or refusal
```

## Initial Experiment

We ran one realistic validation experiment against the demo app:

1. Run a known-good menu-order heist and preserve the last successful receipt.
2. Make a valid product UI change: rename the checkout button from `Checkout` to
   `Go to Checkout`.
3. Re-run the old heist without changing the test.
4. Capture the failing receipt.
5. Run `heist-doctor` with the two receipts.

The first doctor version failed in an instructive way. It suggested unrelated
menu buttons because broad screen-level sibling/header context scored too
strongly, while `Checkout` -> `Go to Checkout` did not score as close text
continuity.

The fix tightened the evidence model:

- contained semantic phrase renames count as text continuity
- sibling context must be local enough to distinguish identity
- broad header overlap no longer creates strong continuity when many compatible
  candidates exist
- wrong-capability repair remains low confidence

After the fix, the same receipt pair produced one suggestion:

```swift
target(predicate(label="Go to Checkout"))
```

Applying the suggestion to the drifted heist made the demo flow pass. Temporary
demo changes were reverted; the durable change was the scorer fix plus focused
unit tests.

This is a strong case study because it includes a negative result. The original
heuristic over-repaired; the experiment exposed the risk; the repair contract
became stricter.

## Experiment Log

### E1: Contained Label Rename on Real Demo Receipts

Status: completed.

Baseline:

- Heist: menu-order dogfood flow.
- Old target: `target(predicate(label="Checkout"))`.
- Last successful receipt: `.rp1/work/heist-doctor-experiment/last-pass.json`.

Product drift:

- Demo app checkout toolbar button changed from `Checkout` to `Go to Checkout`.
- The heist was intentionally left unchanged.
- New failing receipt: `.rp1/work/heist-doctor-experiment/new-fail.json`.

Pre-fix doctor behavior:

- Output: unsafe suggestions.
- Suggested unrelated menu-item buttons:
  - `Garlic Bread`
  - `Hummus & Pita`
  - `Rice Pilaf`
- Confidence: low.
- Failure mode: broad screen-level sibling/header context was counted as
  preserved neighbor evidence, while contained text continuity was not counted.

Post-fix doctor behavior:

- Output: one suggestion.
- Failure kind: `missingTarget`.
- New target: `target(predicate(label="Go to Checkout"))`.
- Confidence: medium.
- Key reasons:
  - old target resolved once in the last successful before snapshot
  - old target resolved zero times in the new before snapshot
  - suggested matcher resolved once in the new before snapshot
  - label was a close semantic rename
  - role/actions remained compatible
  - last successful after diff observed the expected screen change
- Caveat: current failure used full after snapshot because compact diff was
  unavailable.
- Validation: applying the suggested target to the temporarily drifted heist made
  the demo flow pass.

Research classification:

- Before fix: unsafe suggestion.
- After fix: correct suggestion.
- Lesson: low confidence is not enough protection by itself. Weak context must
  be excluded before ranking, not merely caveated after ranking.

## Receipt Evidence Audit

The first real receipt-pair experiment exposed what the current receipt format
already makes possible and where the evidence model is still too thin.

### What E1 Receipts Already Preserve

The E1 receipts preserve:

- action step path, status, command name, and target description
- action result success/failure, method, error kind, and diagnostic message
- before and after accessibility captures for each action
- screen identity in capture context
- screen transition evidence through capture hashes and screen IDs
- projected accessibility labels, values, traits, hints, descriptions, actions,
  custom actions, rotors, user input labels, and identifiers when present
- geometry and activation points inside raw captures
- for-each iteration values at iteration nodes
- expectation outcome when an action carries an expectation

The checkout experiment used these facts well:

- Last pass before capture: `screenId=menu`, target label `Checkout`.
- Last pass after capture: `screenId=checkout`, checkout review elements present.
- New fail before capture: `screenId=menu`, successor label `Go to Checkout`.
- New fail after capture: still `screenId=menu`, same hash as before.
- Failure diagnostic: near miss said `label="Go to Checkout"` matched as a
  substring.

That means receipts already support:

- missing target repair
- label/value rename repair
- capability continuity checks
- screen-transition expectation evidence
- "old action changed screen, new failed action did not" explanations
- no-suggestion errors when the old target still resolves or evidence is
  incompatible

### What E1 Receipts Do Not Preserve Well Enough

The same receipts are weak for local identity:

- Across 34 captures in the last-pass receipt, container annotations were always
  empty.
- Every element path had depth 1.
- The menu capture for the failed checkout step was a flat array of 43 elements.
- The checkout toolbar button's "sibling" set effectively included large parts
  of the screen.

That explains the original bug. The doctor thought unrelated menu items had
neighbor continuity because the receipt's local hierarchy context was not
actually local.

The code model can represent a nested hierarchy: `TreePath` supports root-relative
child indexes, and `Interface` carries full `AccessibilityHierarchy` plus
annotations. The E1 problem is that the produced capture did not preserve useful
row/toolbar/container structure for this SwiftUI screen. The white paper should
treat that as a research finding, not hide it.

### A Second Gap: Resolved References

Parameterized heists introduce another opportunity. In the menu flow, the
for-each iteration nodes preserve concrete values such as:

```text
Greek Salad
Margherita Pizza
```

But the nested action command evidence may preserve the authored ref:

```json
{ "label_ref": "item" }
```

instead of the concrete resolved target label. The concrete value is present in
the ancestor iteration evidence, but the doctor does not yet treat that as
first-class repair context for the nested action step.

This matters for repair. If a parameterized heist breaks inside a loop, the
doctor should be able to say:

```text
This failed in iteration item="Greek Salad"; the action target was label_ref(item),
resolved to the Greek Salad row in the last successful run.
```

That would make loop-body repair much more explainable.

## Second-Pass Receipt Findings

After inspecting the E1 receipts and the current execution model, the strongest
conclusion is that the existing receipt shape is closer than it looks. The
system already records two critical facts:

- successful action results carry `ActionSubjectEvidence`, including the
  resolved target and resolved element immediately before dispatch
- action results carry `AccessibilityTrace` captures, and each capture hash
  covers the hierarchy, Button Heist annotations, and capture context

For the checkout experiment, the last-pass receipt proves the old action
resolved to the `Checkout` button before dispatch. The new-fail receipt has no
subject evidence for that step because resolution failed before dispatch, but
its diagnostic string contains the useful near miss:

```text
did you mean label="Go to Checkout" (visible)?
```

That is enough to repair a simple rename after the scorer fix, but it is not
enough to push the feature much further. The missing evidence is not another
raw snapshot. The missing evidence is a normalized repair context around the
action:

- which capture was used as the before state
- which capture-local path held the old resolved element
- what local neighborhood surrounded that element
- how the target resolved, including candidate counts and ordinal use
- what near misses were considered on failure
- what loop/ref bindings were active when the nested action executed
- how much hierarchy fidelity the capture actually had

The current `ActionSubjectEvidence` is deliberately result evidence, not a
selector. That is the right boundary. The next step should preserve richer
evidence beside it, still marked as evidence, so `heist-doctor` can reason
without reparsing strings or guessing from flat projections.

## Capability Ceiling With Current Receipts

With current receipts, the doctor can be genuinely useful for:

- contained label/value renames
- stable identifier continuity
- wrong-capability explanations on the same semantic target
- screen-transition failures where the old action changed screens and the new
  action did not
- expectation/value failures where compact after diff explains the drift
- no-target-needed classifications when the old target still resolves and still
  supports the requested action

The ceiling appears quickly in harder cases:

- duplicate row repair is unsafe when the capture is effectively flat
- list reordering cannot be distinguished from ordinal drift without row
  context
- toolbar/footer moves need container or pane context, not global sibling text
- loop-body failures need concrete binding context on the action step
- target-resolution near misses are too useful to remain embedded in strings
- a single same-role/same-action candidate is still unsafe without semantic
  continuity

So the right product posture is high precision and useful abstention, not high
recall. "Unable to suggest because the old receipt had no local hierarchy for
duplicate controls" is a valid doctor result. The CLI should make that
actionable by naming the missing evidence, not by quietly returning nothing.

## What We Can Do Today

With current receipts, safe repair seems strongest for:

- exact stable identifier continuity, when identifiers are stable and public
- close label/value continuity
- contained phrase rename, such as `Checkout` -> `Go to Checkout`
- same action family and role, only as supporting evidence
- screen transition continuity, such as old action moved `menu -> checkout`
- expectation outcome differences, such as old expectation passed and new failed
- no-target-needed classification when the old target still resolves and supports
  the requested action

Current receipts are risky for:

- duplicate rows when the real capture is flat
- toolbar-vs-content disambiguation when both appear as top-level siblings
- structural moves where the old and new element share only broad screen context
- loop-body repairs where concrete ref bindings must be reconstructed from
  ancestor steps
- distinguishing "same visible text in same section" from "same visible text
  somewhere else on the screen"

## What To Collect Next

These additions would expand safe repair without making the doctor guessier.

### 1. Local Semantic Neighborhoods at Capture Time

For every resolved action target, store a compact local neighborhood sidecar:

- parent/container path
- nearest accessibility container summary
- nearest list/section/row/cell summary
- nearby preceding and following semantic elements within a small window
- sibling labels inside the same row/container only
- nearest headers and section headers
- toolbar/tabbar/navigation-bar membership
- action/trait/capability summary

This should be derived from the accessibility hierarchy and stored as semantic
facts, not as UIKit object references.

### 2. Target Resolution Trace

For every action, store how the target resolved:

- authored target expression
- fully resolved target after refs/parameters are bound
- match count before ordinal selection
- selected element summary
- selected element local neighborhood
- whether ordinal was used
- near-miss candidates and why they did not match

This would let the doctor prove old intent without re-deriving everything from a
possibly lossy projection.

### 3. Scoped Ref Binding Context

For nested heists and loops, store the active binding environment on each step:

- invoked heist path
- string parameter name/value
- element-target parameter name/value
- for-each ordinal/count
- loop source predicate or string collection
- rendered command target after substitution

The goal is not to store source code. It is to make every action step
self-explanatory as executed.

### 4. Compact Semantic Diffs With Identity Hints

Current after evidence can say screen changed or values changed. For repair, a
more useful compact diff would retain:

- added/removed/updated semantic element summaries
- local neighborhood for changed elements
- screen ID before and after
- screen summary before and after
- expectation predicate and actual observation
- stable identifier continuity when available

This would help expectation/value/screen-change repairs without requiring full
after snapshots for every ordinary case.

### 5. Parser Fidelity Metrics in Receipts

Each capture should report whether it had enough hierarchy for repair:

- maximum tree depth
- container count
- row/list/cell container count
- number of top-level elements
- whether the capture is effectively flat
- whether local context was inferred or explicit

Then `heist-doctor` can lower confidence or refuse when the receipt says local
context quality is poor.

### 6. Failure Diagnostics as Structured Data

The E1 failure message contained a useful near miss:

```text
did you mean label="Go to Checkout" (visible)?
```

Today that is a string. It would be stronger as structured evidence:

- failed predicate
- relaxed predicate mode used for near miss
- candidate target
- visibility/actionability
- reason it did not satisfy the original target
- candidate local neighborhood

The doctor can use that as evidence without brittle message parsing.

### 7. Privacy and Durability Policy

Raw captures already include geometry and activation points. Suggestions must
not leak those as durable identity. If we add richer receipt evidence, classify
each field:

- allowed in receipt
- allowed in suggestion summary
- allowed in suggested matcher
- internal-only diagnostic
- must be redacted

That keeps the repair system useful without letting runtime-local identity
escape into heist artifacts.

## Proposed Receipt Sidecar

A concrete next increment is a small, Codable sidecar on each action receipt.
This should live with execution evidence, not in the heist plan, and
`heist-doctor` should consume it as optional evidence. Older receipts still work;
new receipts become more explainable.

Sketch:

```swift
public struct HeistActionRepairContext: Codable, Sendable, Equatable {
    public let authoredTargetDescription: String?
    public let resolvedTarget: ElementTarget?
    public let resolution: TargetResolutionEvidence?
    public let bindingContext: HeistBindingContext?
    public let beforeCapture: AccessibilityTrace.CaptureRef?
    public let subjectPath: TreePath?
    public let subjectNeighborhood: SemanticNeighborhood?
    public let captureFidelity: InterfaceFidelityMetrics?
    public let diagnostics: TargetDiagnosticEvidence?
}
```

`TargetResolutionEvidence` should record:

- predicate after ref substitution
- match count before ordinal selection
- selected ordinal, if any
- selected capture-local path, when resolved
- selected element summary
- whether ordinal was part of authored intent or only runtime selection
- runtime minimum unique target for the selected element
- capped candidate summaries for ambiguity

`SemanticNeighborhood` should record:

- target path
- parent summary
- nearest semantic container summary
- ancestor chain summaries
- siblings before and after in the same parent/container
- row/list/cell context, when available
- nearest headers
- a small ordered traversal window around the target
- action/trait/capability context
- source quality: `explicitHierarchy`, `inferredFromTraversal`, or
  `unavailable`

`InterfaceFidelityMetrics` should record:

- projected element count
- maximum hierarchy depth
- container count
- annotated container count
- top-level element count
- visible/known element counts if both are available
- whether the capture is effectively flat
- semantic projection name, when known

`TargetDiagnosticEvidence` should record:

- failed predicate
- resolution scope
- failure kind: missing, ambiguous, wrong capability, ordinal out of range
- near-miss relaxation kind, such as substring label or close value
- near-miss candidate summaries
- near-miss paths and neighborhoods when available
- mismatch reasons

`HeistBindingContext` should record:

- invoked heist stack
- active string refs and resolved values
- active target refs and resolved targets
- for-each ordinal and total count
- rendered command target after substitution

This is not a new product feature exposed to app authors. It is receipt evidence
for an alpha CLI tool. The durable output remains structured suggestions,
reasons, caveats, or structured refusal errors.

## Collection Points

The current code has natural places to collect this without redesigning the
execution system:

- `ActionSubjectEvidence` can gain, or be paired with, the capture ref,
  capture-local path, minimum target, and semantic neighborhood for successful
  actions.
- `ElementInflation.InflatedElementTarget.subjectEvidence(...)` is the narrow
  point where a semantic target has resolved and is about to dispatch.
- `TheStash.TargetResolution` already separates resolved, not-found, and
  ambiguous facts; those facts should have a Codable projection instead of
  being flattened only into diagnostic strings.
- `TargetResolutionDiagnostics` should keep producing human text, but from the
  same structured diagnostic object that `heist-doctor` can consume.
- `PostActionObservation` already owns before/after capture construction and is
  the right place to attach capture refs and fidelity metrics.
- `TheBrains+HeistActionExecution` already knows the authored command and the
  resolved command, making it the right place to attach scoped binding context
  to each action receipt.

The implementation should be additive and alpha-scoped: receipts may include
repair context, the doctor may use it, but no production path should edit heists
or stored plans.

## How Good Can This Get?

With the sidecar above, safe repair should handle common real-world drift:

- button and field renames with stable action/role continuity
- duplicated row controls where row text or header context is preserved
- list reordering where neighborhood stays with the item and ordinal changes
- toolbar-to-footer moves when stable container, screen, or nearby cart/total
  context survives
- wrong-capability drift where the same label remains but a compatible successor
  exists nearby
- loop-body drift where the failing action can be explained with concrete
  binding values
- expectation/value failures where after diff explains the behavioral change

It should still refuse when:

- the old target did not resolve exactly once in the last-pass receipt
- successors only share role/action compatibility
- duplicate candidates have no preserved local context
- the capture is flat and the intended distinction lives in missing hierarchy
- product intent changed rather than drifted
- the only available identity would be geometry, runtime IDs, capture-local
  handles, or synthesized IDs

That is the strongest version of the feature: precision first, refusal as a
first-class outcome, and explanations that tell the human what evidence was
missing.

## Research Questions

1. Can semantic accessibility hierarchy evidence identify the intended successor
   of a broken UI test target after legitimate UI evolution?
2. How often should a conservative repair system abstain rather than suggest?
3. Which continuity signals are strong enough to permit repair?
4. Does requiring a minimum unique matcher reduce false repairs without making
   useful suggestions too rare?
5. How much does local neighbor context improve duplicate disambiguation?
6. When does optional after evidence improve repair quality?
7. Can explanations be good enough for a human to approve or reject suggestions
   quickly?

## Hypotheses

- H1: Semantic accessibility snapshots can repair common target drift such as
  label changes, stable identifier preservation, and local row-context changes.
- H2: Role/action compatibility alone produces unacceptable false positives.
- H3: Neighbor context is necessary for duplicate controls and list rows.
- H4: Minimum unique matcher validation prevents suggestions that cannot be
  replayed safely in the new hierarchy.
- H5: A suggestion-only workflow preserves product signal better than automatic
  mutation because ambiguous or behavior-changing updates remain visible.

## Experiment Matrix

Use demo-app changes that simulate real product evolution. These are validation
experiments, not necessarily permanent demo tests. When a validation experiment
exposes a product bug in the doctor, add narrow unit coverage for that bug.

| Scenario | Change | Desired doctor behavior |
|----------|--------|-------------------------|
| Contained label rename | `Checkout` -> `Go to Checkout` | Suggest new label with medium confidence. |
| Duplicate row rename | `Delete` beside `Milk` -> `Remove` beside `Milk`, `Remove` beside `Bread` | Suggest only the Milk-row successor. |
| Duplicate without context | Two same-role successors and no preserved local context | Refuse as ambiguous. |
| Structural move | Checkout action moves from toolbar to footer with cart/total context preserved | Suggest if semantic continuity beats alternatives; do not rely on traversal ordinal. |
| Competing candidates | `Go to Checkout`, `Checkout Help`, `Checkout Later` | Suggest only if semantic + context evidence clearly identifies one. |
| Wrong capability | Same label exists but no longer supports activation | Refuse unsupported target or suggest compatible successor only with low confidence and continuity. |
| Copy-only unrelated candidate | Old `Delete`, new only `Checkout` button | Refuse; role/action compatibility is insufficient. |
| After-diff strengthening | Before snapshot is weak, after evidence points to expected screen/value change | Include after evidence in reasons; do not require full after snapshot by default. |
| Identifier continuity | Label changes but stable accessibility identifier remains | High confidence if matcher resolves uniquely and capability is compatible. |
| Ordinal fallback | Semantic facts cannot disambiguate but old target already used ordinal | Low confidence, explicit caveat. |
| List reorder | Same item and action survive but row order changes | Suggest from row/header context; traversal ordinal must not be primary evidence. |
| Loop binding drift | Failure occurs inside a for-each/nested heist | Explain active binding values and repair only within that iteration context. |
| Modal/pane drift | Action moves into or out of a sheet/dialog | Use pane/window context; refuse if the candidate could belong to another active surface. |
| Text-entry rename | Field label changes while first-responder/keyboard context is preserved | Suggest only if the field neighborhood or identifier proves continuity. |
| Flat duplicate capture | Multiple duplicate buttons, receipt has max depth 1 and no containers | Refuse with missing-neighborhood error. |
| Diagnostic near miss | Failure provides structured close-label candidate | Use near miss as supporting evidence, not sole proof unless continuity exists. |

## Metrics

Primary metrics:

- Suggestion precision: emitted suggestions that identify the intended successor.
- False repair rate: emitted suggestions that identify the wrong element.
- Abstention correctness: refusals when evidence is genuinely insufficient.
- Useful abstention rate: refusals that explain the missing evidence clearly.
- Minimum matcher uniqueness: suggestions whose generated target resolves
  exactly once in the current failing snapshot.

Secondary metrics:

- Confidence calibration: high/medium/low confidence compared with human review.
- Explanation quality: whether reasons and caveats let a reviewer make a quick
  decision.
- Repair latency: time from receipt pair to suggested target.
- Human time-to-repair: time to approve or reject a suggestion versus manual
  investigation.
- Identity-leak audit: suggested matchers contain no geometry, runtime IDs,
  capture IDs, synthesized IDs, handles, or live references.

## Guardrails

The paper should make these guardrails central:

- Repair is suggestion-only.
- No heist/source/artifact/storage mutation.
- Old target must resolve exactly once in the last successful snapshot.
- Current failure must be classified.
- Drift repair requires semantic continuity beyond role/action compatibility.
- Duplicate disambiguation uses the existing minimum matcher machinery.
- Ordinal is last resort and caveated.
- Confidence is conservative.
- Every path returns either a suggestion or a structured reason for refusal.
- Durable output must not include geometry or runtime-local identity.

## Likely Contribution

The contribution is not "AI fixes tests." A better, more credible contribution:

> Semantic accessibility tests can retain enough durable evidence to produce
> conservative, explainable repair suggestions after legitimate UI evolution,
> while preserving test failure as a product signal when intent cannot be proven.

This is narrower than common self-healing marketing, and stronger because it is
auditable.

## Claims To Avoid

- Avoid claiming tests should heal themselves at runtime. That is exactly the
  unsafe behavior the repair contract is designed to avoid.
- Avoid claiming accessibility semantics make tests immune to UI evolution.
  Semantic copy, labels, grouping, and actions are supposed to change when the
  product changes.
- Avoid claiming geometry and screenshots are useless. They are useful
  escalation evidence; they are just poor durable identity.
- Avoid claiming every valid product change is repairable. Some changes remove
  or alter intent, and the right output is refusal.
- Avoid treating confidence as probability. Confidence is a policy label based
  on evidence strength, uniqueness, and caveats.
- Avoid over-indexing on one demo app. The demo is a research instrument; the
  paper needs a corpus of drift cases.

## Experimental Protocol

Each validation scenario should be run with the same protocol:

1. Choose a heist that passes on the baseline app.
2. Preserve the last successful receipt.
3. Make one valid product change to the demo app.
4. Re-run the unchanged heist and preserve the failing receipt.
5. Run `heist-doctor --last-pass ... --new-fail ... --format json`.
6. Classify the result:
   - correct suggestion
   - unsafe suggestion
   - correct refusal
   - unhelpful refusal
   - tool/runtime error
7. If a suggestion is emitted, manually apply it to the temporary heist and
   re-run against the changed app.
8. Revert temporary app/test drift.
9. Add narrow unit coverage only when the experiment exposes a doctor bug.

The output record should include:

- scenario name
- baseline heist path and step path
- product change
- old target
- expected successor or expected refusal
- doctor output
- confidence
- evidence signals in reasons
- caveats
- whether the suggested matcher resolves exactly once
- whether applying the suggestion made the heist pass
- notes on false-positive risk

## Open Questions

- Should the paper use "self-healing" in the title, or reserve that phrase for
  contrast and call the system "evidence-driven semantic repair"?
- How large does the validation corpus need to be before the claim feels
  credible?
- Should mobile be the center of the paper, or should the paper generalize to
  any accessibility-tree testing system?
- How do we define "human-approved repair" operationally in the experiment?
- Should we compare directly against a locator-healing baseline, or only against
  no-repair/manual-repair?
- How should we measure explanation quality without pretending it is objective?

## Next Research Steps

1. Build the validation corpus from the experiment matrix.
2. For each case, preserve the last-pass receipt, introduce a valid product
   drift, preserve the new-fail receipt, and run `heist-doctor`.
3. Record outcome as correct suggestion, unsafe suggestion, correct refusal, or
   unhelpful refusal.
4. Track the evidence signals used for each emitted suggestion.
5. Add focused unit tests only for bugs found in the research instrument.
6. Draft the white paper around the empirical results, not around optimistic
   capability claims.

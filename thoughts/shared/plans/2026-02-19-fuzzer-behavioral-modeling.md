# Prediction-Driven Behavioral Modeling for the AI Fuzzer

## Overview

Shift the fuzzer from reactive anomaly detection ("that looked weird") to prediction-driven testing ("I predicted X, got Y, that's a bug"). When the fuzzer lands on a screen, it builds a behavioral model — state variables, element-state relationships, and testable predictions — then validates each prediction through action. Any deviation between prediction and actual behavior is a finding.

## Current State Analysis

The fuzzer currently follows: `OBSERVE → IDENTIFY INTENT → PLAN BATCH → EXECUTE → RECORD`

Screen intent recognition (added today) classifies screens and runs appropriate workflow/violation tests. But predictions are implicit — the fuzzer doesn't commit to expected outcomes before acting. Findings have `Expected:` and `Actual:` fields, but the expectations are composed retroactively when something looks wrong.

The recent fuzzing session found 8 anomalies, several of which would have been caught *more systematically* with explicit predictions:
- **F-1** (persistence): A model would predict `items persist across navigation` and verify it
- **F-2** (grammar): A model would predict `empty state follows "No {filter} todos" pattern` and test each variant
- **F-3** (hidden clear button): A model would predict `button visibility tracks item visibility`
- **F-5/F-6** (duplicate IDs, inert toggles): A model would predict `each element has unique identifier` and `elements with toggle hint respond to activation`

### Key Discoveries:
- SKILL.md is at 370 lines (budget: 500) — room for ~40 lines of modeling concepts
- screen-intent.md is at 283 lines — room for model templates per intent
- session-notes-format.md has a clear template structure for adding new sections
- trace-format.md has an extensible YAML entry format
- The existing invariants (Reversibility, Persistence, etc.) are generic — models make them specific

## Desired End State

After this plan is complete:
1. The core loop in SKILL.md includes `BUILD MODEL`, `VALIDATE`, and `INVESTIGATE` steps
2. Each screen intent in screen-intent.md has a behavioral model template
3. Session notes include a `## Behavioral Models` section recording per-screen models and predictions
4. Trace entries optionally include prediction and validation fields
5. examples.md demonstrates the full predict→act→validate→investigate cycle
6. The fuzzer generates explicit, testable predictions before acting, reports deviations as findings, and **probes unexpected behavior with focused investigation** instead of just recording and moving on

### Verification:
- Read SKILL.md — core loop shows the prediction-driven flow
- Read screen-intent.md — each intent has a Model Template subsection
- Read session-notes-format.md — template includes `## Behavioral Models`
- Read trace-format.md — interact entry shows optional prediction/validation fields
- Read examples.md — at least one example demonstrates predict→validate
- All files pass internal consistency check (no contradictions with existing content)

## What We're NOT Doing

- **Not adding a formal specification language** — models are structured markdown, not code
- **Not requiring predictions for every action** — trivial actions (tapping a label) don't need predictions
- **Not changing the existing invariants** — models complement invariants, invariants remain as the generic safety net
- **Not adding new commands or reference files** — this integrates into existing files
- **Not changing trace replay** — fuzz-reproduce still works from the existing trace format; prediction fields are optional

## Implementation Approach

Add the modeling concept to SKILL.md, templates to screen-intent.md, recording format to session notes and trace, then demonstrate in examples. Each phase is independently valuable — a partial implementation still improves the fuzzer.

---

## Phase 1: Core Behavioral Modeling in SKILL.md

### Overview
Define what a behavioral model is, update the core loop, and establish the prediction→validation cycle.

### Changes Required:

#### 1. Update the Core Loop section
**File**: `ai-fuzzer/SKILL.md`
**Lines**: ~42-53 (Core Loop section)
**Changes**: Update the loop diagram and description to include BUILD MODEL and VALIDATE steps.

New core loop:
```
OBSERVE → IDENTIFY INTENT → BUILD MODEL → PREDICT+ACT → VALIDATE → INVESTIGATE → RECORD
```

The PLAN BATCH step becomes PREDICT+ACT — the batch plan now includes explicit predictions for each action. The new VALIDATE step compares actual results against predictions. The new INVESTIGATE step probes unexpected results deeper.

Update the step descriptions:
1. **OBSERVE**: (unchanged)
2. **IDENTIFY INTENT**: (unchanged)
3. **BUILD MODEL**: On a new screen, build a behavioral model — state variables, element-state relationships, and testable predictions. Use the intent's model template as a starting point, then refine from observation. Record in `## Behavioral Models`.
4. **PREDICT+ACT**: For each action in the batch, state what you expect to happen (state changes, screen transitions, element appearances/disappearances). Execute the action.
5. **VALIDATE**: Compare the actual delta against your prediction. Match → model confirmed. Mismatch → proceed to INVESTIGATE.
6. **INVESTIGATE**: When a prediction is violated, don't just record it — probe deeper. See `### When Predictions Fail: Investigate` below.
7. **RECORD**: (unchanged, but findings now reference specific prediction violations and investigation results)

#### 2. Add `## Behavioral Modeling` section
**File**: `ai-fuzzer/SKILL.md`
**Position**: After `## Screen Intent Recognition` (after line ~228, before `## Novelty and Variation`)
**Changes**: New section (~50 lines)

Content:

```markdown
## Behavioral Modeling

After identifying a screen's intent, build a **behavioral model** — your best hypothesis about how the screen works, based purely on observation. The model makes your expectations explicit and testable.

### What a Model Contains

1. **State variables**: What does this screen manage? Items in a list, values in form fields, toggle states, a selected filter, a count label. Name each one.
2. **Element-state map**: Which elements *read* state (labels, counts, badges) and which elements *write* state (buttons, toggles, fields)? Map the relationships.
3. **Coupling rules**: How do elements relate to each other? "Text in field enables Add button." "Toggling parent shows/hides children." "Changing filter changes visible items but not the backing list."
4. **Predictions**: What should happen when you interact with each writable element? Be specific: "tapping Add will append the field's text as a new item, increment count from N to N+1, clear the field, and disable the Add button."

### How to Build a Model

1. Start from the screen intent's **model template** (see `references/screen-intent.md`)
2. Fill in specifics from the actual elements you observe — real identifiers, real labels, real current values
3. Infer coupling rules from element proximity and naming (a field called "newItemField" next to an "addButton" are coupled)
4. State your predictions explicitly before acting

### Prediction Types

- **State mutation**: "Tapping Add will set count from 0 to 1" — the action changes a specific state variable in a specific way
- **State persistence**: "Items will survive a navigation roundtrip" — state endures across screens
- **Pattern consistency**: "Empty state for 'All' filter will follow the same template as 'Active' and 'Completed'" — observed pattern extends to untested cases
- **Element coupling**: "Typing into the text field will enable the Add button" — one element's state affects another
- **Cross-screen effect**: "Changing the 'Show Completed' toggle in Settings will hide completed items on the Todo List" — action on screen A affects screen B

### Validating Predictions

After each action, compare the delta against your prediction:
- **Match**: Prediction confirmed. Your model is consistent with observed behavior.
- **Mismatch — model was naive**: You predicted "nothing happens" but something did. Update your model, not a finding yet — but investigate if the unexpected behavior seems wrong.
- **Mismatch — clear violation**: You predicted specific behavior based on strong evidence and the app contradicted it. Investigate immediately.
- **Mismatch — ambiguous**: Could be a bug or a feature you didn't understand. Investigate to disambiguate.

The model doesn't need to be perfect. An incorrect model that gets refined through observation is still doing its job — it's forcing you to reason about expected behavior before acting.

### When Predictions Fail: Investigate

When something unexpected happens, **don't just record it and move on**. Treat every deviation as a thread to pull. The goal is to understand the deviation — its scope, its consistency, and its boundaries.

**Reproduce** — try the exact same action again. Does it happen every time?
- If yes: the behavior is deterministic. It's either a bug or your model was wrong.
- If no: it's intermittent. Try 3 more times to establish the rate.

**Vary** — try related actions. Does the deviation extend?
- Same element, different action (tap vs activate vs long_press)
- Adjacent elements (order ±1, same type)
- Same action on a similar element elsewhere on the screen

**Scope** — how far does this go?
- Is it just this element, or all elements of this type?
- Is it just this screen, or does it affect other screens?
- Navigate to a related screen and check for cross-screen effects

**Reduce** — what's the minimal trigger?
- What's the shortest action sequence that reproduces it?
- Does it happen on a fresh visit to the screen, or only after specific prior actions?
- Does the starting state matter?

**Boundary** — where exactly does it break?
- If a pattern holds for N cases but fails for one, test every case to find the exact boundary
- If persistence fails, test which state survives and which doesn't (e.g., "settings persist but todo items don't")

Investigation doesn't need to be exhaustive — 3-5 focused probes are enough to classify the deviation. Record what you find: the deviation's scope, consistency, and minimal trigger. This turns a vague "something weird happened" into a precise, actionable finding.

**Budget**: Spend up to 5 actions investigating a deviation. If it's still ambiguous after 5 probes, record what you know and move on — you can revisit during the refinement pass.

### Model Evolution

Models improve as you explore:
- After validating predictions, update the model with confirmed or corrected rules
- When investigation reveals new behavior (changing A also changes B), add it to the model
- When a prediction fails but investigation shows the behavior is correct, the model was wrong — fix it
- When investigation confirms a bug, the model was right — the app is wrong. Record the finding.
- Record model updates in session notes so they survive compaction
```

### Success Criteria:
- [x] SKILL.md core loop updated to 7 steps including BUILD MODEL, VALIDATE, and INVESTIGATE
- [x] New `## Behavioral Modeling` section present with all 5 subsections (What, How, Types, Validation+Investigation, Evolution)
- [x] Investigation guidance includes: reproduce, vary, scope, reduce, boundary
- [x] SKILL.md total line count stays under 500 (448 lines)
- [x] No contradictions with existing Screen Intent Recognition or Observable Invariants sections

---

## Phase 2: Model Templates in screen-intent.md

### Overview
Add a "Model Template" subsection to each intent category, giving the fuzzer a starting point for building screen-specific models.

### Changes Required:

#### 1. Add model templates per intent
**File**: `ai-fuzzer/references/screen-intent.md`
**Changes**: Add a `**Model template**` block to each of the 8 intent categories, after the violation tests.

Templates to add:

**Item List** (after violation tests, ~line 58):
```markdown
**Model template**:
```
State: items[]{text, completed?}, count, filter?, emptyState visible|hidden
Writes: addButton→items.append, item.activate→item.completed, item.delete→items.remove, filter→visibleSubset
Reads: countLabel←items.length, emptyLabel←(items.length==0)
Coupling: field.text↔addButton.enabled, filter→visibleItems (not backing store), showCompleted→visibility
Predict: add→count++, delete→count--, complete→activeCount changes, navigate-away-return→items persist, empty-when-0→emptyLabel appears
```
```

**Form / Data Entry** (after violation tests, ~line 87):
```markdown
**Model template**:
```
State: fields{name: val, ...}, submitEnabled, validationErrors[]
Writes: textField→fields[name], submitButton→validate+submit, cancelButton→discard
Reads: validationIndicators←fields (live or on-submit), submitButton.enabled←requiredFieldsFilled
Coupling: field-fill→submit-enabled, submit→screenChange|validationError, cancel→revert|navigate-back
Predict: fill-all→submit-enabled, submit-valid→success(screenChange), submit-empty→validationErrors, cancel→no-persist, navigate-away→fields lost (no auto-save) or fields preserved (auto-save)
```
```

**Settings / Preferences** (after violation tests, ~line 121):
```markdown
**Model template**:
```
State: settings{key: val, ...}, dependencies{parent: [children]}
Writes: toggle→settings[key], picker→settings[key], resetButton→settings=defaults
Reads: dependentControls.visible←parent.value, effectScreens←settings[key]
Coupling: parent-toggle→children.visibility, setting-change→cross-screen-effect
Predict: change→persists-across-nav, parent-off→children-hidden, parent-on→children-restored-with-prior-values, cross-screen-effect-visible
```
```

**Detail / Read View** (after violation tests, ~line 147):
```markdown
**Model template**:
```
State: item{fields...}, favorited?, editing?
Writes: editButton→editing=true, saveButton→item.update, favoriteButton→favorited toggle, deleteButton→item.remove+navigate-back
Reads: displayFields←item, favoriteIcon←favorited
Coupling: edit→save/cancel appear, save→detail-updates+list-updates, delete→navigate-back-to-list
Predict: edit→save-changes-to-detail-and-list, favorite→toggles-and-persists, delete→removed-from-list, back-without-save→no-changes
```
```

**Navigation Hub** (after violation tests, ~line 171):
```markdown
**Model template**:
```
State: destinations[], selectedTab?, perTabState{}
Writes: navElement→screenChange, tabElement→selectedTab
Reads: tabIndicator←selectedTab
Coupling: tab-switch→preserves-per-tab-state, deep-nav→tab-remembers-depth
Predict: visit-return→hub-unchanged, tab-A-interact-tab-B-return→A-state-preserved, deep-nav-tab-switch-return→stack-intact
```
```

**Picker / Selection** (after violation tests, ~line 197):
```markdown
**Model template**:
```
State: selectedValue, originalValue(on-open), confirmed?
Writes: adjustable→selectedValue, doneButton→confirm(selectedValue), cancelButton→revert(originalValue)
Reads: valueDisplay←selectedValue
Coupling: done→propagate-to-caller, cancel→revert-to-original
Predict: select-done→caller-shows-new-value, select-cancel→caller-shows-original, done-without-change→original-preserved, boundary-increment→clamp-or-wrap
```
```

**Alert / Modal / Action Sheet** (after violation tests, ~line 223):
```markdown
**Model template**:
```
State: triggered?, parentScreenState(frozen)
Writes: confirmButton→execute-action+dismiss, cancelButton→dismiss-no-action, background-tap→dismiss(maybe)
Reads: parentScreen←frozen(non-interactive)
Coupling: confirm→parent-state-changes, cancel→parent-state-unchanged, background→blocked-or-dismiss
Predict: confirm→action-executes+modal-dismissed+parent-updated, cancel→no-change+modal-dismissed, background-tap→blocked(no-response)
```
```

**Canvas / Free-Form Interaction** (after violation tests, ~line 250):
```markdown
**Model template**:
```
State: content[], undoStack[], redoStack[], currentTool, zoomLevel
Writes: drawGesture→content.append, undoButton→content.pop+undoStack.push, redoButton→undoStack.pop+content.push, toolSelector→currentTool
Reads: canvas←content, undoButton.enabled←(content.length>0), redoButton.enabled←(undoStack.length>0)
Coupling: draw→clears-redoStack, undo→enables-redo, zoom→preserves-content-positions
Predict: draw-undo→content-removed, draw-undo-redo→content-restored, zoom-draw-unzoom→position-correct
```
```

#### 2. Update the "How to Use This" section
**File**: `ai-fuzzer/references/screen-intent.md`
**Lines**: 19-28 (How to Use This)
**Changes**: Add step 3.5 between "Record the intent" and "Run workflow tests":

Insert after step 3:
```markdown
4. **Build a behavioral model** using the matched intent's model template as a starting point. Fill in specific element names, current values, and observed coupling. Record in session notes `## Behavioral Models`.
```

Renumber subsequent steps (4→5, 5→6, 6→7).

#### 3. Update the Table of Contents
**File**: `ai-fuzzer/references/screen-intent.md`
**Changes**: The ToC doesn't need updating since model templates are subsections within existing sections, not new top-level sections.

### Success Criteria:
- [x] All 8 intent categories have a `**Model template**` block
- [x] "How to Use This" includes a model-building step (step 4)
- [x] Templates are concise (5 lines each) and use consistent format
- [x] No contradictions with existing workflow/violation tests

---

## Phase 3: Session Notes + Trace Format Integration

### Overview
Add recording structures so models and predictions survive compaction and are traceable for reproduction.

### Changes Required:

#### 1. Add `## Behavioral Models` to session notes template
**File**: `ai-fuzzer/references/session-notes-format.md`
**Position**: In the notes file format template, after `## Screen Intents` (which is referenced in SKILL.md but not in the template — we'll add it in the natural position after `## Coverage`)
**Changes**: Add a new section to the template:

Insert after the `## Coverage` section in the template (~after line 89):

```markdown
## Behavioral Models
### [Screen Name] ([Intent])
**State**: {variable: value, ...}
**Element-state map**:
- element → writes: stateVar (how)
- label ← reads: stateVar
**Coupling**: element.X ↔ element.Y (relationship)
**Predictions**:
- P1: [specific testable prediction] — status: confirmed|violated(F-N)|revised
- P2: [specific testable prediction] — status: pending
```

#### 2. Add optional prediction fields to trace `interact` entries
**File**: `ai-fuzzer/references/trace-format.md`
**Position**: In the interact entry type section, after the existing fields table (~line 151)
**Changes**: Add two optional fields to the interact entry:

Add to the fields table:
```
| `prediction` | no | What you expected: state changes, screen change, value changes. Short free-text. |
| `validation` | no | Match/mismatch result. If mismatch, describe the deviation. Reference finding ID if applicable. |
```

Add a brief example after the table showing an interact entry with prediction:
```yaml
# Example with prediction (optional fields)
prediction: "count 0→1, emptyLabel removed, field cleared, addButton disabled"
validation: "MATCH — all predictions confirmed"
```

And a mismatch example:
```yaml
prediction: "items persist, count still 1"
validation: "VIOLATED — count=0, items=[], emptyLabel returned. See F-1."
```

### Success Criteria:
- [x] session-notes-format.md template includes `## Behavioral Models` section
- [x] trace-format.md interact entry has optional `prediction` and `validation` fields
- [x] Fields are clearly marked optional (existing traces remain valid)
- [x] Examples show both match and mismatch cases

---

## Phase 4: Examples and Strategy Updates

### Overview
Demonstrate the prediction-driven approach in examples.md and reference modeling from the key strategy files.

### Changes Required:

#### 1. Add prediction-driven example to examples.md
**File**: `ai-fuzzer/references/examples.md`
**Position**: After the existing "Delta interpretation" section (~line 141), before "Detecting a crash"
**Changes**: Add a new section showing the full predict→validate cycle:

```markdown
## Prediction-driven testing in practice

### Example: Building a model for a todo list

You call `get_interface` and see:
- Text field: "What needs to be done?" (identifier: `todo.newItemField`, value: empty)
- Button: "Add" (identifier: `todo.addButton`, actions: [], value: nil) — no actions means disabled
- Label: "0 items remaining" (identifier: `todo.itemCount`)
- Label: "No todos yet" (identifier: `todo.emptyLabel`)
- Three filter buttons: "All" (selected), "Active", "Completed"

**Identify intent**: Item list. **Build model**:

```
State: {items: [], count: 0, filter: "All", emptyVisible: true}
Coupling: newItemField.text ↔ addButton.enabled, items.length → count, items.length==0 → emptyLabel.visible
```

**Predict + Act**:

Action 1: `type_text(identifier: "todo.newItemField", text: "Buy groceries")`
- **Predict**: addButton becomes enabled (gains actions), emptyLabel unchanged, count unchanged
- **Actual**: `valuesChanged` — addButton now has actions. **MATCH**.

Action 2: `activate(identifier: "todo.addButton")`
- **Predict**: items.append("Buy groceries"), count 0→1 ("1 item remaining"), emptyLabel removed, newItemField cleared, addButton disabled
- **Actual**: `elementsChanged` — new item element added, emptyLabel removed. `valuesChanged` — count now "1 item remaining", field cleared. **MATCH**.

Action 3: Navigate away (Back) then return
- **Predict**: items persist — count still "1 item remaining", "Buy groceries" still in list
- **Actual**: `screenChanged` to Todo List — count "0 items remaining", emptyLabel "No todos yet". **VIOLATED**.

**Investigate** (don't just record — probe deeper):
- **Reproduce**: Add another item, navigate away, return. Still empty. Consistent. (2/2)
- **Scope**: Do Settings persist? Navigate to Settings, change accent color, leave, return. Color preserved. So navigation persistence works for Settings but NOT for Todo items.
- **Reduce**: Is it *all* todo state or just items? Check: does the selected filter persist? No — filter resets to "All" too. Entire Todo screen state is ephemeral.
- **Finding F-1**: Todo List state (items + filter) not persisted across navigation. Settings state IS persisted. Confirmed 3/3.

Action 4: Complete "Buy groceries", switch to each filter
- **Predict**: "Active" filter → "No active todos", "Completed" filter → "No completed todos", "All" filter → "No todos" (following the pattern)
- **Actual**: Active→"No active todos" ✓, Completed→"No completed todos" ✓, All→"No all todos" ✗. **VIOLATED**.

**Investigate**:
- **Boundary**: The pattern "No {filter} todos" works for 2/3 filters. Only "All" breaks. Likely string interpolation without special-casing.
- **Finding F-2**: Empty state for "All" filter produces "No all todos" — grammatically broken. Other filters are correct.

The model made these findings *inevitable*. And investigation turned vague anomalies into precise, scoped bugs with confirmed reproduction rates.
```

#### 2. Update systematic-traversal.md
**File**: `ai-fuzzer/references/strategies/systematic-traversal.md`
**Position**: After "Screen Intent First" section (~line 11)
**Changes**: Add one paragraph:

```markdown
## Model Before Traversal

After identifying intent, **build a behavioral model** before element-by-element testing. The model generates predictions that make your testing targeted — instead of "activate and see what happens," you're validating specific expected behaviors. See `## Behavioral Modeling` in SKILL.md.
```

#### 3. Update state-exploration.md
**File**: `ai-fuzzer/references/strategies/state-exploration.md`
**Position**: After "State Consistency Checks" section (~line 75)
**Changes**: Add one paragraph:

```markdown
## Prediction-Driven State Checks

When performing state consistency checks (A→B→back-to-A), use your behavioral model to make predictions explicit. Instead of "compare with original interface," predict specifically: "element X should have value Y, count should be N, no elements should have been added or removed." Specific predictions catch subtle state leaks that a generic diff might miss (e.g., a value changed from "50" to "50.0" — same semantically but different string).
```

#### 4. Update the anti-patterns section in examples.md
**File**: `ai-fuzzer/references/examples.md`
**Position**: In the "Anti-patterns" section (~line 175)
**Changes**: Add a new anti-pattern about reactive testing:

```markdown
### The reactive testing trap

Bad (no predictions, no investigation):
```
activate addButton → elementsChanged, new item appeared. Looks fine.
navigate away → screenChanged. OK.
navigate back → screenChanged, list is empty. Hmm, that seems wrong? Filing as anomaly. Moving on.
```

Good (prediction-driven with investigation):
```
Model: items persist across navigation (Persistence prediction)
Predict: navigate away → return → items.length==1, count=="1 item remaining"
Act: navigate away, return
Validate: items.length==0, count=="0 items remaining" → PREDICTION VIOLATED
Investigate:
  Reproduce: add item, leave, return → still empty (2/2)
  Scope: do Settings persist? Yes → persistence is broken specifically for Todo state
  Reduce: filter also resets → entire screen state is ephemeral
Finding F-1: Todo List state not persisted. Settings ARE persisted. Confirmed 3/3.
```

The first version *might* catch the bug and records a vague anomaly. The second *always* catches it, then probes to understand scope (only Todo, not Settings), consistency (3/3), and extent (items + filter, not just items).
```

### Success Criteria:
- [x] examples.md has a complete prediction-driven testing example
- [x] examples.md has a "reactive testing trap" anti-pattern
- [x] systematic-traversal.md references behavioral modeling
- [x] state-exploration.md references prediction-driven state checks
- [x] All additions are consistent with existing content

---

## Verification

After all phases:
- [x] Read SKILL.md end-to-end — core loop has 7 steps, Behavioral Modeling section includes investigation protocol, line count < 500 (448)
- [x] Read screen-intent.md end-to-end — all 8 intents have model templates, "How to Use This" includes model step (step 4)
- [x] Read session-notes-format.md — template includes `## Behavioral Models`
- [x] Read trace-format.md — interact entry documents optional `prediction`/`validation` fields
- [x] Read examples.md — prediction-driven example and anti-pattern present
- [x] Read systematic-traversal.md and state-exploration.md — both reference modeling
- [x] No file exceeds its size budget (SKILL.md: 448, screen-intent: 355, examples: 271)
- [x] No contradictions between files

## References

- Previous plan: `thoughts/shared/plans/2026-02-19-fuzzer-claude-code-restructuring.md`
- Fuzzing session that motivated this: `ai-fuzzer/reports/report-2026-02-19-1346-state-exploration.md`
- Color picker investigation: `ai-fuzzer/reports/report-2026-02-19-1419-color-picker-investigation.md`

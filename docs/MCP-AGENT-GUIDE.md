# Button Heist MCP Agent Guide

Button Heist drives iOS apps through the accessibility layer — the same interface VoiceOver uses. You interact with live UI elements by their identity and traits, not screen coordinates. A coordinate that works on one device breaks on another; an element's label and traits work everywhere.

## Core Loop

1. **See** — `get_interface` returns every visible element with a heistId, label, value, traits, and actions.
2. **Act** — `activate`, `type_text`, `scroll`, `gesture` — target by heistId or matcher. Always attach `expect` when you know what should change.
3. **Read the response** — every response tells you two things: what your action did (`interfaceDelta`) and what changed while you were thinking (`[background: ...]`). If either answers your question, skip `get_interface`.
4. **Wait if needed** — when the delta shows a transient state (spinner, loading overlay) and your expectation wasn't met, call `wait_for_change` with the same expectation. The server rides through intermediate states and returns when the real change lands. If the change already happened in the background, `wait_for_change` returns instantly.
5. **Repeat** — only re-fetch when you need elements you haven't seen.

## Choosing Tools

**Observing**: `get_interface` for element data, `get_screen` for visual context. Start with `get_interface` — it explores the full screen by default, including off-screen content in scroll views. Reach for `get_screen` only when layout or visual state matters.

**Acting**: `activate` is your primary tool — it taps, toggles, follows links. `type_text` for keyboard input. `gesture` with type "swipe" for directional gestures. `scroll` for paging through lists. Prefer `activate` over `gesture` — raw coordinates are fragile and don't record well.

**Finding**: `scroll` with mode "to_visible" when you've seen an element before but it scrolled off-screen. `scroll` with mode "search" when you've never seen it — scrolls every container looking for a match. `wait_for` when you know a specific element will appear.

**Waiting**: `wait_for_change` when the UI is updating asynchronously — network requests, timers, animations completing. Pass an expectation object to wait for the specific outcome: `expect={"type":"screen_changed"}` rides through loading spinners until the real navigation happens. With no expectation, returns on any tree change. This is the correct response when your action produced a transient state (spinner appeared, interactive elements disappeared) and you need the final result.

**Composing**: `run_batch` for multi-step sequences in a single call. Attach `expect` to each step for inline verification.

## The Server Is Always Watching

Every response includes what changed since your last call. You never poll. Three things can happen between your tool calls:

**Nothing changed** — no `[background]` line, your heistIds are still valid, proceed.

**Elements changed** — `[background: elements changed +2 -1 (15 total)]` with the added/removed elements listed. Your heistIds are still valid. The delta shows what's new.

**Screen changed** — `[background: screen changed (7 elements)]` with the full new element list. Your heistIds are stale. Don't try to use them — read the new elements from the background block. If you had an `expect` on your action and it matches the background change, the action is skipped entirely and you get "expectation already met." If you didn't have an expect, the action is skipped with "Screen changed while you were thinking" and the response carries the new interface. Either way, you're never left pointing at a screen that doesn't exist.

**Async pattern** — for operations that take time (payments, network requests):
1. `activate pay_button expect={"type":"screen_changed"}` — tap and declare intent
2. Delta shows spinner, expectation not met → `wait_for_change expect={"type":"screen_changed"}` — server waits until the real screen arrives
3. Or: you were slow to act, payment already completed → your next call gets the confirmation instantly via background awareness. No wait needed.

## Expectations

Every action is an opportunity to validate. Attaching `expect` costs nothing — the action runs the same way — but turns a blind tap into a verified assertion. Agents that use expectations routinely catch regressions as a side effect of navigation. Agents that don't are just clicking and hoping.

Before you act, ask: what should change? A toggle flips a value. A nav button changes the screen. A delete removes an element. Form that hypothesis, attach it, and let the result confirm or correct you. Unmet expectations are information, not errors — they tell you what actually happened so you can adapt.

Expectations are as specific as you need — say what you know, omit what you don't:
- `{"type": "elements_changed"}` — something should change (broadest).
- `{"type": "element_updated"}` — some element's property should change.
- `{"type": "element_updated", "heistId": "counter"}` — this specific element should change.
- `{"type": "element_updated", "heistId": "counter", "property": "value"}` — its value specifically.
- `{"type": "element_updated", "heistId": "counter", "newValue": "5"}` — and it should become "5".

Each level narrows what counts as success. The more specific, the more a failure tells you.

## Recording Heists

`start_heist` / `stop_heist` capture your session as a replayable .heist file. The recording is automatic — every successful action becomes a step — but the quality depends entirely on how you approach it.

**Prime the interface first.** Call `get_interface` before your first action. The recorder converts heistIds to portable matchers behind the scenes, but needs cached element data to do it well.

**Attach expectations to every meaningful action.** Expectations are recorded with the step. A heist without expectations is a sequence of taps; a heist with expectations is a self-verifying test suite that validates on every replay.

**One action, one purpose.** Each step should do exactly one thing and verify it. Don't chain five taps and check at the end — check after each one. This makes replay failures precise: step 7 failed means the 7th interaction broke.

**Read the delta before moving on.** If your expectation wasn't met, understand why before continuing. The recording only captures successful actions — continuing after a missed expectation means the heist may not replay the same way.

## Efficiency

Read the delta first — skip `get_interface` when the delta already told you what changed. Use heistIds on the current screen, matchers after navigation. Filter with matcher fields or heistId lists when you only need a subset of elements.

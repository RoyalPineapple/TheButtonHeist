# Button Heist MCP Agent Guide

Button Heist drives iOS apps through the accessibility layer — the same interface VoiceOver uses. You interact with live UI elements by their identity and traits, not screen coordinates. A coordinate that works on one device breaks on another; an element's label and traits work everywhere.

## Core Loop

1. **Read** — `get_interface` returns the app accessibility state with heistIds, labels, values, traits, and actions.
2. **Act** — `activate`, `type_text`, `scroll`, `swipe`, and the other canonical action tools — target by heistId or matcher. Always attach `expect` when you know what should change.
3. **Read the response** — action responses carry trace-backed result evidence. If the delta answers your question, skip `get_interface`.
4. **Wait if needed** — when the delta shows a transient state (spinner, loading overlay) and your expectation wasn't met, call `wait_for_change` with the same expectation. The server checks the current state first, then watches settled changes until the expectation is true.
5. **Repeat** — only re-fetch when you need elements you haven't seen.

## Choosing Tools

**Observing**: `get_interface` for element data, `get_screen` for visual context plus fresh visible geometry. Start with `get_interface`; it returns the app accessibility state for the current screen, including content Button Heist can discover in scroll views. Pass `subtree.element` to project from a leaf, or `subtree.container` to project from a container. Reach for `get_screen` when layout, pixels, or the current viewport geometry matters.

**Acting**: `activate` is your primary tool — it taps, toggles, follows links. Use `action: "increment"` or `"decrement"` for adjustable controls, with optional `count` to repeat 1...100 times. `type_text` for keyboard input. Use direct gesture tools such as `swipe`, `drag`, and `one_finger_tap` when you need a gesture. `scroll` pages through lists. Prefer `activate` over gesture tools — raw coordinates are fragile and don't record well.

**Finding**: semantic actions resolve and reveal targets internally. Use `scroll_to_visible` when your intent is explicit viewport positioning, `element_search` when you want to search scroll content without acting, and `wait_for` when you know a specific element will appear.

**Waiting**: `wait_for_change` when the UI is updating asynchronously — network requests, timers, animations completing. Pass an expectation object to wait for the specific outcome: `expect={"type":"screen_changed"}` rides through loading spinners until the real navigation happens. With `expect`, the server first checks whether the current state already satisfies it, then blocks until a later settled scan does. With no expectation, returns on any tree change. This is the correct response when your action produced a transient state (spinner appeared, interactive elements disappeared) and you need the final result.

For `wait_for_change`, `element_disappeared` means the element is absent from the current settled hierarchy. It does not require Button Heist to prove the element existed and then vanished.

**Composing**: `run_batch` for multi-step sequences in a single call. Attach `expect` to each step for inline verification.

## Trace Semantics

Screen changes create full baselines. Same-screen changes are patches on top of the current baseline.

Actions can refresh off-screen state by exploring scroll views before or after the interaction, but that exploration is not a screen boundary by itself. It only broadens Button Heist's current-screen knowledge. If the app stays on the same screen, the action result is still an elements-changed patch; if Button Heist detects a real screen change, the trace starts a new full baseline.

`get_interface` returns app state. A default call may refresh discoverable off-screen content so the returned hierarchy is current. Passing `subtree` scopes that projection to the part of the hierarchy you asked for. `get_screen` is diagnostic: it returns pixels plus fresh visible geometry for the current viewport, not a replacement for the app-state hierarchy.

## Local MCP Development

Use this workflow when testing a worktree-local `ButtonHeistMCP` change through an MCP host.

**Build the worktree binary:**

```bash
cd ButtonHeistMCP
swift build -c release
```

The release binary is written to `ButtonHeistMCP/.build/release/buttonheist-mcp` in the current worktree.

**Know what `.mcp.json` loads.** The repo config starts `buttonheist` with `./scripts/buttonheist-mcp.sh`. That wrapper resolves its own directory, treats the parent as the repo root, and `exec`s that worktree's release binary. It does not build the server, choose a device, or rewrite environment variables; the MCP host's environment is inherited by the server process.

Start the MCP host or agent from the worktree you are testing. If a host loaded `.mcp.json` from another checkout, its relative `./scripts/buttonheist-mcp.sh` may still point at that checkout until the MCP session is restarted.

**Set target environment before starting the MCP host:**

- `BUTTONHEIST_DEVICE`: discovered device name, named target, or direct `host:port`. Use `127.0.0.1:<port>` for simulator direct-connect sessions that bypass Bonjour.
- `BUTTONHEIST_TOKEN`: auth token from `TheInsideJob`.
- `BUTTONHEIST_DRIVER_ID`: stable driver identity for session locking. Use a unique value per agent/session when multiple clients share a token.

Exporting these variables after the host has already launched does not update an already-running MCP server process. Start a fresh MCP session or agent after changing the target environment.

**Reload after rebuilds.** MCP hosts usually keep the server process alive for the lifetime of the loaded MCP session. Rebuilding `ButtonHeistMCP` updates the binary on disk, but an already-loaded server keeps running the old code. End the MCP session or start a fresh agent/host from this worktree after each rebuild. If tool behavior still matches the previous build after restarting, verify the host resolved `.mcp.json` from the correct worktree.

**Run against a simulator endpoint:**

```bash
TASK_SLUG="mcp-reload-debug"
SIM_UDID=$(xcrun simctl create "$TASK_SLUG" "iPhone 16 Pro")
xcrun simctl boot "$SIM_UDID"
xcrun simctl bootstatus "$SIM_UDID" -b

xcodebuild -workspace ButtonHeist.xcworkspace -scheme "BH Demo" \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/BHDemo.app | head -1)
xcrun simctl install "$SIM_UDID" "$APP"

INSIDEJOB_PORT=$((RANDOM % 10000 + 20000))

SIMCTL_CHILD_INSIDEJOB_PORT="$INSIDEJOB_PORT" \
SIMCTL_CHILD_INSIDEJOB_TOKEN="$TASK_SLUG" \
SIMCTL_CHILD_INSIDEJOB_ID="$TASK_SLUG" \
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp

export BUTTONHEIST_DEVICE="127.0.0.1:$INSIDEJOB_PORT"
export BUTTONHEIST_TOKEN="$TASK_SLUG"
export BUTTONHEIST_DRIVER_ID="$TASK_SLUG"
```

Then start the MCP host or agent from this worktree so `.mcp.json` resolves to the same build. For a one-off stdio smoke check outside a host:

```bash
BUTTONHEIST_DEVICE="127.0.0.1:$INSIDEJOB_PORT" \
BUTTONHEIST_TOKEN="$TASK_SLUG" \
BUTTONHEIST_DRIVER_ID="$TASK_SLUG" \
./scripts/buttonheist-mcp.sh
```

When the session is done, shut down and delete the dedicated simulator:

```bash
xcrun simctl shutdown "$SIM_UDID"
xcrun simctl delete "$SIM_UDID"
```

## Async Changes

For operations that take time (payments, network requests):
1. `activate pay_button expect={"type":"screen_changed"}` — tap and declare intent
2. Delta shows spinner, expectation not met → `wait_for_change expect={"type":"screen_changed"}` — server waits until the real screen arrives

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

`start_heist` / `stop_heist` capture your session as a replayable .heist file. The recording is automatic: a recorded step exists only after the action succeeded and its explicit expectation was satisfied. Actions without explicit expectations keep the existing successful-action recording behavior.

**Prime the interface first.** Call `get_interface` before your first action. The recorder converts heistIds to portable matchers behind the scenes, but needs current element data to do it well.

**Attach expectations to every meaningful action.** Expectations are recorded with the step. A heist without expectations is a sequence of taps; a heist with expectations is a self-verifying test suite that validates on every replay.

**One action, one purpose.** Each step should do exactly one thing and verify it. Don't chain five taps and check at the end — check after each one. This makes replay failures precise: step 7 failed means the 7th interaction broke.

**Read the delta before moving on.** If your expectation wasn't met, understand why before continuing. The recording skips actions with missed expectations, so continuing after one means the heist will omit that interaction.

## Efficiency

Read the delta first — skip `get_interface` when the delta already told you what changed. Use heistIds on the current screen, matchers after navigation. Pass `subtree` when you only need one subtree or one leaf from the current hierarchy.

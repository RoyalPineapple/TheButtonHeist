# Button Heist: Agent Troubleshooting Guide

Common problems agents hit and how to fix them.

## "Element not found"

### You're using a stale heistId

The most common cause. You carried a heistId across a screen transition — a navigation push, modal, tab switch, or any `screen_changed` delta. Every heistId from the previous screen is dead.

**Fix:** After a `screen_changed` delta, read the new heistIds from the delta's `newInterface`. If you need to find an element on the new screen, use a matcher (label, identifier, traits) instead.

### The element is off-screen

`get_interface` only returns what's currently visible. If the element is below the fold in a scroll view, it doesn't exist in the accessibility tree yet.

**Fix:** Use `scroll_to_visible` with a matcher to find it, or call `get_interface` with `full: true` to discover all off-screen content. See the "visibility problem" section in the Agent Guide.

### You predicted a heistId

HeistIds are assigned by the system — never construct or guess one. `"login-button"` might seem logical, but if the system assigned `"sign-in"` or `"button-Sign In"`, your guess is wrong.

**Fix:** Always use a heistId you were handed in a `get_interface` response or action delta. If you haven't seen the element yet, use a matcher.

### The element genuinely doesn't exist

The control may not be on this screen, may be conditionally hidden, or may require a prior action (e.g., expanding a section, switching a tab) before it appears.

**Fix:** Use `wait_for` if you expect it to appear after an async operation. Otherwise, call `get_interface` to see what's actually on screen and adjust your plan.

### Reading "element not found" diagnostics

The error message itself contains the recovery signal — read it carefully before retrying.

- **heistId miss with similar IDs:** `Element not found: "submit-btn"\nsimilar: submit-button, submit-label` — the ID you used is close but wrong. Use the suggested similar ID.
- **Matcher near-miss:** `No match for: label="Submit" traits=[button]\nnear miss: matched all fields except value — actual value=Disabled` — the element exists but one predicate is wrong. Fix the named field.
- **Total miss with screen dump:** `No match for: label="Submit"\n12 elements on screen:\n  label="Cancel" [button]\n  ...` — the element isn't on screen. Use the listed elements to reformulate your query.
- **Ambiguous match:** `3 elements match: label="OK"\n  "OK" id=ok-button\n  "OK" id=dialog-ok` — multiple elements match your predicate. Add `identifier` or `traits` to disambiguate.

These diagnostics give you enough to self-correct without calling `get_interface` again.

## "Element is disabled"

The element was found but has the `notEnabled` trait. The full message is `"Element is disabled (has 'notEnabled' trait)"`.

**Fix:** The element exists but isn't interactive in its current state. A prior action may be needed to enable it (filling required fields, accepting terms, etc.). Check the surrounding UI for prerequisites.

## "Auth mismatch" or "session locked"

### Session locked by another driver

`"Session is locked by another driver. Session will time out after Ns of inactivity."` — another agent owns this app instance. The message includes the exact timeout duration.

**Fix:** Don't change the token. Find *your* simulator. Check which simulators are running with `xcrun simctl list devices booted`. Connect to the one matching your task slug. If you don't have a dedicated simulator, create one.

### Invalid token

`"Invalid token. Retry without a token to request a fresh session."` — the token doesn't match the app's configured token.

**Fix:** If you launched the app with `SIMCTL_CHILD_INSIDEJOB_TOKEN`, use that exact value. If you're hitting a simulator you didn't launch, find yours instead.

### Too many failed attempts

`"Too many failed attempts. Try again later."` — after 5 failed auth attempts, the server locks out for 30 seconds. The message doesn't include the duration.

**Fix:** Wait 30 seconds, then retry. Don't loop — each failed retry during lockout extends nothing but wastes time. If you're repeatedly hitting this, you're connecting to the wrong app instance.

## "No devices found"

### Bonjour is blocked

On managed machines (MDM stealth mode), Bonjour discovery is disabled. `list_devices` will return nothing even when apps are running.

**Fix:** Use a direct `host:port` address instead of relying on discovery. If you know the port, connect explicitly:
```json
{"tool": "connect", "arguments": {"device": "127.0.0.1:1455", "token": "my-token"}}
```

Or use a `.buttonheist.json` config file with named targets.

### The app isn't running

The iOS app with TheInsideJob embedded must be running in the simulator or on a device before you can connect.

**Fix:** Build and launch the app first. Check with `xcrun simctl list devices booted` that the simulator is up.

### Recovering port and token from logs

If the app is running but you don't know the port or token (e.g., launched without explicit env vars), read them from the simulator logs:

```bash
xcrun simctl spawn $SIM_UDID log show \
  --predicate 'subsystem == "com.buttonheist.theinsidejob" AND category == "server"' \
  --last 5m --style compact 2>&1 | grep -E "listening on port|Auth token|Instance ID"
```

This shows three lines:
- `Server listening on port 23456` — the TCP port
- `Auth token: abc123...` — the token to pass as `BUTTONHEIST_TOKEN`
- `Instance ID: accra-task` (or an 8-char hex fallback if none was set)

Then connect directly:
```bash
BUTTONHEIST_DEVICE="127.0.0.1:<port>" BUTTONHEIST_TOKEN="<token>" buttonheist session
```

## Text input failures

### "No active text input after tapping element"

The element was tapped to focus it, but no keyboard appeared. The element may not actually be a text field — it could be a label or button that looks like an input.

**Fix:** Check the element's traits in `get_interface`. A real text field has the `textEntry` trait. If the element lacks this trait, look for a sibling or child that is the actual input.

### "No keyboard or focused text input available"

No text field is focused. Either the keyboard dismissed between actions, or no text field was ever tapped.

**Fix:** Provide an `elementTarget` to `type_text` so it taps the field first. Don't assume a previous activation kept the keyboard open — animations, alerts, or screen changes can dismiss it.

## Scroll failures

### "No scrollable ancestor found for element"

The element you targeted for scroll isn't inside a scroll view. Static content and fixed headers can't be scrolled.

**Fix:** Target a different element that's actually inside the scrollable area, or use `get_interface` with `full: true` to see the hierarchy and identify the scrollable container.

### "Already at edge"

The scroll view is already at the boundary you're scrolling toward. Further scrolling in that direction has no effect.

**Fix:** This is informational, not a failure. If you're searching for content, it's not in this scroll direction. Try the opposite direction, or use `scroll_to_visible` which handles bidirectional search automatically.

## Action succeeded but nothing changed

The delta kind is `noChange` after your action.

### The element didn't respond

Some elements look tappable but don't have an accessibility activation path. Static text, decorative images, and container views won't respond to `activate`.

**Fix:** Check the element's traits and actions in the `get_interface` output. If it has no `activate` action and no interactive traits (`button`, `link`, `textEntry`), it's not a control. Look for the actual interactive element nearby — it may be a parent or sibling.

### The action is too fast

Rapid sequential actions can outrun the UI. If you activate a button that triggers an animation or network request, the delta is computed before the UI settles.

**Fix:** Use `wait_for` to wait for the expected result, or `wait_for_idle` to let animations complete before checking state.

### You activated the wrong element

With matchers, a substring match might hit a different element than intended. `"label": "Sign"` matches both "Sign In" and "Sign Up".

**Fix:** Use more specific matchers. Add `traits` to narrow the match. Or use heistIds from a prior `get_interface` call for zero ambiguity.

## Expectation failed

Expectation input uses snake_case (`screen_changed`, `elements_changed`), but the output in error messages uses camelCase (`screenChanged`, `elementsChanged`, `noChange`). Both refer to the same delta kinds.

### "expected screenChanged, got elementsChanged"

The action changed elements on the current screen but didn't navigate. The button may update in-place rather than pushing a new screen (e.g., an inline form validation, a disclosure toggle, a state change).

**Fix:** Read the delta to see what actually changed. If the behavior is correct, adjust your expectation to `"elements_changed"` or use `elementUpdated` to check the specific change. Note: `screen_changed` is strict — `elements_changed` is more lenient because a `screenChanged` delta also satisfies `elements_changed`.

### "expected elementUpdated, got no element updates"

The screen may have changed (navigation) rather than individual elements updating. Or the element you expected to change didn't.

**Fix:** Check the delta kind. If it's `screenChanged`, the entire interface was replaced — individual element updates aren't tracked across screen transitions. If it's `noChange`, the action may not have had the expected effect.

### "expected elementsChanged, got noChange"

The action completed successfully but nothing in the accessibility tree changed. This can happen with actions that affect non-accessible state (analytics, logging, background tasks) or when an animation is still in progress.

**Fix:** If the change is async, use `wait_for` to wait for the expected element state, then check. If the action genuinely has no visible effect, drop the expectation.

## Batch stopped early

### "failed at step N"

With `stop_on_error` policy (the default), a step failed or its expectation wasn't met, halting the batch.

**Fix:** Check the step summary. If the failure is an unmet expectation on a step where the action itself succeeded, decide whether to relax the expectation or switch to `continue_on_error`. If the action failed (element not found, delivery failure), fix the targeting or ordering.

### HeistIds go stale mid-batch

If a batch step causes a `screen_changed`, all heistIds from earlier steps are invalid. Subsequent steps using those heistIds will fail with "element not found".

**Fix:** After a screen-changing step in a batch, switch to matchers for the remaining steps. Or split the batch at the navigation boundary — batch the pre-navigation steps, read the new interface from the delta, then batch the post-navigation steps with fresh heistIds.

## "Connection timeout"

The connection to the app took too long or the app stopped responding.

### The app crashed or was suspended

Simulators suspend background apps. If the app was backgrounded or the simulator was paused, the TCP connection drops.

**Fix:** Check if the app is still running. Relaunch if needed. For long-running tasks, keep the app in the foreground.

### Session timeout

Sessions expire after 60 seconds of inactivity by default. If you go too long between commands, the session is released.

**Fix:** This is intentional — it prevents stale sessions from blocking other agents. Reconnect and continue. If you need longer idle windows, the `BUTTONHEIST_SESSION_TIMEOUT` environment variable controls the timeout.

## "Protocol mismatch"

`"Protocol mismatch: expected 1.2, got 1.1"` — the CLI/MCP version doesn't match the app version. This happens when you rebuild one side but not the other.

**Fix:** Rebuild both sides from the same commit. Rebuild the CLI (`cd ButtonHeistCLI && swift build -c release`), rebuild the app (`xcodebuild ... build`), and reinstall. The two version strings in the error tell you which side is behind.

## "Action timed out — connection lost"

The connection dropped mid-action. Different from initial connection timeout — this means a previously working connection broke.

**Fix:** The app may have crashed, been killed by the OS, or the simulator was shut down. Check `xcrun simctl list devices booted` to see if the simulator is still up. If it is, check if the app process is running. Relaunch if needed. TheFence will attempt to reconnect automatically if `autoReconnect` is enabled (the MCP server default).

## General debugging strategy

When something goes wrong:

1. **Read the error message.** Diagnostic messages include near-misses, similar IDs, screen dumps, and exact field mismatches. The recovery signal is in the error text itself.
2. **Read the delta.** It tells you what actually happened, not what you expected.
3. **Call `get_interface`.** See what's actually on screen right now.
4. **Check the heistId lifetime.** Did a screen change invalidate your IDs?
5. **Check element traits and actions.** Is the element actually interactive? Does it have the `textEntry` trait for text input? The `notEnabled` trait for disabled state?
6. **Check which simulator you're connected to.** Auth errors mean wrong target, not wrong credentials.
7. **Don't retry blindly.** If an action failed, the same action will fail again. Read the error, adjust, then retry.

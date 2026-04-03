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

## "Auth mismatch" or "session locked"

This means you're talking to the wrong simulator. Another agent (or a previous session) owns that connection. You haven't failed to authenticate — you've connected to someone else's app instance.

**Fix:** Don't change the token. Find *your* simulator. Check which simulators are running with `xcrun simctl list devices booted`. Connect to the one matching your task slug. If you don't have a dedicated simulator, create one.

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

## Action succeeded but nothing changed

The delta says `no change` after your action.

### The element didn't respond

Some elements look tappable but don't have an accessibility activation path. Static text, decorative images, and container views won't respond to `activate`.

**Fix:** Check the element's traits and actions in the `get_interface` output. If it has no `{tap}` action and no interactive traits (`[button]`, `[link]`, `[textField]`), it's not a control. Look for the actual interactive element nearby — it may be a parent or sibling.

### The action is too fast

Rapid sequential actions can outrun the UI. If you activate a button that triggers an animation or network request, the delta is computed before the UI settles.

**Fix:** Use `wait_for` to wait for the expected result, or `wait_for_idle` to let animations complete before checking state.

### You activated the wrong element

With matchers, a substring match might hit a different element than intended. `"label": "Sign"` matches both "Sign In" and "Sign Up".

**Fix:** Use more specific matchers. Add `traits` to narrow the match. Or use heistIds from a prior `get_interface` call for zero ambiguity.

## Expectation failed

### "expected screen_changed, got elementsChanged"

The action changed elements on the current screen but didn't navigate. The button may update in-place rather than pushing a new screen (e.g., an inline form validation, a disclosure toggle, a state change).

**Fix:** Read the delta to see what actually changed. If the behavior is correct, adjust your expectation to `"elements_changed"` or use `elementUpdated` to check the specific change.

### "expected elementUpdated, got no element updates"

The screen may have changed (navigation) rather than individual elements updating. Or the element you expected to change didn't.

**Fix:** Check the delta kind. If it's `screenChanged`, the entire interface was replaced — individual element updates aren't tracked across screen transitions. If it's `noChange`, the action may not have had the expected effect.

### "expected elements_changed, got noChange"

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

## General debugging strategy

When something goes wrong:

1. **Read the delta.** It tells you what actually happened, not what you expected.
2. **Call `get_interface`.** See what's actually on screen right now.
3. **Check the heistId lifetime.** Did a screen change invalidate your IDs?
4. **Check element traits and actions.** Is the element actually interactive?
5. **Check which simulator you're connected to.** Auth errors mean wrong target, not wrong credentials.

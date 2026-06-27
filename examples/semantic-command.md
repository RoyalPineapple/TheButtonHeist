# Semantic Command Example

Start with the accessibility contract and act through semantic intent.

```bash
buttonheist get_interface

buttonheist activate \
  --label "Continue" \
  --traits button
```

`activate` performs accessibility activation. The Button Heist resolves the target,
reveals it if needed, refreshes live accessibility geometry, calls
`accessibilityActivate()` once, waits for the interface to settle, and returns
trace-backed evidence. If UIKit declines the accessibility activation,
The Button Heist dispatches at the fresh activation point as part of the same
semantic command. Use a heist plan when the command should carry an executable
expectation.

Use `one_finger_tap`, `swipe`, `drag`, or `scroll` only when the physical
gesture or viewport state is the durable intent.

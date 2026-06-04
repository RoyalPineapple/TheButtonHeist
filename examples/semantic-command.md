# Semantic Command Example

Start with the semantic interface, act through accessibility intent, and attach
the expected contract outcome.

```bash
buttonheist get_interface

buttonheist activate \
  --label "Continue" \
  --traits button \
  --expect '{"type":"screen_changed"}'
```

`activate` performs accessibility activation. Button Heist resolves the target,
reveals it if needed, executes through the accessibility contract, waits for the
interface to settle, and returns trace-backed evidence.

Use `one_finger_tap`, `swipe`, `drag`, or `scroll` only when the physical
gesture or viewport state is the durable intent.


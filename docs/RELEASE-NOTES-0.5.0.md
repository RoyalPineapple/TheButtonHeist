# Button Heist 0.5.0 Release Notes

0.5.0 is a pre-1.0 accessibility contract runtime milestone, not an API freeze.

Button Heist now presents one product model from docs to runtime: agents express
semantic UI intent, Button Heist owns accessibility resolution, reveal,
activation delivery, settling, evidence, recording, and replay diagnostics.

## Highlights

- `activate` is documented and reported as accessibility activation.
- `wait` is documented as predicate + timeout over settled accessibility observations.
- Recorded heists are semantic tests: successful action evidence becomes a durable step and expectation.
- `run_heist` reports structured heist nodes instead of a flat command transcript.
- Mechanical gestures and viewport commands are documented as explicit escape hatches, not the normal route for controls.

## Compatibility Notes

Flat report rows, where still needed by playback or reporter adapters, are
derived from the structured heist report tree. They are not the heist model.

Full self-healing repair, final Swift DSL stability, and the accessibility
validation report are intentionally outside 0.5.0.

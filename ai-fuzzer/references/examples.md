# MCP Tool Response Examples

Concrete examples of what ButtonHeist MCP tool responses look like and how to interpret them.

## get_interface response

Returns an `elements` array and a `tree` array. Each element has:

```json
{
  "identifier": "buttonheist.actions.primaryButton",
  "label": "Primary Action",
  "value": null,
  "frameX": 16.0,
  "frameY": 352.0,
  "frameWidth": 361.0,
  "frameHeight": 44.0,
  "actions": ["activate"]
}
```

Key fields:
- **identifier**: Stable across runs. Use for targeting when available.
- **label**: Human-readable text. Use for understanding what the element is.
- **value**: Current value for adjustable elements (sliders show "50%", toggles show "0"/"1").
- **frame**: Position and size in points. Use for coordinate-based targeting.
- **actions**: Available accessibility actions. Elements with `["activate"]` are tappable. Elements with `["increment", "decrement"]` are adjustable.

## Detecting a screen transition

**Before tap**: 8 elements, identifiers include `{home, settings, profile, search}`
**After tap on "settings"**: 12 elements, identifiers include `{back, theme, notifications, privacy}`

The element sets are completely different → this is a **new screen**. Record the transition:
- From: "Main Menu" (fingerprint: {home, settings, profile, search})
- Action: tap(identifier: "settings")
- To: "Settings" (fingerprint: {back, theme, notifications, privacy})

## Detecting NO transition

**Before tap**: 8 elements including `{toggle1}` with value "0"
**After tap on toggle1**: 8 elements including `{toggle1}` with value "1"

Same elements, only a value changed → **same screen**, value updated. This is expected behavior for a toggle.

## Detecting a crash

```
Tool call: tap(identifier: "deleteButton")
Error: "MCP server disconnected" / connection refused / tool not available
```

Any MCP tool failure after the connection was previously working = **CRASH**. The app died. Record immediately.

## Detecting an anomaly

**Before tap on "saveButton"**: Elements include `{saveButton, cancelButton, nameField}`
**After tap**: Elements include `{cancelButton, nameField}` — saveButton is GONE

An element disappeared after an action that shouldn't have removed it → **ANOMALY**. Record it.

## Adjustable element values

**Slider before increment**: value "50"
**After increment**: value "60"
**After 5 more increments**: value "100" (stops increasing — hit max)
**After decrement**: value "90"

Track the value progression. If increment past max wraps to 0, that's an ANOMALY.

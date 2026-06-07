# ButtonHeist CLI

The CLI is the terminal adapter for Button Heist. It routes through
`TheFence.Command`, the same product command contract used by JSON-lines stdin,
MCP, and heist execution.

This README covers build, targeting, and common workflows. It does not maintain
a hand-written command or parameter catalog.

Generated references:

- [Command Reference](../docs/reference/commands.md) - canonical commands,
  CLI exposure, heist execution eligibility, and parameters
- [MCP Tool Reference](../docs/reference/mcp-tools.md) - MCP adapter tools
- [API](../docs/API.md) - product invariants and integration context

## Build

```bash
cd ButtonHeistCLI
swift build -c release
```

Binary:

```bash
.build/release/buttonheist
```

## Device Targeting

All device-backed commands accept `--device <filter>`. The filter matches
discovered metadata such as service name, app name, device name, short ID,
installation ID, instance ID, simulator UDID, or a named target from config.

```bash
buttonheist --device a1b2 get_interface
buttonheist --device demo activate --identifier loginButton
```

Without `--device`, direct commands require exactly one reachable target.

## Command Surface

Run local help for executable usage:

```bash
buttonheist --help
buttonheist <command> --help
```

The checked-in command contract is generated in
[Command Reference](../docs/reference/commands.md). If this README and the
generated reference disagree, the generated reference wins.

## Workflows

### Inspect and Act

```bash
buttonheist get_interface
buttonheist activate --label "Sign In" --traits button
buttonheist type_text "user@example.com" --identifier emailField
```

Semantic commands identify elements by matcher fields. Button Heist resolves
the target, moves the viewport if needed, refreshes, and uses fresh live
geometry before acting.

### Viewport and Screenshots

```bash
buttonheist scroll --direction down
buttonheist scroll_to_visible --identifier submitButton
buttonheist get_screen --output screen.png
```

Explicit viewport commands expose viewport state because moving the viewport is
the command's purpose. They are not setup for ordinary semantic actions.
Screenshots write artifact files by default; inline PNG data is an explicit raw
output mode.

### Replay Authored Heists

```bash
buttonheist run_heist --path checkout.heist --junit report.xml
```

Heist replay uses durable semantic selectors and matchers. Capture-local
annotations are evidence and diagnostics, not replay identity. The `.heist`
package is an authored replay artifact.

### JSON-Lines Mode

`buttonheist json_lines` keeps a single connection open and accepts canonical
JSON requests on stdin.

```bash
buttonheist json_lines
echo '{"command":"get_interface"}' | buttonheist json_lines
echo '{"command":"run_heist","version":1,"body":[{"type":"action","action":{"command":{"type":"activate","payload":{"label":"Sign In","traits":["button"]}}}}]}' | buttonheist json_lines
```

JSON-lines mode auto-reconnects after connection loss, then the next command
refreshes state through the same Fence path.

## Environment

| Variable | Description |
|----------|-------------|
| `BUTTONHEIST_DEVICE` | Default device filter or named target |
| `BUTTONHEIST_TOKEN` | Auth token |
| `BUTTONHEIST_DRIVER_ID` | Driver identity for session locking |
| `BUTTONHEIST_SESSION_TIMEOUT` | Idle timeout for `buttonheist json_lines` |

Flags take precedence over environment variables.

## Output

Standalone commands default to human-readable text on a TTY and JSON when
piped. JSON-lines mode defaults to JSON. Use `--format human` or `--format json`
to choose explicitly.

Status messages go to stderr.

## See Also

- [MCP Server](../ButtonHeistMCP/)
- [Command Reference](../docs/reference/commands.md)
- [Project Overview](../README.md)

# ButtonHeistCLI - The CLI

> **Module:** `ButtonHeistCLI/Sources/`
> **Platform:** macOS 14.0+
> **Role:** User-facing command-line interface for direct commands and persistent sessions

## Responsibilities

This is the public face of the outfit. The CLI is what you hand to a human operator who wants to work the scene directly:

1. **Subcommand routing** via `swift-argument-parser`
2. **Direct commands** through `CLIRunner` — creates a `TheFence`, connects, executes, disconnects
3. **Persistent sessions** through `ReplSession` and `TheFence`
4. **Output auto-detection**: human for TTY, JSON for piped input/output. Also supports `compact` format for terse machine-readable output.
5. **Access to both high-level commands and raw JSON session requests**

## Architecture Diagram

```mermaid
graph TD
    subgraph CLI["ButtonHeistCLI"]
        Main["main.swift - AsyncParsableCommand"]
        Options["ConnectionOptions - --device, --token, --quiet"]
        Format["OutputFormat - human / json / compact (.auto is computed)"]

        subgraph Commands["Subcommands"]
            ListDevices["list_devices"]
            Activate["activate --action increment/decrement/custom"]
            EditAction["edit_action copy/paste/cut/select/selectAll"]
            DismissKeyboard["dismiss_keyboard"]
            Scroll["scroll / scroll_to_visible / scroll_to_edge"]
            Touch["touch - one_finger_tap / long_press / swipe / drag / pinch / rotate / two_finger_tap"]
            TypeCmd["type_text"]
            GetScreen["get_screen"]
            GetInterface["get_interface"]
            WaitForChange["wait_for_change"]
            WaitFor["wait_for"]
            Record["start_recording / stop_recording"]
            Pasteboard["set_pasteboard / get_pasteboard"]
            Session["session - ReplSession"]
        end

        subgraph Patterns["Connection Patterns"]
            Direct["CLIRunner - TheFence → connect → execute → disconnect"]
            REPL["ReplSession -> TheFence - persistent JSON/human command loop"]
        end
    end

    ListDevices --> Direct
    Activate --> Direct
    EditAction --> Direct
    DismissKeyboard --> Direct
    Scroll --> Direct
    Touch --> Direct
    TypeCmd --> Direct
    GetScreen --> Direct
    GetInterface --> Direct
    WaitForChange --> Direct
    WaitFor --> Direct
    Record --> Direct
    Pasteboard --> Direct
    Session --> REPL

    Direct --> TheFence["TheFence"]
    REPL --> TheFence
```

## Connection Patterns

```mermaid
flowchart LR
    subgraph Direct["Direct Commands"]
        D1["CLIRunner"] --> D2["makeFence + start"]
        D2 --> D3["fence.execute(request:)"]
        D3 --> D4["outputResponse"]
        D4 --> D5["fence.stop()"]
    end

    subgraph Session["Session Mode"]
        S1["ReplSession"] --> S2["TheFence"]
        S2 --> S3["persistent connection"]
        S3 --> S4["read stdin"]
        S4 --> S5["execute command"]
        S5 --> S6["write stdout"]
        S6 --> S4
    end
```

## MCP Parity

The CLI is designed to mirror the MCP tool surface. Key mappings:

| MCP Tool | CLI Command | Notes |
|----------|-------------|-------|
| `activate` | `activate` | Direct match; `--action` for increment/decrement/custom |
| `gesture` | `touch` | Grouped gestures (swipe, one_finger_tap, drag, etc.) |
| `scroll` (mode: page) | `scroll` | Direct match |
| `scroll` (mode: to_visible/search/to_edge) | `scroll_to_visible` / `scroll_to_edge` | CLI keeps separate commands |
| `edit_action` | `edit_action` | Direct match for copy/paste/cut/select/selectAll |
| `edit_action` (action: dismiss) | `dismiss_keyboard` | CLI has separate command |
| `wait_for` | `wait_for` | Direct match; matcher-only (no --heist-id) |
| `run_batch`, `get_session_state` | `session` (REPL only) | Available via JSON input in session mode |
| `connect` | `session` (REPL only) | Switch connection target at runtime |
| `list_targets` | `session` (REPL only) | List configured targets from config file |

## Session Notes

- Human mode supports aliases such as `tap`, `ui`, `screen`, `idle`, `wait`, and `devices`
- JSON mode accepts canonical Fence commands such as `one_finger_tap`, `run_batch`, and `get_session_state`
- `session` is the bridge used under the hood by REPL-like workflows; the MCP server talks to `TheFence` directly rather than shelling out to the CLI

## Exit Code Contract

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Action failed (explicit `Darwin.exit(1)` in `CLIRunner.exitOnActionFailure`) or unhandled error (swift-argument-parser default) |

## Risks / Gaps

- Session mode exposes more raw power than the top-level flags, so documentation needs to keep both surfaces aligned

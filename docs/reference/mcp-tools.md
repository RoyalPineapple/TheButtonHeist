# ButtonHeist MCP Tool Reference

_Generated from `TheFence.Command.descriptors`._

## Summary

| Tool | Family | Description |
|------|--------|-------------|
| `connect` | `session` | Establish or switch the active connection to a Button Heist app. |
| `describe_heist` | `heistRuntime` | Describe one root entry or reusable heist from a runtime-validated plan. The `heist` parameter selects the entry/capability name; the plan can be supplied as canonical ButtonHeist source via `plan` or loaded from a `path` to a .heist package artifact. |
| `get_interface` | `observation` | Read the app accessibility hierarchy, optionally scoped to a subtree. |
| `get_pasteboard` | `observation` | Read text from the general pasteboard. |
| `get_screen` | `observation` | Capture a PNG screenshot with optional inline data and interface state. |
| `get_session_state` | `session` | Inspect connection, device, and last-action session state. |
| `list_heists` | `heistRuntime` | List a summary menu of the root entry and named reusable heists derived from one runtime-validated plan. Set `detail` to `detailed` to include derived command names, nested heist calls, counts, and safe semantic surface summaries. The plan can be supplied as canonical ButtonHeist source via `plan` or loaded from a `path` to a .heist package artifact. |
| `perform` | `heistRuntime` | Perform exactly one primitive ButtonHeist step from `step` source. The fence wraps it as `HeistPlan { <step> }`, compiles it through ThePlans, requires one action or simple WaitFor step, then executes it through the heist runtime. Use run_heist for branching, loops, named heists, warnings, failures, or multiple steps. |
| `run_heist` | `heistRuntime` | Execute a typed heist plan, supplied as canonical ButtonHeist source via `plan`, or loaded by the fence from a `path` to a .heist package artifact. Provide exactly one source: path or plan. Use `argument` when the root heist declares a string or element_target parameter. |

## Details

### `connect`

Establish or switch the active connection to a Button Heist app.

- Family: `session`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `target` | `string` | no | - | - |
| `device` | `string` | no | - | - |
| `token` | `string` | no | - | - |

### `describe_heist`

Describe one root entry or reusable heist from a runtime-validated plan. The `heist` parameter selects the entry/capability name; the plan can be supplied as canonical ButtonHeist source via `plan` or loaded from a `path` to a .heist package artifact.

- Family: `heistRuntime`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `heist` | `string` | yes | - | - |
| `path` | `string` | no | - | - |
| `plan` | `string` | no | - | - |

### `get_interface`

Read the app accessibility hierarchy, optionally scoped to a subtree.

containerName is ButtonHeist's generated name for a container in the current interface capture. It is useful for inspection and viewport/debug commands. It is not a semantic target or durable heist selector.

- Family: `observation`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `label` | `string` | no | - | - |
| `identifier` | `string` | no | - | - |
| `value` | `string` | no | - | - |
| `traits` | `stringArray` | no | - | - |
| `excludeTraits` | `stringArray` | no | - | - |
| `subtree` | `object` | no | - | - |
| `detail` | `string` | no | - | `summary`, `full` |

### `get_pasteboard`

Read text from the general pasteboard.

- Family: `observation`

Parameters:

_None._

### `get_screen`

Capture a PNG screenshot with optional inline data and interface state.

- Family: `observation`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `output` | `string` | no | - | - |
| `inlineData` | `boolean` | no | - | - |
| `includeInterface` | `boolean` | no | - | - |

### `get_session_state`

Inspect connection, device, and last-action session state.

- Family: `session`

Parameters:

_None._

### `list_heists`

List a summary menu of the root entry and named reusable heists derived from one runtime-validated plan. Set `detail` to `detailed` to include derived command names, nested heist calls, counts, and safe semantic surface summaries. The plan can be supplied as canonical ButtonHeist source via `plan` or loaded from a `path` to a .heist package artifact.

- Family: `heistRuntime`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `detail` | `string` | no | `"summary"` | `summary`, `detailed` |
| `path` | `string` | no | - | - |
| `plan` | `string` | no | - | - |

### `perform`

Perform exactly one primitive ButtonHeist step from `step` source. The fence wraps it as `HeistPlan { <step> }`, compiles it through ThePlans, requires one action or simple WaitFor step, then executes it through the heist runtime. Use run_heist for branching, loops, named heists, warnings, failures, or multiple steps.

- Family: `heistRuntime`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `step` | `string` | yes | - | - |

### `run_heist`

Execute a typed heist plan, supplied as canonical ButtonHeist source via `plan`, or loaded by the fence from a `path` to a .heist package artifact. Provide exactly one source: path or plan. Use `argument` when the root heist declares a string or element_target parameter.

- Family: `heistRuntime`

Parameters:

| Parameter | Type | Required | Default | Values |
|-----------|------|----------|---------|--------|
| `argument` | `object` | no | - | - |
| `path` | `string` | no | - | - |
| `plan` | `string` | no | - | - |


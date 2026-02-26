# ButtonHeistMCP - Performance Improvement Plan

## Summary

Fix all flagged review items: version alignment, video data handling, schema validation, and TheFence rename.

## Phase 1: Align Version Numbers

- [x] **Create shared version constant** in TheScore or ButtonHeist framework:
   ```swift
   public let buttonHeistVersion = "2.1.0"
   ```
- [x] **Update `ButtonHeistMCP/Sources/main.swift`** to use shared constant
- [x] **Update `ButtonHeistCLI/Sources/main.swift`** to use shared constant
- [x] **Build passes** after phase

## Phase 2: Document Video Data Omission

- [x] **Update `ToolDefinitions.swift`** — explain video data is summarized, not returned raw
- [x] **Add code comment in `main.swift`** explaining the decision
- [x] **Document CLI alternative** for agents needing actual video files

## Phase 3: Add Per-Command Schema Validation

- [x] **Add `validateArgs(command:args:)` function** before calling TheFence
- [x] **Validate target parameters** for tap/activate/increment/decrement commands
- [x] **Clear error messages** for missing parameters
- [x] **Build passes** after phase

### Files affected:
- `main.swift` — add validation before `fence.execute()`

## Phase 4: Update for TheFence Rename

- [x] **Update `main.swift`** — import and reference TheFence (already done by Batch 5)
- [x] **Update environment variable names** if they change (no changes needed, env vars unchanged)
- [x] **Build passes** after phase

## Verification

- [x] Shared version constant used by both CLI and MCP
- [x] Video data handling documented in tool description
- [x] Required parameter validation before dispatch
- [x] Clear error messages for missing parameters
- [x] TheFence references updated throughout
- [x] MCP builds: `cd ButtonHeistMCP && swift build -c release`

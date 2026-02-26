# ButtonHeistMCP - Performance Improvement Plan

## Summary

Fix all flagged review items: version alignment, video data handling, schema validation, and TheFence rename.

## Phase 1: Align Version Numbers

- [ ] **Create shared version constant** in TheScore or ButtonHeist framework:
   ```swift
   public let buttonHeistVersion = "2.1.0"
   ```
- [ ] **Update `ButtonHeistMCP/Sources/main.swift`** to use shared constant
- [ ] **Update `ButtonHeistCLI/Sources/main.swift`** to use shared constant
- [ ] **Build passes** after phase

## Phase 2: Document Video Data Omission

- [ ] **Update `ToolDefinitions.swift`** — explain video data is summarized, not returned raw
- [ ] **Add code comment in `main.swift`** explaining the decision
- [ ] **Document CLI alternative** for agents needing actual video files

## Phase 3: Add Per-Command Schema Validation

- [ ] **Add `validateArgs(command:args:)` function** before calling TheFence
- [ ] **Validate target parameters** for tap/activate/increment/decrement commands
- [ ] **Clear error messages** for missing parameters
- [ ] **Build passes** after phase

### Files affected:
- `main.swift` — add validation before `fence.execute()`

## Phase 4: Update for TheFence Rename

- [ ] **Update `main.swift`** — import and reference TheFence
- [ ] **Update environment variable names** if they change
- [ ] **Build passes** after phase

## Verification

- [ ] Shared version constant used by both CLI and MCP
- [ ] Video data handling documented in tool description
- [ ] Required parameter validation before dispatch
- [ ] Clear error messages for missing parameters
- [ ] TheFence references updated throughout
- [ ] MCP builds: `cd ButtonHeistMCP && swift build -c release`

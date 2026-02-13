# Text Entry via Keyboard Key Tapping - Implementation Plan

## Overview

Add a `typeText` command that enables AI agents to type, delete, and correct text in iOS text fields — character-by-character by tapping individual keyboard keys on the iOS software keyboard. This mirrors how KIF (Keep It Functional) handles text entry.

The critical design goal is a **tight feedback loop for remote AI agents**: every type operation returns the current text field value in the response, so the agent can verify what was typed and make corrections without needing a separate snapshot request. The loop is: type → read result → correct → read result → done.

Example AI agent interaction:
```
Agent: type_text(text: "Hello Wrold", identifier: "nameField")
Server: { success: true, value: "Hello Wrold" }

Agent: type_text(deleteCount: 4, text: "orld", identifier: "nameField")
Server: { success: true, value: "Hello World" }
```

## Current State Analysis

- **No text entry capability exists.** The system can tap, swipe, draw paths, etc. but cannot type text into text fields.
- The accessibility hierarchy already detects keyboard keys — `checkElementInteractivity()` in `InsideMan.swift:459` checks for `.keyboardKey` trait.
- `SafeCracker.tap(at:)` provides reliable single-tap injection that works on iOS 26.
- `UIElement.value` already contains text field content via `accessibilityValue` — confirmed at `InsideMan.swift:879` where `marker.value` is mapped to `UIElement.value`.
- `ActionResult` currently has `success: Bool`, `method: ActionMethod`, `message: String?` — the `message` field is used for errors, so we need a dedicated `value` field.
- The test app has text input demos: `TextInputDemo.swift` (SwiftUI TextField/SecureField/TextEditor) and `FormViewController.swift` (UIKit UITextField).

### Key Discoveries:
- Keyboard keys are accessibility elements with `UIAccessibilityTraits.keyboardKey` trait
- Each key's accessibility label matches its displayed character (e.g., "A", "space", "delete", "shift")
- Labels are case-sensitive and reflect the current keyboard state
- The keyboard mode button (e.g., "numbers" / "letters") switches between keyboard layouts
- `AccessibilitySnapshotParser` already parses keyboard keys when the keyboard is visible
- InsideMan's `cachedElements` array will contain keyboard keys after a hierarchy refresh
- `UITextField.accessibilityValue` automatically syncs with its `text` property — no special API needed to read it back
- The hierarchy refresh pattern (lines 472, 519, 543) is well-established: `parser.parseAccessibilityElements(in: rootView)`

## Desired End State

A text entry system optimized for remote AI agent control where:

1. **Type & verify**: `type_text(text: "Hello", identifier: "nameField")` → returns `{ success: true, value: "Hello" }`
2. **Delete & verify**: `type_text(deleteCount: 3, identifier: "nameField")` → returns `{ success: true, value: "He" }`
3. **Correct & verify**: `type_text(deleteCount: 2, text: "llo World", identifier: "nameField")` → returns `{ success: true, value: "Hello World" }`
4. Every response includes the **current text field value** so the agent never needs a separate snapshot to verify
5. CLI outputs the resulting value to stdout for scripted verification
6. Wire protocol: `typeText(TypeTextTarget)` with `text`, `deleteCount`, and element targeting

### Verification:
- Build all targets successfully
- Run all existing tests (no regressions)
- End-to-end test: type → verify value → delete → verify value → retype → verify value

## What We're NOT Doing

- **No hardware keyboard simulation** — we tap the software keyboard only (like KIF)
- **No predictive text / autocomplete handling** — we type exactly the characters requested
- **No emoji keyboard support** — standard character set only (letters, numbers, symbols on the default keyboards)
- **No setValue/insertText shortcut** — the whole point is key-by-key tapping for realistic simulation
- **No keyboard dismissal** — caller can tap "return" or tap elsewhere to dismiss if needed
- **No multi-language keyboard support** — English keyboard layout assumed
- **No first responder tracking** — we rely on element targeting by identifier/order, not focus detection

## Implementation Approach

All keyboard interaction logic lives **server-side in InsideMan** because:
- Direct access to the accessibility hierarchy for finding keyboard keys
- Character-by-character tapping requires rapid hierarchy refreshes — network round-trips per character would be too slow
- SafeCracker is `@MainActor` and can tap immediately
- After typing, InsideMan can immediately refresh the hierarchy and read back the text field value
- The full typing + verification is a single atomic command from the client's perspective

The **feedback loop** works as follows:
1. Client sends `typeText` with text/deleteCount and element target
2. InsideMan focuses the field, types/deletes character by character
3. InsideMan refreshes the accessibility hierarchy
4. InsideMan finds the target element and reads its `value` (the text field content)
5. InsideMan returns `ActionResult` with `value` populated
6. Client (AI agent) sees the actual field content and can decide if correction is needed

---

## Phase 1: Wire Protocol & Message Types

### Overview
Add `TypeTextTarget`, `typeText` ClientMessage case, new `ActionMethod`, and extend `ActionResult` with a `value` field for returning text field content.

### Changes Required:

#### 1. ActionResult value field
**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`

Extend `ActionResult` (line 388) to include an optional value:

```swift
public struct ActionResult: Codable, Sendable {
    public let success: Bool
    public let method: ActionMethod
    public let message: String?
    /// Current text field value after a typeText operation
    public let value: String?

    public init(success: Bool, method: ActionMethod, message: String? = nil, value: String? = nil) {
        self.success = success
        self.method = method
        self.message = message
        self.value = value
    }
}
```

This is backward-compatible: existing callers don't pass `value`, so it defaults to `nil`. Existing JSON decoding succeeds because the field is optional.

#### 2. TypeTextTarget struct
**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`

Add new target struct (after `DrawBezierTarget`, around line 357):

```swift
/// Target for typing text character-by-character via keyboard key taps
public struct TypeTextTarget: Codable, Sendable {
    /// Text to type (each character is tapped individually). Can be empty if only deleting.
    public let text: String?
    /// Number of times to tap the delete key before typing. Used for corrections.
    public let deleteCount: Int?
    /// Optional element to tap first to bring up keyboard (text field).
    /// Also used to read back the current value after typing.
    public let elementTarget: ActionTarget?

    public init(text: String? = nil, deleteCount: Int? = nil, elementTarget: ActionTarget? = nil) {
        self.text = text
        self.deleteCount = deleteCount
        self.elementTarget = elementTarget
    }
}
```

#### 3. ClientMessage case
**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`

Add after `touchDrawBezier` (line 66):

```swift
/// Type text character-by-character by tapping keyboard keys
case typeText(TypeTextTarget)
```

#### 4. ActionMethod case
**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`

Add after `syntheticDrawPath` (line 430):

```swift
case typeText
```

### Success Criteria:

#### Automated Verification:
- [x] TheGoods builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoods build`
- [x] TheGoodsTests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test`

---

## Phase 2: InsideMan Handler — Core Text Entry Logic

### Overview
Implement the server-side text entry engine that finds and taps keyboard keys character-by-character, then reads back the text field value.

### Changes Required:

#### 1. InsideMan message dispatch
**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

Add dispatch case in `handleClientMessage` switch (after `touchDrawBezier` case, line 222):

```swift
case .typeText(let target):
    handleTypeText(target, respond: respond)
```

#### 2. Text entry handler and helpers
**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

Add `handleTypeText` method and supporting helpers. The core algorithm:

```
handleTypeText(target, respond):
  1. If elementTarget provided:
     - Refresh hierarchy, resolve point from element
     - Tap it using SafeCracker to focus (bring up keyboard)
     - Wait up to 2s for keyboard to appear (poll every 100ms)
  2. Refresh hierarchy
  3. Verify keyboard is visible (at least one element with .keyboardKey trait)
     - If not visible, return error

  4. If deleteCount > 0:
     - For each delete:
       a. Refresh hierarchy
       b. Find "delete" key by label
       c. Tap it
       d. Wait 50ms

  5. If text is non-empty:
     - For each character in text:
       a. Refresh hierarchy
       b. Handle special characters:
          - " " → find and tap "space" key
          - "\n" → find and tap "Return" key
       c. Determine if shift is needed (uppercase letter):
          - Find "shift" key, tap it, wait 50ms, refresh hierarchy
       d. Find keyboard key by accessibility label matching the character
          - If not found on current keyboard, try toggling mode:
            find "more, numbers" or "letters" key, tap it, refresh, retry
       e. Tap the key at its activation point
       f. Wait 50ms between characters

  6. Read back current text field value:
     - Refresh hierarchy
     - If elementTarget was provided:
       find that element again, read its value property
     - Return ActionResult(success: true, method: .typeText, value: fieldValue)
```

Key helper methods to add:

```swift
/// Find all keyboard keys in the current hierarchy
private func findKeyboardKeys() -> [AccessibilityMarker] {
    cachedElements.filter { $0.traits.contains(.keyboardKey) }
}

/// Find a specific keyboard key by its accessibility label
private func findKeyboardKey(label: String) -> AccessibilityMarker? {
    findKeyboardKeys().first { $0.label == label }
}

/// Check if the software keyboard is currently visible
private func isKeyboardVisible() -> Bool {
    !findKeyboardKeys().isEmpty
}

/// Tap a keyboard key using SafeCracker
private func tapKey(_ key: AccessibilityMarker) -> Bool {
    safeCracker.tap(at: key.activationPoint)
}

/// Read the current value of an element by refreshing hierarchy and looking it up
private func readElementValue(for target: ActionTarget) -> String? {
    if let rootView = getRootView() {
        cachedElements = parser.parseAccessibilityElements(in: rootView)
    }
    guard let element = findElement(for: target) else { return nil }
    return element.value
}
```

**Character matching strategy:**
- Lowercase letter "a" → look for key with label "a" (keyboard in lowercase mode)
- Uppercase letter "A" → tap shift first, then look for key with label "A" (keyboard now shows uppercase)
- Space " " → look for key with label "space"
- Numbers "1" → if not found, tap "more, numbers" key to switch modes, then find "1"
- Symbols "!" → may need to switch to numbers keyboard, possibly tap shift too
- Return "\n" → look for key with label "Return" (or similar variants)

**Shift detection:**
After each letter tap, the keyboard auto-returns to lowercase. So for each uppercase character: find "shift" key, tap it, refresh hierarchy, then find the key with the uppercase label.

**Value readback:**
After all typing/deleting is complete:
1. Refresh hierarchy via `parser.parseAccessibilityElements(in: rootView)`
2. Find the target element via `findElement(for: target.elementTarget)`
3. Read `element.value` — this is the text field's `accessibilityValue`, which UITextField syncs with its `text` property
4. Include in `ActionResult(success: true, method: .typeText, value: element.value)`

If no `elementTarget` was provided, `value` will be `nil` (we don't know which field to read from).

### Success Criteria:

#### Automated Verification:
- [x] InsideMan builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideMan -destination 'generic/platform=iOS' build`
- [x] Full project builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build`

---

## Phase 3: CLI Command

### Overview
Add `buttonheist type` CLI subcommand for text entry with value feedback.

### Changes Required:

#### 1. New TypeCommand file
**File**: `ButtonHeistCLI/Sources/TypeCommand.swift`

```swift
struct TypeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text into a field by tapping keyboard keys",
        discussion: """
            Type text character-by-character and/or delete characters.
            Returns the current text field value after the operation.

            Examples:
              buttonheist type --text "Hello" --identifier "nameField"
              buttonheist type --delete 3 --identifier "nameField"
              buttonheist type --delete 4 --text "orld" --identifier "nameField"
            """
    )

    @Option(name: .long, help: "Text to type")
    var text: String?

    @Option(name: .long, help: "Number of characters to delete before typing")
    var delete: Int?

    @Option(name: .long, help: "Element identifier to target (focuses field, reads value back)")
    var identifier: String?

    @Option(name: .long, help: "Element index to target")
    var index: Int?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 30.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @MainActor
    mutating func run() async throws {
        guard text != nil || delete != nil else {
            throw ValidationError("Must specify --text, --delete, or both")
        }

        let elementTarget: ActionTarget? = (identifier != nil || index != nil)
            ? ActionTarget(identifier: identifier, order: index) : nil

        let message = ClientMessage.typeText(TypeTextTarget(
            text: text,
            deleteCount: delete,
            elementTarget: elementTarget
        ))

        // Uses shared helper, but needs special handling for value output
        try await sendTypeCommand(message: message, timeout: timeout, quiet: quiet)
    }
}
```

The `sendTypeCommand` helper is similar to `sendTouchGesture` but additionally prints `result.value` to stdout when present, so scripts and agents can capture the current field value:

```
$ buttonheist type --text "Hello" --identifier "nameField"
Hello
$ buttonheist type --delete 2
Hel
```

stdout outputs just the value (or "success" if no value returned). Status messages go to stderr.

#### 2. Register in main.swift
**File**: `ButtonHeistCLI/Sources/main.swift`

Add `TypeCommand.self` to the subcommands array.

### Success Criteria:

#### Automated Verification:
- [x] CLI builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build`

---

## Phase 4: MCP Tool

### Overview
Add `type_text` tool to the MCP server for AI agent access, surfacing the returned value.

### Changes Required:

#### 1. Tool definition
**File**: `ButtonHeistMCP/Sources/main.swift`

Add tool definition (after `customActionTool`):

```swift
let typeTextTool = Tool(
    name: "type_text",
    description: """
        Type text into a text field by tapping individual keyboard keys, and/or delete characters. \
        Returns the current text field value after the operation. \
        Use deleteCount to backspace before typing for corrections. \
        The software keyboard must be visible (disable 'Simulate Hardware Keyboard' in simulator). \
        Specify an element to target — it will be tapped to focus, and its value read back after typing.
        """,
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "text": .object(["type": .string("string"), "description": .string("Text to type character-by-character")]),
            "deleteCount": .object(["type": .string("integer"), "description": .string("Number of delete key taps before typing (for corrections)")]),
            "identifier": .object(["type": .string("string"), "description": .string("Element accessibility identifier (focuses field, reads value)")]),
            "order": .object(["type": .string("integer"), "description": .string("Element order index (focuses field, reads value)")]),
        ]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)
```

Add to `allTools` array.

#### 2. Handler implementation
In `handleToolCall` switch:

```swift
case "type_text":
    let text = stringArg(args, "text")
    let deleteCount = intArg(args, "deleteCount")
    guard text != nil || deleteCount != nil else {
        return errorResult("Must specify text, deleteCount, or both")
    }
    let target = elementTarget(args)
    let message = ClientMessage.typeText(TypeTextTarget(
        text: text,
        deleteCount: deleteCount,
        elementTarget: target
    ))
    return try await sendTypeAction(message, client: client)
```

#### 3. Response handler with value
New `sendTypeAction` helper (or update `sendAction`) that includes the returned value in the MCP response:

```swift
@MainActor
func sendTypeAction(_ message: ClientMessage, client: HeistClient) async throws -> CallTool.Result {
    client.send(message)
    let result = try await client.waitForActionResult(timeout: 30)
    if result.success {
        var content: [Tool.Content] = [
            .text("Success (method: \(result.method.rawValue))"),
        ]
        if let value = result.value {
            content.append(.text("Value: \(value)"))
        }
        return CallTool.Result(content: content)
    } else {
        let errorMsg = result.message ?? result.method.rawValue
        return CallTool.Result(content: [.text("Failed: \(errorMsg)")], isError: true)
    }
}
```

This ensures the AI agent sees the current text field value in the tool response.

### Success Criteria:

#### Automated Verification:
- [x] MCP server builds: `swift build --package-path ButtonHeistMCP`

---

## Phase 5: Protocol Tests

### Overview
Add unit tests for the new message types and ActionResult value field.

### Changes Required:

#### 1. ClientMessage encoding/decoding tests
**File**: `ButtonHeist/Tests/TheGoodsTests/ClientMessageTests.swift`

Add tests:
- `typeText` with text only encodes/decodes correctly
- `typeText` with deleteCount only encodes/decodes correctly
- `typeText` with both text and deleteCount encodes/decodes correctly
- `typeText` with elementTarget encodes/decodes correctly

#### 2. ActionResult value field tests
**File**: `ButtonHeist/Tests/TheGoodsTests/ServerMessageTests.swift`

Add tests:
- `ActionResult` with `value: nil` decodes correctly (backward compat)
- `ActionResult` with `value: "Hello"` encodes/decodes correctly
- Existing ActionResult JSON without `value` key still decodes (backward compat)

### Success Criteria:

#### Automated Verification:
- [x] TheGoodsTests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test`

---

## Phase 6: Documentation Updates

### Overview
Update wire protocol docs and API docs to cover the new `typeText` command and ActionResult value field.

### Changes Required:

#### 1. Wire Protocol
**File**: `docs/WIRE-PROTOCOL.md`

Add `typeText` message specification with JSON examples:

```json
// Type text into a field
{"typeText":{"_0":{"text":"Hello","elementTarget":{"identifier":"nameField"}}}}

// Delete 3 characters
{"typeText":{"_0":{"deleteCount":3,"elementTarget":{"identifier":"nameField"}}}}

// Delete then retype (correction)
{"typeText":{"_0":{"deleteCount":4,"text":"orld","elementTarget":{"identifier":"nameField"}}}}
```

Document the updated `ActionResult` with `value` field:

```json
// Response with text field value
{"actionResult":{"_0":{"success":true,"method":"typeText","value":"Hello World"}}}
```

#### 2. API Documentation
**File**: `docs/API.md`

Add `type_text` tool documentation with usage examples showing the feedback loop.

#### 3. README
**File**: `README.md`

Add text entry to the feature list and CLI examples.

### Success Criteria:

#### Automated Verification:
- [x] Documentation files exist and are non-empty
- [x] JSON examples are valid JSON

---

## Phase 7: Integration Testing — The Feedback Loop

### Overview
End-to-end verification of the AI agent feedback loop: type, verify, correct, verify.

### Test Scenarios:

1. **Type and verify**: Type "hello" → response value is "hello"
2. **Mixed case**: Type "Hello World" → response value is "Hello World"
3. **Delete and verify**: After typing "hello", delete 2 → response value is "hel"
4. **Correct and verify**: After "hel", type "lo World" → response value is "hello World" (oops, lowercase h)
5. **Full correction loop**: Delete all + retype correctly → response value matches
6. **Delete only**: `deleteCount: 5` with no text → response value shows remaining text
7. **Numbers and symbols**: Type "test@example.com" → response value matches
8. **Empty field**: Type into empty field → verify value from empty start

### Automated Test Flow:
```bash
# Boot simulator, install app, launch
xcrun simctl boot "iPhone 16"
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TestApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' install

# Navigate to text input demo
buttonheist touch tap --identifier "TextInput"

# Step 1: Type text, verify value
VALUE=$(buttonheist type --text "Hello Wrold" --identifier "buttonheist.text.nameField")
[ "$VALUE" = "Hello Wrold" ] && echo "PASS: type" || echo "FAIL: type (got: $VALUE)"

# Step 2: Delete and correct, verify value
VALUE=$(buttonheist type --delete 4 --text "orld" --identifier "buttonheist.text.nameField")
[ "$VALUE" = "Hello World" ] && echo "PASS: correct" || echo "FAIL: correct (got: $VALUE)"

# Step 3: Delete everything, verify empty
VALUE=$(buttonheist type --delete 11 --identifier "buttonheist.text.nameField")
[ -z "$VALUE" ] && echo "PASS: clear" || echo "FAIL: clear (got: $VALUE)"
```

### Success Criteria:

#### Automated Verification:
- [ ] All builds pass: TheGoods, Wheelman, ButtonHeist, InsideMan
- [ ] All existing tests pass: TheGoodsTests, WheelmanTests, ButtonHeistTests
- [ ] CLI `type` command returns correct value after typing
- [ ] CLI `type --delete` returns correct value after deletion
- [ ] CLI correction sequence (delete + retype) returns expected value

---

## Testing Strategy

### Unit Tests:
- `TypeTextTarget` encoding/decoding (add to `ClientMessageTests.swift`)
- `ActionResult` with/without `value` field round-trips (add to `ServerMessageTests.swift`)
- Backward compatibility: old `ActionResult` JSON (no `value` key) still decodes

### Integration Tests:
- End-to-end CLI → InsideMan → keyboard tapping → value readback
- Test with both SwiftUI TextField and UIKit UITextField
- Full correction loop: type → read value → delete → retype → read value

### Edge Cases:
- Keyboard not visible → error: "Keyboard not visible. Ensure the software keyboard is shown."
- Character not found on keyboard → error: "Key not found for character: X"
- Empty text + no deleteCount → validation error
- `elementTarget` not provided → typing works but `value` is nil in response (no field to read from)
- Text field not focusable → error propagated from tap failure
- Delete more characters than exist → delete key taps are best-effort (tapping delete on empty field is harmless)
- SecureField → value may be redacted by iOS accessibility

## Performance Considerations

- **Inter-key delay**: 50ms between taps (fast enough for automation, slow enough for keyboard to register)
- **Shift tap delay**: 50ms wait after tapping shift before tapping the character
- **Keyboard appearance wait**: Up to 2 seconds after tapping the text field, polling every 100ms
- **Hierarchy refresh**: Refresh before each character to ensure keyboard state is current
- **Value readback refresh**: One final hierarchy refresh after all typing to get the current value
- **Total timeout**: CLI defaults to 30s (longer than gestures because typing is sequential)
- **Typing speed**: ~20 characters/second at 50ms per character. A 50-char string takes ~2.5s.

## References

- KIF text entry: `KIFTypist.m` — enters characters one at a time by tapping keyboard keys found via accessibility labels
- KIF keyboard detection: Uses `UIAccessibilityTraits.keyboardKey` to identify keyboard elements
- Existing gesture pattern: `handleTouchTap` in `InsideMan.swift:567-585`
- Value readback: `UIElement.value` at `Messages.swift:529`, populated via `marker.value` at `InsideMan.swift:879`
- ActionResult: `Messages.swift:388-398`
- Hierarchy refresh pattern: `InsideMan.swift:472` (`parser.parseAccessibilityElements(in: rootView)`)
- Test app text inputs: `TestApp/Sources/TextInputDemo.swift`
- Wire protocol spec: `docs/WIRE-PROTOCOL.md`

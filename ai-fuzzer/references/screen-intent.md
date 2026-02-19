# Screen Intent Recognition

## Contents
- [How to Use This](#how-to-use-this) — intent identification workflow
- [Item List](#item-list) — task lists, feeds, collections
- [Form / Data Entry](#form--data-entry) — signup, profile edit, compose
- [Settings / Preferences](#settings--preferences) — toggles, pickers, config
- [Detail / Read View](#detail--read-view) — item detail, article, profile
- [Navigation Hub](#navigation-hub) — tab bar, sidebar, main menu
- [Picker / Selection](#picker--selection) — date picker, color picker, multi-select
- [Alert / Modal / Action Sheet](#alert--modal--action-sheet) — dialogs, confirmations
- [Canvas / Free-Form Interaction](#canvas--free-form-interaction) — drawing, maps, editors
- [Cross-Screen Relationships](#cross-screen-relationships) — multi-screen workflow testing

---

When you land on a new screen, **read the room before testing**. Look at the elements, their labels, their actions, and their spatial relationships. Ask: "What is this screen trying to let the user do?" The answer drives your test plan.

## How to Use This

1. **Observe** the screen's elements via `get_interface`
2. **Scan** for recognition signals below — most screens match 1-2 categories
3. **Record** the intent in your session notes (`## Screen Intents` table)
4. **Build a behavioral model** using the matched intent's model template as a starting point. Fill in specific element names, current values, and observed coupling. Record in session notes `## Behavioral Models`.
5. **Run workflow tests** for the matched intent — happy path first, with explicit predictions for each action
6. **Run violation tests** — out-of-order operations, skipped steps, edge states
7. **Then** do element-by-element fuzzing for anything the workflow didn't cover

If a screen doesn't match any category, fall back to element-by-element testing. Record it as "Unknown" — it may reveal a new pattern.

---

## Item List

**What it is**: A collection of similar items — tasks, messages, contacts, feed posts, search results.

**Recognition signals**:
- Multiple elements with similar structure (repeating labels, identifiers with indices)
- "Add" / "New" / "+" / "Compose" element
- Swipe actions on items (delete, archive, mark)
- Selection indicators (checkmarks, radio buttons)
- Empty state text ("No items yet", "Nothing here")
- Count labels ("3 items", "showing 1-10 of 42")
- Sort/filter controls

**Workflow tests**:
1. **Full CRUD lifecycle**: Add item → verify it appears in list → tap to view/edit → modify something → go back → verify change reflected in list → delete item → verify it's gone
2. **Empty state → populated → empty**: Start from empty state (or delete all items), add one item, add a second, delete both, verify empty state returns
3. **Ordering**: Add items A, B, C — do they appear in expected order? If sort exists, change sort and verify reorder

**Violation tests**:
- Delete when list is empty (is the button hidden? disabled? does it crash?)
- Add duplicate items with identical content
- Delete an item while another item is being edited
- Rapid add → delete → add → delete cycle
- Select an item, then add a new one — does selection state clear?
- Swipe-to-delete, then immediately tap the item (race condition)
- If list has pagination: delete items until you cross a page boundary
- Scroll to bottom, add item — does the list scroll to show it?

**Model template**:
```
State: items[]{text, completed?}, count, filter?, emptyState visible|hidden
Writes: addButton→items.append, item.activate→item.completed, item.delete→items.remove, filter→visibleSubset
Reads: countLabel←items.length, emptyLabel←(items.length==0)
Coupling: field.text↔addButton.enabled, filter→visibleItems (not backing store), showCompleted→visibility
Predict: add→count++, delete→count--, complete→activeCount changes, navigate-away-return→items persist, empty-when-0→emptyLabel appears
```

---

## Form / Data Entry

**What it is**: Structured input — signup, profile edit, checkout, compose message, create item.

**Recognition signals**:
- 2+ text fields with descriptive labels ("Name", "Email", "Phone", "Description")
- Submit/Save/Done/Send button
- Cancel/Discard button
- Validation indicators (red borders, error text, checkmarks)
- Required field markers (*, "Required")
- Keyboard type hints in identifiers (emailField, passwordField, phoneField)

**Workflow tests**:
1. **Happy path**: Fill every field with intent-appropriate values → submit → verify success (screen change, confirmation, list update)
2. **Required-only**: Fill only required fields (if identifiable) → submit → should succeed
3. **Edit and resubmit**: Fill and submit, navigate back, change one field, submit again

**Violation tests**:
- Submit completely empty form
- Submit with only one field filled (try each field solo)
- Fill form → navigate away without saving → come back (persisted or lost?)
- Fill form → submit → immediately submit again (double-submit)
- Fill field A with a value that should affect field B's validation (e.g., country changes phone format)
- Type into a field, then tap a different field — does the first field lose focus cleanly?
- Fill form → rotate device (if testable via gestures) → verify fields preserved
- Type a value → clear it → submit (is empty-after-edit different from never-filled?)

**Value generation**: Generate values based on what the field *expects*, not from a generic list:
- "Full Name" → `María José García-López`, `X Æ A-12`, `李明`, `Null`, `Test McTestface the Third Jr.`
- "Email" → `a@b.c`, `user+fuzzer@example.com`, `user@192.168.1.1`, `"quoted spaces"@example.com`
- "Phone" → `+1 (555) 000-0000`, `00000000000`, `+44 20 7946 0958`, `ext. 1234`
- "Password" → single char `x`, passphrase `correct horse battery staple`, 500 chars, matches the username/email
- "Bio" / "Description" → single word, 10 paragraphs, only emoji, only whitespace, URL-heavy text

**Model template**:
```
State: fields{name: val, ...}, submitEnabled, validationErrors[]
Writes: textField→fields[name], submitButton→validate+submit, cancelButton→discard
Reads: validationIndicators←fields (live or on-submit), submitButton.enabled←requiredFieldsFilled
Coupling: field-fill→submit-enabled, submit→screenChange|validationError, cancel→revert|navigate-back
Predict: fill-all→submit-enabled, submit-valid→success(screenChange), submit-empty→validationErrors, cancel→no-persist, navigate-away→fields lost or preserved
```

---

## Settings / Preferences

**What it is**: Configuration — app settings, notification preferences, account options, display settings.

**Recognition signals**:
- Toggle switches (accessibility value "0"/"1")
- Segmented controls ("Small"/"Medium"/"Large")
- Picker elements (date, color, value)
- Section headers/groups ("Account", "Notifications", "Display")
- Labels like "settings", "preferences", "options" in navigation
- "Reset" / "Defaults" / "Restore" buttons

**Workflow tests**:
1. **Change and persist**: Change a setting → navigate away → return → verify the setting stuck
2. **Dependency chain**: If toggle A controls visibility of settings B, C, D — toggle A off → verify B/C/D disappear → toggle A on → verify B/C/D return with their previous values
3. **All settings changed**: Change every setting from its default → navigate away → return → verify all persisted

**Violation tests**:
- Toggle a setting rapidly 20x — does the final state match the expected parity?
- Change a dependent setting to a non-default value → disable the parent toggle → re-enable parent → is the dependent setting's value preserved or reset?
- Change settings on this screen → navigate to the screen those settings affect → verify the effect is visible
- If a "Reset to defaults" exists: change everything → reset → verify all defaults restored
- Change a picker to its minimum value, then decrement again
- Change a picker to its maximum value, then increment again

**Model template**:
```
State: settings{key: val, ...}, dependencies{parent: [children]}
Writes: toggle→settings[key], picker→settings[key], resetButton→settings=defaults
Reads: dependentControls.visible←parent.value, effectScreens←settings[key]
Coupling: parent-toggle→children.visibility, setting-change→cross-screen-effect
Predict: change→persists-across-nav, parent-off→children-hidden, parent-on→children-restored-with-prior-values, cross-screen-effect-visible
```

---

## Detail / Read View

**What it is**: Detailed view of a single item — article, contact profile, item detail, message thread.

**Recognition signals**:
- Back/close navigation (came from a list or hub)
- Large text content or images
- "Edit" / "Modify" button
- Action buttons: share, favorite/like, bookmark, delete
- Few interactive elements relative to total element count
- Title matches a label from the previous (list) screen

**Workflow tests**:
1. **Read → Edit → Save → Verify**: View detail → tap Edit → change something → save → verify the change shows in detail view
2. **Read → Back → Verify list**: Check that detail info matches the list item you tapped
3. **Action round-trip**: Favorite → verify favorited → unfavorite → verify unfavorited

**Violation tests**:
- Tap Edit → make changes → tap Back without saving (unsaved changes prompt? data lost?)
- Favorite then unfavorite rapidly 10x
- Edit from two different navigation paths to the same item — same state?
- Delete from detail view — does it navigate back to the list? Is the item gone?
- Share → cancel share sheet → verify no state change on the detail screen

**Model template**:
```
State: item{fields...}, favorited?, editing?
Writes: editButton→editing=true, saveButton→item.update, favoriteButton→favorited toggle, deleteButton→item.remove+navigate-back
Reads: displayFields←item, favoriteIcon←favorited
Coupling: edit→save/cancel appear, save→detail-updates+list-updates, delete→navigate-back-to-list
Predict: edit→save-changes-to-detail-and-list, favorite→toggles-and-persists, delete→removed-from-list, back-without-save→no-changes
```

---

## Navigation Hub

**What it is**: A jumping-off point — tab bar, sidebar, home screen, main menu.

**Recognition signals**:
- Multiple elements that each lead to different screens (tab bar items, menu cells, category buttons)
- Tab bar container or section headers
- Icons paired with labels
- "More" / "..." overflow elements
- No form fields or content — primarily navigation

**Workflow tests**:
1. **Round-trip every destination**: Visit each destination → return → verify hub state unchanged
2. **State preservation across tabs**: Visit tab A → interact → switch to tab B → return to A → verify A's state preserved
3. **Deep navigation preservation**: Tab A → drill into sub-screen → switch tab → return to A → still on sub-screen? Or reset to A's root?

**Violation tests**:
- Rapid tab switching (10 switches in quick succession)
- Switch tab mid-operation (start typing in tab A, switch to B, return to A — text preserved?)
- Visit the same destination from different hub elements if multiple paths exist — consistent?
- Deep-navigate in tab A (3+ levels), switch tabs rapidly, return — navigation stack intact?

**Model template**:
```
State: destinations[], selectedTab?, perTabState{}
Writes: navElement→screenChange, tabElement→selectedTab
Reads: tabIndicator←selectedTab
Coupling: tab-switch→preserves-per-tab-state, deep-nav→tab-remembers-depth
Predict: visit-return→hub-unchanged, tab-A-interact-tab-B-return→A-state-preserved, deep-nav-tab-switch-return→stack-intact
```

---

## Picker / Selection

**What it is**: Choosing a value — date picker, color picker, item selector, multi-select list.

**Recognition signals**:
- Adjustable elements (increment/decrement actions)
- Value display that changes with interaction
- "Done" / "Cancel" / "Select" confirmation buttons
- Wheel or grid layout
- Elements with constrained value sets

**Workflow tests**:
1. **Select → Confirm**: Pick a value → tap Done → verify the value propagated to the calling screen
2. **Select → Cancel**: Pick a value → tap Cancel → verify original value unchanged
3. **Boundary values**: Select the minimum, maximum, and default values

**Violation tests**:
- Tap Done without changing anything — is the original value preserved?
- Change the value → Cancel → reopen picker → is it showing the original or the changed value?
- Select → Done → immediately reopen → select different value → Done (rapid changes)
- Increment past maximum boundary — does it wrap, cap, or crash?
- Decrement past minimum boundary
- If multi-select: select all → deselect one → confirm (does "all minus one" work?)

**Model template**:
```
State: selectedValue, originalValue(on-open), confirmed?
Writes: adjustable→selectedValue, doneButton→confirm(selectedValue), cancelButton→revert(originalValue)
Reads: valueDisplay←selectedValue
Coupling: done→propagate-to-caller, cancel→revert-to-original
Predict: select-done→caller-shows-new-value, select-cancel→caller-shows-original, done-without-change→original-preserved, boundary-increment→clamp-or-wrap
```

---

## Alert / Modal / Action Sheet

**What it is**: Overlay requiring user decision — confirmation dialog, error alert, action sheet, bottom sheet.

**Recognition signals**:
- Appeared after an action on the previous screen (elements added, not replaced)
- "OK" / "Cancel" / "Dismiss" / "Delete" / "Confirm" buttons
- Destructive action labels (often styled differently)
- Background elements still present but potentially dimmed/non-interactive
- Fewer elements than the underlying screen

**Workflow tests**:
1. **Confirm path**: Trigger → tap confirm/OK → verify the action happened (item deleted, setting changed, etc.)
2. **Cancel path**: Trigger → tap cancel → verify nothing changed
3. **Dismiss path**: If dismissable by tapping outside or swiping down, test that too

**Violation tests**:
- Try to interact with background elements while the modal is showing (should be blocked)
- Trigger the alert → confirm → immediately trigger the same alert again
- If the alert has a text field: submit empty, submit with the same value as before
- Trigger two different alerts in quick succession (does the second queue or conflict?)
- Swipe-dismiss a modal that has a destructive action — is the action taken or cancelled?
- Long-press on a modal button

**Model template**:
```
State: triggered?, parentScreenState(frozen)
Writes: confirmButton→execute-action+dismiss, cancelButton→dismiss-no-action, background-tap→dismiss(maybe)
Reads: parentScreen←frozen(non-interactive)
Coupling: confirm→parent-state-changes, cancel→parent-state-unchanged, background→blocked-or-dismiss
Predict: confirm→action-executes+modal-dismissed+parent-updated, cancel→no-change+modal-dismissed, background-tap→blocked(no-response)
```

---

## Canvas / Free-Form Interaction

**What it is**: Open-ended drawing or manipulation — drawing canvas, map view, photo editor, whiteboard.

**Recognition signals**:
- Large interactive area that responds to draw_path/drag
- Tool/mode selectors (pen, eraser, shapes)
- Zoom/pan gestures produce visible changes
- Undo/redo buttons
- Few labeled elements, large empty space

**Workflow tests**:
1. **Draw → Undo → Redo**: Create content → undo → verify removed → redo → verify restored
2. **Tool switching**: Select tool A → draw → select tool B → draw → verify both drawings coexist
3. **Zoom interaction**: Zoom in → draw → zoom out → verify the drawn content is at the expected position

**Violation tests**:
- Undo with nothing to undo
- Redo with nothing to redo
- Draw outside the canvas bounds (coordinates beyond frame)
- Pinch to scale 0 (or very close to 0)
- Draw while changing tools mid-stroke
- Rapid undo: undo 100x in quick succession
- Zoom in maximally → draw → zoom out maximally → verify

**Model template**:
```
State: content[], undoStack[], redoStack[], currentTool, zoomLevel
Writes: drawGesture→content.append, undoButton→content.pop+undoStack.push, redoButton→undoStack.pop+content.push, toolSelector→currentTool
Reads: canvas←content, undoButton.enabled←(content.length>0), redoButton.enabled←(undoStack.length>0)
Coupling: draw→clears-redoStack, undo→enables-redo, zoom→preserves-content-positions
Predict: draw-undo→content-removed, draw-undo-redo→content-restored, zoom-draw-unzoom→position-correct
```

---

## Cross-Screen Relationships

Screens don't exist in isolation. After identifying individual screen intents, look for screens that form workflows together:

**List → Detail → Edit** (CRUD across screens):
- Create item on list → verify it appears → tap into detail → tap edit → change → save → back to detail (shows change?) → back to list (shows change?)
- Delete from detail → verify list no longer contains the item

**Form → Confirmation → List** (creation flow):
- Fill form → submit → see confirmation → navigate to list → verify new item appears
- Fill form → submit → back to form → is it cleared for next entry?

**Settings → Affected Screen** (preference effects):
- Change a display setting (theme, text size, sort order) → navigate to the screen it affects → verify the effect is visible
- Change setting → verify → change it back → verify the effect reversed

**Hub → Deep Navigation → Hub** (tab state):
- Tab A → drill 3 levels deep → switch to Tab B → return to Tab A → still 3 levels deep?
- Tab A deep → Tab B deep → back and forth → both states preserved?

When you discover screen relationships, record them in session notes:
```
## Screen Relationships
- [List: Tasks] → tap item → [Detail: Task Detail] → tap Edit → [Form: Edit Task]
- [Hub: Main Menu] → "Settings" → [Settings: App Settings] → affects → [List: Tasks] sort order
- [Form: New Task] → submit → [List: Tasks] (item appears)
```

Test the full chain, not just individual screens. Bugs often hide in the transitions.

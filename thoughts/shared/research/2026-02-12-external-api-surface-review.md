---
date: 2026-02-12T19:00:00+01:00
researcher: Claude
git_commit: eb36fb015c62a07c008387dbda9466c1debd0bf4
branch: RoyalPineapple/heist-rebrand
repository: RoyalPineapple/accra
topic: "External API Surface Review — Naming, Abstraction, and Terminology Audit"
tags: [research, api, naming, abstraction, thegoods, wheelman, cli]
status: complete
last_updated: 2026-02-12
last_updated_by: Claude
---

# Research: External API Surface Review

**Date**: 2026-02-12T19:00:00+01:00
**Git Commit**: eb36fb0
**Branch**: RoyalPineapple/heist-rebrand

## Research Question
Audit the external API to ensure: (1) heist naming doesn't leak beyond what's reasonable, (2) accessibility internals are abstracted away, (3) a clean UI element abstraction is exposed for driving apps.

## Summary

The external API has **three layers of consumer exposure**: TheGoods (wire types), Wheelman (client library), and ButtonHeistCLI (CLI tool). Currently, **accessibility terminology dominates all three layers** — type names, properties, help text, and output formatting all reference accessibility concepts directly. Heist naming is mostly contained to module/package names and one constant, which is reasonable. The main gap is the lack of a UI-level abstraction: consumers work with `AccessibilityElementData` directly rather than a cleaner "UI element" concept.

## Detailed Findings

### 1. Heist Naming Leakage

Heist names visible to consumers:

| Where | What | Visibility |
|---|---|---|
| Module imports | `import Wheelman`, `import TheGoods` | **Developers see this** |
| Bonjour constant | `buttonHeistServiceType = "_buttonheist._tcp"` | **Public API** |
| CLI command | `buttonheist` | **End users see this** |
| Python module | `ButtonHeistUSBConnection`, `ButtonHeistUSBError` | **Python users** |
| Doc comments | "A discovered iOS device running InsideMan" | Wheelman.swift:8, 49 |

**Assessment**: The module names (Wheelman, TheGoods) and CLI command (buttonheist) are the public face — these are fine as branding. The doc comments mentioning "InsideMan" leak an internal name to consumers who read API docs. The Bonjour service type `_buttonheist._tcp` is reasonable.

### 2. Accessibility Terminology in Public API

This is the bigger issue. Accessibility concepts are deeply embedded:

**Type names** (TheGoods/Messages.swift):
- `AccessibilityElementData` — the primary element type (line 441)
- `AccessibilityContainerData` — container/group type (line 390)
- `AccessibilityHierarchyNode` — tree node type (line 431)
- `HierarchyPayload` containing `elements: [AccessibilityElementData]` (line 376)

**Properties on AccessibilityElementData**:
- `traversalIndex` — VoiceOver ordering concept (line 443)
- `traits: [String]` — accessibility traits like "button", "adjustable" (line 448)
- `hint` — VoiceOver hint (line 450)
- `activationPointX/Y` — accessibility activation point (lines 455-456)
- `customActions` — VoiceOver custom actions (line 457)

**Action methods** (ActionMethod enum, line 330):
- `.accessibilityActivate`
- `.accessibilityIncrement`
- `.accessibilityDecrement`

**Client messages** (ClientMessage enum):
- `.requestHierarchy` — requests "accessibility hierarchy"
- `.activate(ActionTarget)` — comment says "VoiceOver double-tap equivalent"

**CLI output**:
- Header: `"Accessibility Hierarchy (timestamp)"`
- Help text: "Inspect and interact with iOS app accessibility hierarchy"
- "accessibility element", "accessibilityIdentifier" throughout

### 3. What a Clean UI Abstraction Would Look Like

Currently consumers see:
```swift
let element: AccessibilityElementData
element.traversalIndex  // VoiceOver concept
element.traits          // accessibility concept
element.hint            // VoiceOver concept
element.activationPoint // accessibility concept
```

A UI-focused abstraction would present:
```
Element (or UIElement, ViewElement, etc.)
├── label: String?        — display text
├── value: String?        — current value
├── identifier: String?   — stable ID for targeting
├── role: String          — "button", "slider", "text", etc.
├── frame: CGRect         — screen position
├── interactionPoint: CGPoint — where to tap
├── actions: [String]     — available actions
└── index: Int            — ordering index
```

Key renames that would abstract away accessibility:
- `AccessibilityElementData` → `Element` or `UIElement`
- `traits` → `role` or `type` (these are already human-readable strings like "button")
- `traversalIndex` → `index`
- `hint` → `tooltip` or `description`
- `activationPoint` → `interactionPoint` or `tapPoint`
- `customActions` → `actions`
- `AccessibilityHierarchyNode` → `ElementNode` or `ViewNode`
- `AccessibilityContainerData` → `Container` or `Group`
- `HierarchyPayload` → `Snapshot` or `ViewTree`
- `.requestHierarchy` → `.requestSnapshot` or `.requestElements`
- `ActionMethod.accessibilityActivate` → `ActionMethod.activate`

### 4. Wire Protocol Implications

The wire protocol (JSON over TCP) uses the type names from TheGoods directly. Renaming types would be a **wire protocol breaking change** unless:
- The `CodingKeys` are set explicitly to preserve wire format
- Or the protocol version is bumped

Currently types use default Codable synthesis, so JSON keys match property names exactly. A rename of `traversalIndex` → `index` would change the JSON wire format.

## Code References

- `ButtonHeist/Sources/TheGoods/Messages.swift` — all wire types and public constants
- `ButtonHeist/Sources/Wheelman/Wheelman.swift:51-280` — client class public API
- `ButtonHeistCLI/Sources/main.swift:5-28` — CLI help text and command structure
- `ButtonHeistCLI/Sources/CLIRunner.swift:166-228` — human output format
- `ButtonHeistCLI/Sources/ActionCommand.swift` — action command help text
- `ButtonHeistCLI/Sources/TouchCommand.swift` — touch command help text

## Architecture Documentation

The public API spans three layers:

```
End Users (CLI)          Developers (Library)        Wire Protocol
──────────────          ────────────────────        ─────────────
buttonheist CLI    →    Wheelman (client class)  →  TheGoods (types)
                        DiscoveredDevice                ↕
                        ConnectionState             JSON over TCP
                                                        ↕
                                                    InsideMan (server)
```

- **TheGoods** defines the shared vocabulary (types/enums)
- **Wheelman** wraps connection management around those types
- **CLI** formats those types for human/JSON output

Any rename at the TheGoods layer cascades to all three.

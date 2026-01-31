# Accessibility Tree Visualization - Design Implementation Plan

## Overview

Refactor the existing `HierarchyListView` to achieve a clean, professional aesthetic. The current implementation has icons, colored badges, and traversal indices. We want understated, typography-driven design inspired by Linear and native Apple developer tools.

## Current State Analysis

### Existing Codebase Structure
```
AccessibilityInspector/
├── AccessibilityInspector/
│   ├── Views/
│   │   ├── ContentView.swift          # Main app with device list
│   │   └── HierarchyListView.swift    # Current tree view (TO REFACTOR)
│   ├── Services/
│   │   ├── BonjourBrowser.swift
│   │   └── WebSocketClient.swift
│   └── CLI/
│       ├── CLIRunner.swift
│       └── main.swift
└── Package.swift

AccessibilityBridgeProtocol/
└── Sources/
    └── AccessibilityBridgeProtocol/
        └── Messages.swift             # AccessibilityElementData model
```

### Existing Model: `AccessibilityElementData`
Located in `AccessibilityBridgeProtocol/Sources/AccessibilityBridgeProtocol/Messages.swift`

```swift
public struct AccessibilityElementData: Codable, Equatable, Hashable, Sendable {
    public var traversalIndex: Int      // VoiceOver traversal order (FLAT, not hierarchical)
    public var description: String
    public var label: String?
    public var value: String?
    public var traits: [String]         // e.g., ["button", "staticText"]
    public var identifier: String?
    public var hint: String?
    public var frameX, frameY, frameWidth, frameHeight: Double
    public var activationPointX, activationPointY: Double
    public var customActions: [String]
}
```

**Important**: Data is currently a **flat list** in VoiceOver traversal order, not a tree structure.

### Existing Views to Refactor

**`ElementRowView`** (current):
- Shows `[traversalIndex]` in monospace
- Bold label text
- Traits listed below in caption
- Blue icons for primary trait type

**`ElementDetailView`** (current):
- Already well-structured with sections
- Uses blue capsule badges for traits
- Keep structure, simplify styling

---

## Desired End State

A list visualization that:
- Feels native to macOS
- Uses monochromatic palette with system accent for selection only
- Distinguishes elements through typography, not color or icons
- Has always-visible search
- Shows element details in existing detail panel on selection

### Display Format
```
button "Submit Form"
staticText "Welcome to our app"
link "Learn more"
```
- First word: trait/role in monospace, secondary color
- Quoted text: label in system font, primary color
- No traversal index, no icons

### Verification
- List renders with correct visual styling
- Selection highlights with system accent
- Search filters list correctly
- Detail panel updates on selection
- Light/dark mode both look correct

---

## What We're NOT Doing

- No hierarchical tree (data is flat) - future enhancement
- No color-coded trait badges
- No icons
- No traversal index display
- No hover-reveal actions
- No inline metadata clutter

---

## Design Specification

### Color Tokens

```swift
// Design/Colors.swift
import SwiftUI

extension Color {
    struct Tree {
        // Backgrounds
        static let background = Color(nsColor: .windowBackgroundColor)
        static let rowHover = Color.primary.opacity(0.04)
        static let rowSelected = Color.accentColor.opacity(0.15)

        // Text
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.primary.opacity(0.3)

        // Structure
        static let divider = Color.primary.opacity(0.1)
    }
}
```

---

### Typography Tokens

```swift
// Design/Typography.swift
import SwiftUI

extension Font {
    struct Tree {
        // Element display
        static let elementLabel = Font.system(size: 13, weight: .regular)
        static let elementTrait = Font.system(size: 11, weight: .regular, design: .monospaced)

        // Search
        static let searchInput = Font.system(size: 14, weight: .regular)

        // Detail panel
        static let detailSectionTitle = Font.caption
        static let detailValue = Font.system(.body, design: .monospaced)
    }
}
```

---

### Spacing Tokens

```swift
// Design/Spacing.swift
import Foundation

enum TreeSpacing {
    static let rowHeight: CGFloat = 28
    static let rowHorizontalPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 4
    static let searchHeight: CGFloat = 32
    static let searchHorizontalPadding: CGFloat = 12
    static let unit: CGFloat = 8
}
```

---

### Element Row Layout

```
┌─────────────────────────────────────────────────────────────┐
│  button "Submit Form"                                       │
│  ↑       ↑                                                  │
│  trait   label (quoted)                                     │
│                                                             │
│  Row height: 28px                                           │
│  Horizontal padding: 12px                                   │
└─────────────────────────────────────────────────────────────┘
```

**Text format**: `trait "label"`
- Trait: lowercase, monospace, secondary color (from first trait in array)
- Label: quoted, system font, primary color
- If no label: show description instead

---

### Search Bar

```
┌─────────────────────────────────────────────────────────────┐
│  🔍  Filter elements...                          ⌘F        │
└─────────────────────────────────────────────────────────────┘
```
- Position: Fixed at top of list panel
- Height: 32px
- Background: `controlBackgroundColor`
- Corner radius: 6px

---

### Interaction States

| State | Background | Text |
|-------|------------|------|
| Default | transparent | primary/secondary |
| Hover | `primary.opacity(0.04)` | unchanged |
| Selected | `accentColor.opacity(0.15)` | primary |

---

### Detail Panel Simplification

Current badges like:
```swift
Text(trait)
    .padding(.horizontal, 8)
    .background(.blue.opacity(0.1))
    .foregroundStyle(.blue)
    .clipShape(Capsule())
```

Change to:
```swift
Text(trait)
    .font(.Tree.elementTrait)
    .foregroundColor(.Tree.textSecondary)
```

Simple comma-separated list, no colored capsules.

---

## Implementation Phases

### Phase 1: Add Design Tokens

**Create files**:

#### `AccessibilityInspector/AccessibilityInspector/Design/Colors.swift`
```swift
import SwiftUI

extension Color {
    struct Tree {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let rowHover = Color.primary.opacity(0.04)
        static let rowSelected = Color.accentColor.opacity(0.15)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.primary.opacity(0.3)
        static let divider = Color.primary.opacity(0.1)
    }
}
```

#### `AccessibilityInspector/AccessibilityInspector/Design/Typography.swift`
```swift
import SwiftUI

extension Font {
    struct Tree {
        static let elementLabel = Font.system(size: 13, weight: .regular)
        static let elementTrait = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let searchInput = Font.system(size: 14, weight: .regular)
        static let detailSectionTitle = Font.caption
        static let detailValue = Font.system(.body, design: .monospaced)
    }
}
```

#### `AccessibilityInspector/AccessibilityInspector/Design/Spacing.swift`
```swift
import Foundation

enum TreeSpacing {
    static let rowHeight: CGFloat = 28
    static let rowHorizontalPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 4
    static let searchHeight: CGFloat = 32
    static let searchHorizontalPadding: CGFloat = 12
    static let unit: CGFloat = 8
}
```

### Success Criteria - Phase 1

#### Automated Verification:
- [x] Project compiles: `swift build` in AccessibilityInspector directory

#### Manual Verification:
- [ ] Files created in correct location

---

### Phase 2: Refactor ElementRowView

**File**: `AccessibilityInspector/AccessibilityInspector/Views/HierarchyListView.swift`

**Replace `ElementRowView`** with:

```swift
struct ElementRowView: View {
    let element: AccessibilityElementData

    var body: some View {
        HStack(spacing: 4) {
            // Primary trait (monospace, secondary)
            Text(primaryTrait)
                .font(.Tree.elementTrait)
                .foregroundColor(Color.Tree.textSecondary)

            // Label or description (quoted, primary)
            Text("\"\(displayLabel)\"")
                .font(.Tree.elementLabel)
                .foregroundColor(Color.Tree.textPrimary)
                .lineLimit(1)

            Spacer()
        }
        .frame(height: TreeSpacing.rowHeight)
        .padding(.horizontal, TreeSpacing.rowHorizontalPadding)
    }

    private var primaryTrait: String {
        element.traits.first ?? "element"
    }

    private var displayLabel: String {
        element.label ?? element.description
    }
}
```

**Changes from current**:
- Remove `[traversalIndex]` display
- Remove trait icon (`primaryTraitIcon`)
- Remove VStack with label + traits underneath
- Single line: `trait "label"`

### Success Criteria - Phase 2

#### Automated Verification:
- [x] Project compiles

#### Manual Verification:
- [ ] Rows display as `trait "label"` format
- [ ] No icons visible
- [ ] No traversal index visible
- [ ] Monospace trait, quoted label

---

### Phase 3: Add Search Bar

**File**: `AccessibilityInspector/AccessibilityInspector/Views/HierarchyListView.swift`

Add `SearchBar` view and integrate into `HierarchyListView`:

```swift
struct SearchBar: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.Tree.textSecondary)

            TextField("Filter elements...", text: $query)
                .font(.Tree.searchInput)
                .textFieldStyle(.plain)

            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color.Tree.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text("⌘F")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(Color.Tree.textTertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.Tree.textTertiary.opacity(0.2))
                .cornerRadius(3)
        }
        .padding(.horizontal, TreeSpacing.searchHorizontalPadding)
        .frame(height: TreeSpacing.searchHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
}
```

**Update `HierarchyListView`**:

```swift
struct HierarchyListView: View {
    let elements: [AccessibilityElementData]
    @State private var selectedElement: AccessibilityElementData?
    @State private var searchQuery = ""

    private var filteredElements: [AccessibilityElementData] {
        guard !searchQuery.isEmpty else { return elements }
        let query = searchQuery.lowercased()
        return elements.filter { element in
            element.label?.lowercased().contains(query) == true ||
            element.description.lowercased().contains(query) ||
            element.traits.contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        HSplitView {
            // Element list with search
            VStack(spacing: 0) {
                SearchBar(query: $searchQuery)
                    .padding(TreeSpacing.unit)

                Divider()

                if filteredElements.isEmpty && !searchQuery.isEmpty {
                    emptySearchView
                } else {
                    List(filteredElements, id: \.traversalIndex, selection: $selectedElement) { element in
                        ElementRowView(element: element)
                    }
                }
            }
            .frame(minWidth: 300)

            // Detail pane (unchanged)
            if let element = selectedElement {
                ElementDetailView(element: element)
                    .frame(minWidth: 250)
            } else {
                Text("Select an element")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var emptySearchView: some View {
        VStack(spacing: 8) {
            Text("No matches for \"\(searchQuery)\"")
                .font(.Tree.elementLabel)
                .foregroundColor(Color.Tree.textPrimary)
            Text("Try a different search term")
                .font(.Tree.elementTrait)
                .foregroundColor(Color.Tree.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

### Success Criteria - Phase 3

#### Automated Verification:
- [x] Project compiles

#### Manual Verification:
- [ ] Search bar visible at top of list
- [ ] Typing filters the list
- [ ] Clear button works
- [ ] Empty state shows when no matches
- [ ] ⌘F hint visible

---

### Phase 4: Simplify Detail Panel

**File**: `AccessibilityInspector/AccessibilityInspector/Views/HierarchyListView.swift`

**Update traits section in `ElementDetailView`**:

Replace:
```swift
if !element.traits.isEmpty {
    DetailSection(title: "Traits") {
        FlowLayout(spacing: 4) {
            ForEach(element.traits, id: \.self) { trait in
                Text(trait)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
    }
}
```

With:
```swift
if !element.traits.isEmpty {
    DetailSection(title: "Traits") {
        Text(element.traits.joined(separator: ", "))
            .font(.Tree.elementTrait)
            .foregroundColor(Color.Tree.textSecondary)
    }
}
```

**Update `DetailSection` title styling**:
```swift
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.Tree.detailSectionTitle)
                .foregroundStyle(Color.Tree.textTertiary)
                .textCase(.uppercase)
            content()
        }
    }
}
```

### Success Criteria - Phase 4

#### Automated Verification:
- [x] Project compiles

#### Manual Verification:
- [ ] Traits show as comma-separated text, not blue badges
- [ ] Section titles use tertiary color
- [ ] Overall detail panel feels calmer, less colorful

---

### Phase 5: Final Polish

1. **Remove `FlowLayout`** - No longer needed after Phase 4

2. **Update custom actions display** (if present):
```swift
if !element.customActions.isEmpty {
    DetailSection(title: "Custom Actions") {
        Text(element.customActions.joined(separator: ", "))
            .font(.Tree.elementTrait)
            .foregroundColor(Color.Tree.textSecondary)
    }
}
```

3. **Ensure consistent spacing** throughout detail panel

### Success Criteria - Phase 5

#### Automated Verification:
- [x] Project compiles
- [x] No unused code warnings

#### Manual Verification:
- [ ] Full app matches design spec
- [ ] Light mode looks correct
- [ ] Dark mode looks correct
- [ ] Selection highlight uses system accent
- [ ] Typography hierarchy is clear without color

---

## Testing Strategy

### Manual Testing Steps
1. Connect to a device with accessibility elements
2. Verify list displays in `trait "label"` format
3. Test search with various queries
4. Select elements, verify detail panel updates
5. Check light mode appearance
6. Check dark mode appearance
7. Verify no blue/colored elements remain (except system selection)

---

## Future Enhancements (Out of Scope)

1. **Hierarchical tree** - Would require protocol changes to include parent/child relationships
2. **Keyboard navigation** - Arrow keys to navigate list
3. **Minimap** - For very large element lists
4. **Icons** - Could add back subtle role icons later if needed

---

## References

- Research: `thoughts/shared/research/2026-01-31-accessibility-tree-visualization.md`
- Existing code: `AccessibilityInspector/AccessibilityInspector/Views/HierarchyListView.swift`
- Model: `AccessibilityBridgeProtocol/Sources/AccessibilityBridgeProtocol/Messages.swift`
- [Linear UI Redesign](https://linear.app/now/how-we-redesigned-the-linear-ui)

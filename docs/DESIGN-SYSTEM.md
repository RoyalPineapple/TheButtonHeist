# Accra Inspector Design System

Design tokens and guidelines for the AccraInspector macOS application.

## Overview

AccraInspector uses a typography-driven design system with semantic tokens for colors, fonts, and spacing. All design values are defined in the `Design/` directory.

## File Structure

```
AccraInspector/Sources/Design/
├── Colors.swift      # Semantic color definitions
├── Typography.swift  # Font definitions
└── Spacing.swift     # Layout constants
```

## Colors

**Location**: `AccraInspector/Sources/Design/Colors.swift`

Colors are accessed via the `Color.Tree` namespace extension.

### Semantic Colors

| Token | Usage |
|-------|-------|
| `Color.Tree.textPrimary` | Primary text, element labels |
| `Color.Tree.textSecondary` | Secondary text, metadata |
| `Color.Tree.textTertiary` | Tertiary text, hints |
| `Color.Tree.background` | View backgrounds |
| `Color.Tree.rowHover` | Row hover state |
| `Color.Tree.rowSelected` | Row selection state |

### Usage

```swift
Text(element.description)
    .foregroundStyle(Color.Tree.textPrimary)

Text(element.traits.joined(separator: ", "))
    .foregroundStyle(Color.Tree.textSecondary)
```

### Color Values

Colors adapt to light/dark mode using semantic system colors or custom asset catalog colors.

## Typography

**Location**: `AccraInspector/Sources/Design/Typography.swift`

Fonts are accessed via the `Font.Tree` namespace extension.

### Font Tokens

| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| `Font.Tree.elementLabel` | 13pt | Regular | Element descriptions |
| `Font.Tree.elementTrait` | 11pt | Regular, Monospaced | Trait badges |
| `Font.Tree.searchInput` | 14pt | Regular | Search field |
| `Font.Tree.detailSectionTitle` | Caption | Regular | Detail panel headers |

### Usage

```swift
Text(element.description)
    .font(.Tree.elementLabel)

Text(trait)
    .font(.Tree.elementTrait)
```

## Spacing

**Location**: `AccraInspector/Sources/Design/Spacing.swift`

Spacing constants are defined in the `TreeSpacing` enum.

### Spacing Tokens

| Token | Value | Usage |
|-------|-------|-------|
| `TreeSpacing.unit` | 8pt | Base unit for calculations |
| `TreeSpacing.rowHeight` | 28pt | List row height |
| `TreeSpacing.searchHeight` | 32pt | Search bar height |

### Usage

```swift
List {
    ForEach(elements) { element in
        ElementRow(element: element)
    }
}
.listRowInsets(EdgeInsets(
    top: TreeSpacing.unit / 2,
    leading: TreeSpacing.unit,
    bottom: TreeSpacing.unit / 2,
    trailing: TreeSpacing.unit
))
```

## Component Patterns

### Element Row

Standard row for displaying accessibility elements:

```swift
struct ElementRow: View {
    let element: AccessibilityElementData

    var body: some View {
        HStack(spacing: TreeSpacing.unit) {
            // Index badge
            Text(String(format: "%02d", element.traversalIndex))
                .font(.Tree.elementTrait)
                .foregroundStyle(Color.Tree.textTertiary)

            // Traits
            HStack(spacing: 4) {
                ForEach(element.traits, id: \.self) { trait in
                    Text(trait)
                        .font(.Tree.elementTrait)
                        .foregroundStyle(Color.Tree.textSecondary)
                }
            }

            // Label
            Text(element.description)
                .font(.Tree.elementLabel)
                .foregroundStyle(Color.Tree.textPrimary)
        }
        .frame(height: TreeSpacing.rowHeight)
    }
}
```

### Search Bar

Consistent search bar styling:

```swift
struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.Tree.textTertiary)

            TextField("Search", text: $text)
                .font(.Tree.searchInput)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, TreeSpacing.unit)
        .frame(height: TreeSpacing.searchHeight)
        .background(Color.Tree.background)
    }
}
```

### Detail Panel

Section styling for detail views:

```swift
struct DetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TreeSpacing.unit / 2) {
            Text(title)
                .font(.Tree.detailSectionTitle)
                .foregroundStyle(Color.Tree.textTertiary)

            content
        }
    }
}
```

## Guidelines

### Consistency

- Always use design tokens instead of hardcoded values
- Use semantic color names that describe purpose, not appearance
- Maintain consistent spacing using `TreeSpacing.unit` multiples

### Accessibility

- Ensure sufficient color contrast in both light and dark modes
- Use Dynamic Type-compatible font sizes
- Provide proper accessibility labels for all interactive elements

### Adding New Tokens

When adding new design tokens:

1. Add to the appropriate file (`Colors.swift`, `Typography.swift`, or `Spacing.swift`)
2. Use the existing namespace extension pattern
3. Document the token's intended usage
4. Update this documentation

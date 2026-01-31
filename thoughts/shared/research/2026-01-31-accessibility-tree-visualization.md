---
date: 2026-01-31T16:32:51Z
researcher: Claude
git_commit: 8dccc3c2a21cb3fcb089428124a73dba6bd1c9ae
branch: RoyalPineapple/a11y-tree-viz
repository: accra
topic: "Accessibility Tree Visualization Techniques for macOS App"
tags: [research, accessibility, tree-visualization, swiftui, macos, ux-design]
status: complete
last_updated: 2026-01-31
last_updated_by: Claude
---

# Research: Accessibility Tree Visualization Techniques for macOS App

**Date**: 2026-01-31T16:32:51Z
**Researcher**: Claude
**Git Commit**: 8dccc3c2a21cb3fcb089428124a73dba6bd1c9ae
**Branch**: RoyalPineapple/a11y-tree-viz
**Repository**: accra

## Research Question

How can we visualize an accessibility hierarchy in a Mac app using interesting visualization tricks and techniques that make the tree look beautiful while remaining clear to understand and navigate?

## Summary

This research compiles comprehensive findings on tree visualization techniques spanning multiple domains: standard tree views, alternative layouts (radial, treemaps, icicle charts), focus+context techniques (hyperbolic trees), animation patterns, and accessibility-specific tooling patterns from Chrome/Firefox DevTools. The research reveals numerous approaches that balance visual appeal with clarity and usability.

**Key Findings:**
- **SwiftUI native support**: `List` with `children:` parameter and `OutlineGroup` provide native hierarchical display
- **Animation sweet spot**: 200-500ms with spring physics creates premium feel
- **Indentation standards**: 13-24px per level depending on density needs
- **Innovative layouts**: Hyperbolic trees can display 10x more nodes in the same space
- **DevTools patterns**: Chrome's lazy loading, live updates, and intelligent filtering provide UX inspiration

---

## Detailed Findings

### 1. SwiftUI Native Tree Visualization

#### List with Children Parameter (Simplest)

```swift
struct FileItem: Identifiable {
    let name: String
    var children: [FileItem]?
    var id: String { name }
}

List(data, children: \.children, rowContent: { Text($0.name) })
```

**Requirements:**
- Elements must conform to `Identifiable`
- Children property must be optional (signals tree end)

#### OutlineGroup for More Control

```swift
OutlineGroup(categories, id: \.value, children: \.children) { tree in
    Text(tree.value).font(.subheadline)
}
```

**Best Practice - With Sidebar Style:**
```swift
List(categories, id: \.value, children: \.children) { tree in
    Text(tree.value)
}.listStyle(SidebarListStyle())
```

This provides native macOS sidebar appearance with automatic translucency.

#### DisclosureGroup for Custom Behavior

```swift
@State private var showContent = false

DisclosureGroup("Message", isExpanded: $showContent) {
    Text("Hello World!")
}
```

**Customization (macOS 13+):**
Custom `DisclosureGroupStyle` allows full appearance customization.

**Sources:**
- [SwiftUI Hierarchy Lists](https://www.fivestars.blog/articles/swiftui-hierarchy-list/)
- [Displaying recursive data using OutlineGroup](https://swiftwithmajid.com/2020/09/02/displaying-recursive-data-using-outlinegroup-in-swiftui/)
- [OutlineGroup Documentation](https://developer.apple.com/documentation/swiftui/outlinegroup)

---

### 2. Visual Design Patterns

#### Indentation Standards

| Design System | Indentation per Level |
|--------------|----------------------|
| Unity | 15px |
| Windows Forms | 19px |
| Microsoft Web | 20px |
| GitHub Primer | 8px minimum |
| Carbon | 24px (medium), 12px (small) |
| NSOutlineView | 13 points |

#### Color Coding Strategies

- **Node types**: Different icons/colors for different accessibility roles
- **D3 convention**: Dark (#555) for parents, lighter (#999) for leaves
- **State indicators**: Green (valid), Yellow (warnings), Red (errors)

#### Information Display per Node

Chrome DevTools shows for each accessibility node:
- **Role**: button, tree, treeitem, etc.
- **Name**: Accessible label
- **State**: focusable, editable, expanded, ignored
- **Value**: Current value for inputs

**Sources:**
- [Primer Tree View](https://primer.style/components/tree-view/)
- [Carbon Design System Tree View](https://carbondesignsystem.com/components/tree-view/usage/)
- [PatternFly Tree View](https://www.patternfly.org/components/tree-view/design-guidelines/)

---

### 3. Animation & Micro-Interactions

#### Recommended Timing

| Interaction | Duration | Easing |
|------------|----------|--------|
| Tap feedback | 180ms | `.snappy()` |
| Hover lift | 220ms | `.smooth()` |
| Expand/collapse | 250ms | Spring physics |
| Slide-in | 400ms | `.spring(response: 0.4, dampingFraction: 0.75)` |

#### Spring Physics for Premium Feel

```swift
.animation(.spring(response: 0.4, dampingFraction: 0.75), value: isExpanded)
```

**Key Principles:**
- 200-500ms range feels responsive
- Scale effects: 0.92 pressed, 1.03 hover
- Shadow manipulation for depth
- Spring physics over linear easing

**Sources:**
- [Micro-Interactions in SwiftUI](https://dev.to/sebastienlato/micro-interactions-in-swiftui-subtle-animations-that-make-apps-feel-premium-2ldn)
- [NN/G Animation Duration](https://www.nngroup.com/articles/animation-duration/)

---

### 4. Keyboard Navigation (W3C Standards)

#### Arrow Key Behavior

| Key | Action |
|-----|--------|
| Right | Open closed node or move to first child |
| Left | Close open node or move to parent |
| Up/Down | Navigate between visible nodes |
| Home/End | Jump to first/last node |
| Enter | Toggle expansion or perform action |
| * | Expand all siblings |

#### Required ARIA Attributes

```html
<div role="tree" aria-label="Accessibility Tree">
  <div role="treeitem" aria-expanded="true" aria-selected="false">
    <div role="group">
      <div role="treeitem" aria-expanded="false">...</div>
    </div>
  </div>
</div>
```

**Sources:**
- [W3C Tree View Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/treeview/)
- [ARIA tree role MDN](https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Roles/tree_role)

---

### 5. Search & Filter UX

#### Best Practices

- Start filtering as user types (instant feedback)
- Display only matching nodes AND their parents
- Highlight matches distinctively
- Provide "no results" with recovery options
- **Preserve tree state** - don't reset expanded nodes after search

#### Filter Display Modes

1. **Highlighting only**: Mark matches within visible tree
2. **Filtering**: Show only matches and their ancestors
3. **Hybrid**: Filter with option to show surrounding context

**Sources:**
- [Interaction Design for Trees](https://medium.com/@hagan.rivers/interaction-design-for-trees-5e915b408ed2)
- [Algolia Search Filter Best Practices](https://www.algolia.com/blog/ux/search-filter-ux-best-practices/)

---

### 6. Alternative Tree Layouts

#### Hyperbolic Tree (Focus+Context)

**Technique**: Lays out hierarchy on hyperbolic plane with fisheye distortion. Center has full detail, edges compressed.

**Advantages:**
- Displays **1,000 nodes** where standard tree shows 100
- Smooth blending between focus and context
- Any node can become center of focus

**Implementation**: Click any node to bring to center, or drag to reposition.

**Sources:**
- [ACM Focus+Context Based on Hyperbolic Geometry](https://dl.acm.org/doi/fullHtml/10.1145/223904.223956)
- [Wikipedia Hyperbolic Tree](https://en.wikipedia.org/wiki/Hyperbolic_tree)

#### Zoomable Icicle Chart

**Features:**
- Adjacent rectangles by depth
- Interactive zoom via click or mouse-wheel
- Shows only 3 layers at a time
- Better for size comparison than sunburst

**Sources:**
- [Observable Zoomable Icicle](https://observablehq.com/@d3/zoomable-icicle)
- [Plotly Icicle Charts](https://plotly.com/python/icicle-charts/)

#### Sunburst Diagram

**Best for:**
- Deep hierarchies with many levels
- Single-screen snapshot of entire structure
- Space-efficient display

**Limitations:**
- Deeper slices appear visually larger
- Harder for exact comparisons than rectangles

**Sources:**
- [Oracle Treemap vs Sunburst](https://docs.oracle.com/en/cloud/saas/enterprise-performance-management-common/dmepr/about_treemap_sunburst_charts.html)

#### Circle Packing

**Best for:**
- Illustrating 2-3 level hierarchies
- Showing group organization clearly
- Quick size comparison via area

**Sources:**
- [Data-to-Viz Circular Packing](https://www.data-to-viz.com/graph/circularpacking.html)

---

### 7. DevTools Pattern Inspiration

#### Chrome Accessibility Tree Features

- **Full-page tree view** in Elements panel
- **Lazy loading**: Children fetched only when expanded
- **Live updates**: Synchronized with DOM changes
- **Intelligent filtering**: Hides ignored/generic nodes by default
- **Toggle**: Switch between DOM tree and accessibility tree

**How to access:**
1. Enable in Settings > Experiments > "Enable full accessibility tree view"
2. Toggle button appears in Elements panel upper right

#### Firefox Accessibility Inspector

- Hover nodes highlights DOM elements
- Accessibility issues shown next to nodes
- Role and name in information bar
- Color contrast information

**Sources:**
- [Chrome Full Accessibility Tree](https://developer.chrome.com/blog/full-accessibility-tree)
- [Firefox Accessibility Inspector](https://firefox-source-docs.mozilla.org/devtools-user/accessibility_inspector/)
- [Apple Accessibility Inspector](https://developer.apple.com/documentation/accessibility/accessibility-inspector)

---

### 8. Advanced Relationship Visualization

#### Hierarchical Edge Bundling

Shows dependencies between nodes by curving edges along tree paths. Reduces visual clutter for complex relationships.

**Sources:**
- [Hierarchical Edge Bundling D3](https://gist.github.com/mbostock/1044242)
- [React Graph Gallery](https://www.react-graph-gallery.com/hierarchical-edge-bundling)

#### Tangled Tree Visualization

For trees with multiple inheritance (DAGs). Uses metro-style bundling when nodes have multiple parents.

**Applications**: Accessibility trees with ARIA relationships beyond parent-child.

**Sources:**
- [Observable Tangled Tree](https://observablehq.com/@nitaku/tangled-tree-visualization-ii)

#### Minimap Overview

Shows full tree with highlighted viewport rectangle. Prevents disorientation in large trees.

**Sources:**
- [GitHub Gist Collapsible Tree with Minimap](https://gist.github.com/bwswedberg/464a7dbc471ee2a94dd6278bc7d94710)

---

### 9. When NOT to Use Tree Views

**Avoid trees when:**
- 10,000+ items (excessive scrolling)
- Very deep nesting (context loss)
- Items fit multiple categories (use tagging)
- Serving navigation (menubars better)

**Alternatives:**
- **Tree Tables**: Hierarchies + tabular data
- **Miller Columns**: Deep hierarchies (Finder-style)
- **Tagging Systems**: Multi-category organization

**Sources:**
- [Interaction Design for Trees](https://medium.com/@hagan.rivers/interaction-design-for-trees-5e915b408ed2)
- [NN/G Treemaps](https://www.nngroup.com/articles/treemaps/)

---

## Design Recommendations for Accessibility Tree

### Primary Layout Approach

**Recommended**: Collapsible tree with `SidebarListStyle` for native macOS feel, with these enhancements:

1. **Node display**: Show role, name, and key states inline
2. **Indentation**: 16-20px per level
3. **Icons**: Unique icons per accessibility role
4. **Animation**: 250ms spring animations for expand/collapse

### Innovative Features to Consider

| Feature | Benefit | Implementation |
|---------|---------|----------------|
| Hyperbolic focus | 10x density | Custom view with gesture handling |
| Minimap | Orientation in large trees | Overlay view synced with main tree |
| Live sync | Real-time updates | Accessibility notifications |
| Search with highlight | Quick navigation | Filter + ancestor preservation |
| Breadcrumb | Context awareness | Path from root to selection |
| Lazy loading | Performance | Load children on expand |

### Color Scheme Suggestion

| Role Category | Color |
|--------------|-------|
| Interactive (buttons, links) | Blue |
| Text content | Gray |
| Images | Purple |
| Structural (groups, lists) | Green |
| Landmarks | Orange |
| Warnings/Issues | Red |

### Animation Details

```swift
// Expand/collapse
.animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)

// Selection
.animation(.easeOut(duration: 0.15), value: isSelected)

// Hover
.scaleEffect(isHovered ? 1.02 : 1.0)
.animation(.smooth(duration: 0.2), value: isHovered)
```

---

## Code References

- SwiftUI List with children: [Apple Documentation](https://developer.apple.com/documentation/swiftui/list)
- OutlineGroup: [Apple Documentation](https://developer.apple.com/documentation/swiftui/outlinegroup)
- NSOutlineView (AppKit): [Apple Documentation](https://developer.apple.com/documentation/appkit/nsoutlineview)
- D3 Collapsible Tree: [Observable](https://observablehq.com/@d3/collapsible-tree)

---

## Architecture Documentation

### Current Codebase State

This is a new, empty repository. No existing implementation to document.

### Recommended Architecture

```
accra/
├── Sources/
│   └── Accra/
│       ├── Models/
│       │   └── AccessibilityNode.swift      # Tree node model
│       ├── Views/
│       │   ├── AccessibilityTreeView.swift  # Main tree component
│       │   ├── TreeNodeView.swift           # Individual node
│       │   └── TreeMinimapView.swift        # Optional minimap
│       ├── Services/
│       │   └── AccessibilityService.swift   # AX API integration
│       └── App.swift
└── Package.swift
```

---

## Related Research

None yet in this repository.

---

## Open Questions

1. **Performance target**: How many nodes should the tree handle smoothly? (100? 1000? 10000?)
2. **Update frequency**: How often does the tree need to refresh from live accessibility data?
3. **Multi-window**: Should the tree support inspecting multiple applications simultaneously?
4. **Customization**: Should users be able to configure which properties display per node?
5. **Export**: Is there a need to export tree data for analysis?

---

## Comprehensive Source Links

### SwiftUI & macOS Implementation
- [SwiftUI Hierarchy Lists](https://www.fivestars.blog/articles/swiftui-hierarchy-list/)
- [Displaying recursive data using OutlineGroup](https://swiftwithmajid.com/2020/09/02/displaying-recursive-data-using-outlinegroup-in-swiftui/)
- [SwiftUI macOS Tree List Demo](https://github.com/shufflingB/swiftui-macos-tree-list-demo)
- [NSOutlineView Tutorial](https://www.kodeco.com/1201-nsoutlineview-on-macos-tutorial)
- [Apple Outline Views HIG](https://developer.apple.com/design/human-interface-guidelines/components/layout-and-organization/outline-views/)

### Design Systems
- [Primer Tree View (GitHub)](https://primer.style/components/tree-view/)
- [Carbon Design System Tree View](https://carbondesignsystem.com/components/tree-view/usage/)
- [PatternFly Tree View](https://www.patternfly.org/components/tree-view/design-guidelines/)
- [Fluent 2 Tree Component](https://fluent2.microsoft.design/components/web/react/core/tree/usage)
- [The Component Gallery - Tree View](https://component.gallery/components/tree-view/)

### Accessibility Tools
- [Chrome Full Accessibility Tree](https://developer.chrome.com/blog/full-accessibility-tree)
- [Chrome DevTools Accessibility Reference](https://developer.chrome.com/docs/devtools/accessibility/reference)
- [Firefox Accessibility Inspector](https://firefox-source-docs.mozilla.org/devtools-user/accessibility_inspector/)
- [Apple Accessibility Inspector](https://developer.apple.com/documentation/accessibility/accessibility-inspector)

### Animation & Interaction
- [W3C Tree View Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/treeview/)
- [Micro-Interactions in SwiftUI](https://dev.to/sebastienlato/micro-interactions-in-swiftui-subtle-animations-that-make-apps-feel-premium-2ldn)
- [NN/G Animation Duration](https://www.nngroup.com/articles/animation-duration/)
- [Motion UI Trends 2025](https://www.betasofttechnology.com/motion-ui-trends-and-micro-interactions/)

### Alternative Visualizations
- [D3 Collapsible Tree](https://observablehq.com/@d3/collapsible-tree)
- [Observable Zoomable Icicle](https://observablehq.com/@d3/zoomable-icicle)
- [Hyperbolic Trees](https://en.wikipedia.org/wiki/Hyperbolic_tree)
- [Hierarchical Edge Bundling](https://gist.github.com/mbostock/1044242)
- [Observable Tangled Tree](https://observablehq.com/@nitaku/tangled-tree-visualization-ii)
- [Data-to-Viz Circular Packing](https://www.data-to-viz.com/graph/circularpacking.html)

### UX Best Practices
- [Interaction Design for Trees](https://medium.com/@hagan.rivers/interaction-design-for-trees-5e915b408ed2)
- [How to Show Hierarchical Data](https://www.interaction-design.org/literature/article/how-to-show-hierarchical-data-with-information-visualization)
- [NN/G Treemaps](https://www.nngroup.com/articles/treemaps/)
- [Handling Tree View Indentation](https://ishadeed.com/article/tree-view-css-indent/)

### Visual Inspiration
- [Dribbble Tree View UI](https://dribbble.com/search/tree-view-ui)
- [10 CSS Tree View Examples](https://www.subframe.com/tips/css-tree-view-examples)
- [Shadcn Tree View](https://www.shadcn.io/template/mrlightful-shadcn-tree-view)

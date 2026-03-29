import SwiftUI

// MARK: - Configuration

enum ScrollLayout: String, CaseIterable, Identifiable {
    case verticalHorizontal = "V→H"
    case horizontalVertical = "H→V"
    case verticalVertical = "V→V"
    case tripleNest = "V→H→V"

    var id: String { rawValue }
}

enum ItemDensity: String, CaseIterable, Identifiable {
    case sparse = "5"
    case medium = "15"
    case dense = "40"

    var id: String { rawValue }
    var count: Int {
        switch self {
        case .sparse: return 5
        case .medium: return 15
        case .dense: return 40
        }
    }
}

enum SectionCount: String, CaseIterable, Identifiable {
    case one = "1"
    case three = "3"
    case six = "6"

    var id: String { rawValue }
    var count: Int {
        switch self {
        case .one: return 1
        case .three: return 3
        case .six: return 6
        }
    }
}

// MARK: - Main View

struct NestedScrollView: View {
    @State private var layout: ScrollLayout = .verticalHorizontal
    @State private var sections: SectionCount = .three
    @State private var density: ItemDensity = .medium
    @State private var showIndicators = false
    @State private var pagingEnabled = false
    @State private var showControls = true

    private var sectionIndices: [Int] { Array(0..<sections.count) }
    private var itemIndices: [Int] { Array(0..<density.count) }

    var body: some View {
        VStack(spacing: 0) {
            if showControls {
                controlPanel
            }

            scrollContent
        }
        .navigationTitle("Nested Scrolls")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(showControls ? "Hide" : "Config") {
                    withAnimation { showControls.toggle() }
                }
                .accessibilityIdentifier("nestedScroll.toggleConfig")
            }
        }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Layout").font(.caption2).foregroundStyle(.secondary)
                Picker("Layout", selection: $layout) {
                    ForEach(ScrollLayout.allCases) { l in
                        Text(l.rawValue).tag(l)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("nestedScroll.layoutPicker")
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sections").font(.caption2).foregroundStyle(.secondary)
                    Picker("Sections", selection: $sections) {
                        ForEach(SectionCount.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("nestedScroll.sectionsPicker")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Items").font(.caption2).foregroundStyle(.secondary)
                    Picker("Items", selection: $density) {
                        ForEach(ItemDensity.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("nestedScroll.densityPicker")
                }
            }

            HStack(spacing: 16) {
                Toggle("Indicators", isOn: $showIndicators)
                    .accessibilityIdentifier("nestedScroll.indicatorsToggle")
                Toggle("Paging", isOn: $pagingEnabled)
                    .accessibilityIdentifier("nestedScroll.pagingToggle")
            }
            .toggleStyle(.switch)
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityIdentifier("nestedScroll.controlPanel")
    }

    // MARK: - Scroll Content

    @ViewBuilder
    private var scrollContent: some View {
        switch layout {
        case .verticalHorizontal:
            verticalOuterHorizontalInner
        case .horizontalVertical:
            horizontalOuterVerticalInner
        case .verticalVertical:
            verticalOuterVerticalInner
        case .tripleNest:
            tripleNestedLayout
        }
    }

    // MARK: - Layout: V outer → H inner (App Store style)

    private var verticalOuterHorizontalInner: some View {
        ScrollView(.vertical, showsIndicators: showIndicators) {
            LazyVStack(spacing: 24) {
                ForEach(sectionIndices, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(section)

                        ScrollView(.horizontal, showsIndicators: showIndicators) {
                            LazyHStack(spacing: 12) {
                                ForEach(itemIndices, id: \.self) { item in
                                    itemCard(section: section, item: item, width: 140, height: 180)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .accessibilityIdentifier("section.\(section).carousel")
                    }
                }

                footer
            }
            .padding(.vertical)
        }
        .accessibilityIdentifier("nestedScroll.outer")
    }

    // MARK: - Layout: H outer → V inner (page tabs)

    private var horizontalOuterVerticalInner: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: showIndicators) {
                LazyHStack(spacing: 0) {
                    ForEach(sectionIndices, id: \.self) { section in
                        ScrollView(.vertical, showsIndicators: showIndicators) {
                            LazyVStack(spacing: 8) {
                                sectionHeader(section)

                                ForEach(itemIndices, id: \.self) { item in
                                    itemRow(section: section, item: item)
                                }

                                footer
                            }
                            .padding()
                        }
                        .frame(width: geo.size.width)
                        .accessibilityIdentifier("section.\(section).page")
                    }
                }
            }
            .accessibilityIdentifier("nestedScroll.outer")
        }
    }

    // MARK: - Layout: V outer → V inner (nested lists)

    private var verticalOuterVerticalInner: some View {
        ScrollView(.vertical, showsIndicators: showIndicators) {
            LazyVStack(spacing: 24) {
                ForEach(sectionIndices, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(section)

                        ScrollView(.vertical, showsIndicators: showIndicators) {
                            LazyVStack(spacing: 4) {
                                ForEach(itemIndices, id: \.self) { item in
                                    itemRow(section: section, item: item)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 200)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.quaternary)
                        )
                        .padding(.horizontal)
                        .accessibilityIdentifier("section.\(section).innerList")
                    }
                }

                footer
            }
            .padding(.vertical)
        }
        .accessibilityIdentifier("nestedScroll.outer")
    }

    // MARK: - Layout: V → H → V (triple nesting)

    private var tripleNestedLayout: some View {
        ScrollView(.vertical, showsIndicators: showIndicators) {
            LazyVStack(spacing: 24) {
                ForEach(sectionIndices, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(section)

                        ScrollView(.horizontal, showsIndicators: showIndicators) {
                            LazyHStack(spacing: 16) {
                                ForEach(0..<3, id: \.self) { column in
                                    ScrollView(.vertical, showsIndicators: showIndicators) {
                                        LazyVStack(spacing: 4) {
                                            Text("Column \(column + 1)")
                                                .font(.caption.bold())
                                                .accessibilityIdentifier(
                                                    "section.\(section).col.\(column).header"
                                                )

                                            ForEach(itemIndices, id: \.self) { item in
                                                itemRow(
                                                    section: section, item: item,
                                                    prefix: "c\(column)"
                                                )
                                            }
                                        }
                                        .padding(8)
                                    }
                                    .frame(width: 250, height: 200)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.quaternary)
                                    )
                                    .accessibilityIdentifier(
                                        "section.\(section).col.\(column).scroll"
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                        .accessibilityIdentifier("section.\(section).carousel")
                    }
                }

                footer
            }
            .padding(.vertical)
        }
        .accessibilityIdentifier("nestedScroll.outer")
    }

    // MARK: - Shared Components

    private func sectionHeader(_ section: Int) -> some View {
        Text("Section \(section + 1)")
            .font(.headline)
            .padding(.horizontal)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("section.\(section).header")
    }

    private var footer: some View {
        Text("\(sections.count) sections \u{b7} \(density.count) items each")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("nestedScroll.footer")
    }

    private func itemCard(section: Int, item: Int, width: CGFloat, height: CGFloat) -> some View {
        VStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(itemColor(section: section, item: item))
                .frame(width: width, height: height)

            Text("Item \(item + 1)")
                .font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Section \(section + 1) Item \(item + 1)")
        .accessibilityIdentifier("section.\(section).item.\(item)")
    }

    private func itemRow(section: Int, item: Int, prefix: String? = nil) -> some View {
        let id = [prefix, "section.\(section).item.\(item)"]
            .compactMap { $0 }
            .joined(separator: ".")

        return HStack {
            Circle()
                .fill(itemColor(section: section, item: item))
                .frame(width: 28, height: 28)

            Text("Item \(item + 1)")
                .font(.subheadline)

            Spacer()

            Text("S\(section + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Section \(section + 1) Item \(item + 1)")
        .accessibilityIdentifier(id)
    }

    private func itemColor(section: Int, item: Int) -> Color {
        let total = max(sections.count * density.count, 1)
        return Color(
            hue: Double(section * density.count + item) / Double(total),
            saturation: 0.55,
            brightness: 0.88
        )
    }
}

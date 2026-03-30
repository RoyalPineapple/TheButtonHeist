import SwiftUI
import UIKit

/// Probes raw UIAccessibilityTraits bitmask on every element in the view hierarchy.
/// Displays the bit positions so we can discover private traits on real controls.
struct TraitProbeView: View {
    @State private var results: [TraitResult] = []
    @State private var showControls = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Scan Traits") { scanTraits() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("traitProbe.scan")
                Toggle("Controls", isOn: $showControls)
                    .fixedSize()
                Button("Clear") { results.removeAll() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if showControls {
                controlsSection
            }

            Divider()

            List(results) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.label)
                        .font(.system(.caption, design: .monospaced))
                        .bold()
                    Text("bits: \(r.bitString)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if !r.unknownBits.isEmpty {
                        Text("UNKNOWN: \(r.unknownBits)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
            }
            .accessibilityIdentifier("traitProbe.results")
        }
        .navigationTitle("Trait Probe")
    }

    // MARK: - Controls to probe

    @State private var toggleValue = false
    @State private var pickerValue = "A"
    @State private var sliderValue = 0.5
    @State private var stepperValue = 3
    @State private var dateValue = Date()
    @State private var secureText = ""
    @State private var normalText = ""
    @State private var showingAlert = false
    @State private var showingSheet = false

    private var controlsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    Toggle("Test Toggle", isOn: $toggleValue)
                        .accessibilityIdentifier("traitProbe.toggle")

                    Picker("Segment", selection: $pickerValue) {
                        Text("A").tag("A")
                        Text("B").tag("B")
                        Text("C").tag("C")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("traitProbe.segmented")

                    Picker("Menu Pick", selection: $pickerValue) {
                        Text("Alpha").tag("A")
                        Text("Beta").tag("B")
                    }
                    .accessibilityIdentifier("traitProbe.menuPicker")

                    Slider(value: $sliderValue)
                        .accessibilityIdentifier("traitProbe.slider")

                    Stepper("Count: \(stepperValue)", value: $stepperValue)
                        .accessibilityIdentifier("traitProbe.stepper")

                    DatePicker("Date", selection: $dateValue)
                        .accessibilityIdentifier("traitProbe.datePicker")
                }

                Group {
                    SecureField("Password", text: $secureText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("traitProbe.secureField")

                    TextField("Normal text", text: $normalText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("traitProbe.textField")

                    Link("Example Link", destination: URL(string: "https://example.com")!)
                        .accessibilityIdentifier("traitProbe.link")

                    Button("Show Alert") { showingAlert = true }
                        .accessibilityIdentifier("traitProbe.alertButton")

                    Button("Show Sheet") { showingSheet = true }
                        .accessibilityIdentifier("traitProbe.sheetButton")

                    Label("Info Label", systemImage: "info.circle")
                        .accessibilityIdentifier("traitProbe.infoLabel")

                    ProgressView(value: 0.6)
                        .accessibilityIdentifier("traitProbe.progress")

                    Image(systemName: "star.fill")
                        .accessibilityLabel("Star")
                        .accessibilityIdentifier("traitProbe.image")
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 300)
        .alert("Test Alert", isPresented: $showingAlert) {
            Button("OK") {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is a test alert for trait probing")
        }
        .sheet(isPresented: $showingSheet) {
            VStack {
                Text("Sheet Content")
                Button("Dismiss") { showingSheet = false }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Trait scanning

    private func scanTraits() {
        results.removeAll()
        guard let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else { return }

        // Walk ALL UIViews — record traits and also probe private SPI
        walkAllViews(window, depth: 0)
    }

    /// Walk the entire UIView hierarchy. For every view:
    /// 1. Record raw accessibilityTraits if non-zero
    /// 2. Probe _accessibilityIsScrollable SPI
    /// 3. Walk accessibilityElements (crosses into SwiftUI AccessibilityNode tree)
    private func walkAllViews(_ view: UIView, depth: Int) {
        let cls = String(describing: type(of: view))
        let traits = view.accessibilityTraits.rawValue

        // Always record views with traits
        if traits != 0 {
            let label = view.accessibilityLabel ?? cls
            addResult(label: label, identifier: view.accessibilityIdentifier,
                      traits: traits, depth: depth, source: "view")
        }

        // Probe _accessibilityIsScrollable SPI on scroll views
        let scrollableSel = NSSelectorFromString("_accessibilityIsScrollable")
        if view.responds(to: scrollableSel),
           let result = view.perform(scrollableSel) {
            // performSelector returns Unmanaged; for BOOL the pointer IS the value
            let isScrollable = Int(bitPattern: result.toOpaque()) != 0
            if isScrollable {
                // Record this view with its traits + scrollable annotation
                let label = view.accessibilityLabel ?? cls
                var extra = "scrollable=YES"
                // Also check scroll status
                let statusSel = NSSelectorFromString("_accessibilityScrollStatus")
                if view.responds(to: statusSel),
                   let statusResult = view.perform(statusSel)?.takeUnretainedValue() as? String {
                    extra += " status=\"\(statusResult)\""
                }
                addResult(label: "\(label) [\(extra)]",
                          identifier: view.accessibilityIdentifier,
                          traits: traits, depth: depth, source: "spi")
            }
        }

        // Walk accessibilityElements — this crosses into SwiftUI's AccessibilityNode tree
        if let elements = view.accessibilityElements {
            for element in elements {
                guard let obj = element as? NSObject else { continue }
                walkAccessibilityNode(obj, depth: depth + 1)
            }
        }

        // Recurse into subviews
        for sub in view.subviews {
            walkAllViews(sub, depth: depth + 1)
        }
    }

    /// Walk a SwiftUI AccessibilityNode and its children recursively.
    /// AccessibilityNodes expose children via accessibilityElements property.
    private func walkAccessibilityNode(_ obj: NSObject, depth: Int) {
        guard depth < 20 else { return }

        let traits = obj.accessibilityTraits.rawValue
        let isElement = obj.isAccessibilityElement
        let label = obj.accessibilityLabel
        let cls = String(describing: type(of: obj))

        if traits != 0 || isElement {
            let displayLabel = label ?? cls
            let id = (obj as? UIAccessibilityIdentification)?.accessibilityIdentifier
            addResult(label: displayLabel, identifier: id, traits: traits,
                      depth: depth, source: "node")
        }

        // Walk children via accessibilityElements
        if let elements = obj.accessibilityElements {
            for element in elements {
                guard let child = element as? NSObject else { continue }
                walkAccessibilityNode(child, depth: depth + 1)
            }
        }
    }
    private func addResult(label: String, identifier: String?, traits: UInt64, depth: Int, source: String) {
        let known: [(Int, String)] = [
            // Public traits (bits 0-14, 16-17)
            (0, "button"), (1, "link"), (2, "image"), (3, "selected"),
            (4, "playsSound"), (5, "keyboardKey"), (6, "staticText"),
            (7, "summaryElement"), (8, "notEnabled"), (9, "updatesFrequently"),
            (10, "searchField"), (11, "startsMediaSession"), (12, "adjustable"),
            (13, "allowsDirectInteraction"), (14, "causesPageTurn"),
            (16, "header"), (17, "tabBar"),
            // Private traits (confirmed via AccessibilitySnapshotParser + AXRuntime)
            (18, "textEntry"), (19, "pickerElement"), (20, "radioButton"),
            (21, "isEditing"), (22, "launchIcon"), (23, "statusBarElement"),
            (24, "secureTextField"), (25, "inactive"), (26, "footer"),
            (27, "backButton"), (28, "tabBarItem"),
            // Higher private traits
            (29, "autoCorrectCandidate"), (30, "deleteKey"),
            (31, "selectionDismissesItem"), (32, "visited"),
            (47, "scrollable"), (53, "switchButton"),
        ]

        var bits: [String] = []
        var unknowns: [String] = []
        for b in 0..<64 where traits & (1 << b) != 0 {
            if let entry = known.first(where: { $0.0 == b }) {
                bits.append("\(b):\(entry.1)")
            } else {
                bits.append("\(b):???")
                unknowns.append("bit\(b)=0x\(String(1 << b, radix: 16))")
            }
        }

        let prefix = String(repeating: "  ", count: min(depth, 4))
        let idStr = identifier.map { " [\($0)]" } ?? ""
        let result = TraitResult(
            label: "\(prefix)\(source)| \(label)\(idStr)",
            bitString: bits.joined(separator: " "),
            unknownBits: unknowns.joined(separator: " "),
            rawValue: traits
        )
        results.append(result)
    }
}

struct TraitResult: Identifiable {
    let id = UUID()
    let label: String
    let bitString: String
    let unknownBits: String
    let rawValue: UInt64
}

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

        // Walk the UIView hierarchy for UIKit controls (UISwitch, UITextField, etc.)
        // AND collect hosting views to walk their SwiftUI accessibility trees.
        var hostingViews: [UIView] = []
        walkViews(window, depth: 0, hostingViews: &hostingViews)

        // Walk SwiftUI accessibility trees rooted at each hosting view.
        for host in hostingViews {
            walkSwiftUIAccessibilityTree(host, depth: 0)
        }
    }

    private func walkViews(_ view: UIView, depth: Int, hostingViews: inout [UIView]) {
        let traits = view.accessibilityTraits.rawValue
        if traits != 0 {
            let label = view.accessibilityLabel ?? String(describing: type(of: view))
            let id = view.accessibilityIdentifier
            addResult(label: label, identifier: id, traits: traits, depth: depth, source: "view")
        }
        // Detect SwiftUI hosting views — they contain the accessibility tree root
        let cls = String(describing: type(of: view))
        if cls.contains("HostingView") || cls.contains("HostingController") {
            hostingViews.append(view)
        }
        for sub in view.subviews {
            walkViews(sub, depth: depth + 1, hostingViews: &hostingViews)
        }
    }

    /// Walk the SwiftUI accessibility tree by finding hosting views and
    /// walking their accessibilityElement children recursively.
    /// SwiftUI hosting views expose AccessibilityNode children via
    /// accessibilityElement(at:) — not via _accessibilityNodeChildrenUnsorted
    /// which returns Swift Arrays that don't bridge through performSelector.
    private func walkSwiftUIAccessibilityTree(_ obj: NSObject, depth: Int) {
        guard depth < 20 else { return }

        // Walk accessibilityElements property if available
        if let elements = obj.accessibilityElements {
            for element in elements {
                guard let child = element as? NSObject else { continue }
                recordAndRecurse(child, depth: depth)
            }
            return
        }

        // Walk indexed accessibility elements
        let count = obj.accessibilityElementCount()
        if count > 0, count < 500, count != NSNotFound {
            for i in 0..<count {
                guard let child = obj.accessibilityElement(at: i) as? NSObject else { continue }
                recordAndRecurse(child, depth: depth)
            }
        }
    }

    private func recordAndRecurse(_ child: NSObject, depth: Int) {
        let traits = child.accessibilityTraits.rawValue
        let isElement = child.isAccessibilityElement
        let label = child.accessibilityLabel
        let cls = String(describing: type(of: child))

        if traits != 0 || isElement {
            let displayLabel = label ?? cls
            let id = (child as? UIAccessibilityIdentification)?.accessibilityIdentifier
            addResult(label: displayLabel, identifier: id, traits: traits, depth: depth, source: "swui")
        }

        walkSwiftUIAccessibilityTree(child, depth: depth + 1)
    }

    private func addResult(label: String, identifier: String?, traits: UInt64, depth: Int, source: String) {
        let known: [(Int, String)] = [
            (0, "button"), (1, "link"), (2, "image"), (3, "selected"),
            (4, "playsSound"), (5, "keyboardKey"), (6, "staticText"),
            (7, "summaryElement"), (8, "notEnabled"), (9, "updatesFrequently"),
            (10, "searchField"), (11, "startsMediaSession"), (12, "adjustable"),
            (13, "allowsDirectInteraction"), (14, "causesPageTurn"), (15, "header"),
            (18, "textEntry"), (21, "isEditing"), (24, "secureTextField"),
            (27, "backButton"), (28, "tabBarItem"), (47, "scrollable"),
            (48, "tabBar"), (53, "switchButton"),
        ]
        _ = Set(known.map(\.0))

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

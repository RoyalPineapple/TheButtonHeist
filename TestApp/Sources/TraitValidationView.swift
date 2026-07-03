import SwiftUI
import UIKit

// MARK: - Trait Validation Screen

/// Exercises every known private accessibility trait so we can validate bit positions.
/// Tap "Scan All" to walk the full accessibility tree and dump raw trait bitmasks.
struct TraitValidationView: View {
    @State private var results: [TraitScanResult] = []
    @State private var filterUnknownOnly = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            controlSurface
            Divider()
            resultsList
        }
        .navigationTitle("Trait Validation")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Scan All") { runScan() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("traitVal.scan")
            Toggle("Unknown", isOn: $filterUnknownOnly)
                .fixedSize()
            Spacer()
            Text("\(filteredResults.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Clear") { results.removeAll() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("traitVal.clear")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Results

    private var filteredResults: [TraitScanResult] {
        filterUnknownOnly ? results.filter { !$0.unknownBits.isEmpty } : results
    }

    private var resultsList: some View {
        List(filteredResults) { r in
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label)
                    .font(.system(.caption, design: .monospaced))
                    .bold()
                Text(r.bitString)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !r.unknownBits.isEmpty {
                    Text("UNKNOWN: \(r.unknownBits)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
        }
        .accessibilityIdentifier("traitVal.results")
    }

    // MARK: - Control Surface
    //
    // Every section targets a specific private trait. Controls are chosen to
    // provoke the trait so the scanner can read the raw bitmask.

    @State private var toggleVal = false
    @State private var sliderVal = 0.5
    @State private var textVal = ""
    @State private var secureVal = ""

    private var controlSurface: some View {
        VStack(alignment: .leading, spacing: 4) {
            // bit 0: button + bit 8: notEnabled
            Button("Button") {}.accessibilityIdentifier("tv.button")
            Button("Disabled") {}.disabled(true).accessibilityIdentifier("tv.disabledButton")
            // bit 1: link
            if let exampleURL = URL(string: "https://example.com") {
                Link("Link", destination: exampleURL).accessibilityIdentifier("tv.link")
            }
            // bit 2: image
            Image(systemName: "star.fill").accessibilityLabel("Star").accessibilityIdentifier("tv.image")
            // bit 6: staticText
            Text("Static").accessibilityIdentifier("tv.static")
            // bit 9: updatesFrequently
            ProgressView(value: 0.6).accessibilityIdentifier("tv.progress")
            // bit 12: adjustable
            Slider(value: $sliderVal).accessibilityIdentifier("tv.slider")
            // bit 16: header
            Text("Header").accessibilityAddTraits(.isHeader).accessibilityIdentifier("tv.header")
            // bit 18: textEntry
            TextField("Text", text: $textVal).textFieldStyle(.roundedBorder).accessibilityIdentifier("tv.text")
            // bit 24: secureTextField
            SecureField("Pass", text: $secureVal).textFieldStyle(.roundedBorder).accessibilityIdentifier("tv.secure")
            // bit 53: switchButton
            Toggle("Toggle", isOn: $toggleVal).accessibilityIdentifier("tv.toggle")
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Scanner

    private func runScan() {
        results.removeAll()
        nodeVisited.removeAll()
        guard let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else { return }

        walkAllViews(window, depth: 0)

        // Write results to tmp file for easy reading
        let lines = results.map { r in
            var line = "\(r.label) | \(r.bitString)"
            if !r.unknownBits.isEmpty { line += " | UNKNOWN: \(r.unknownBits)" }
            return line
        }
        let content = lines.joined(separator: "\n")
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("trait_scan.txt")
        do {
            try content.write(to: path, atomically: true, encoding: .utf8)
            print("[TraitValidation] Wrote \(results.count) results to \(path.path)")
        } catch {
            print("[TraitValidation] Failed to write results: \(error)")
        }
    }

    private func walkAllViews(_ view: UIView, depth: Int) {
        guard depth < 30 else { return }
        let cls = String(describing: type(of: view))
        let traits = view.accessibilityTraits.rawValue

        if traits != 0 || view.isAccessibilityElement {
            let label = view.accessibilityLabel ?? cls
            record(label: label, identifier: view.accessibilityIdentifier,
                   traits: traits, depth: depth, source: "view")
        }

        // SPI: _accessibilityIsScrollable
        probeScrollableSPI(view, depth: depth)

        // Cross into SwiftUI AccessibilityNode tree
        if let elements = view.accessibilityElements {
            for element in elements {
                guard let obj = element as? NSObject else { continue }
                walkAccessibilityNode(obj, depth: depth + 1)
            }
        }

        for sub in view.subviews {
            walkAllViews(sub, depth: depth + 1)
        }
    }

    // Track visited nodes to avoid cycles in the accessibility tree
    @State private var nodeVisited = Set<ObjectIdentifier>()

    private func walkAccessibilityNode(_ obj: NSObject, depth: Int) {
        guard depth < 25 else { return }
        let oid = ObjectIdentifier(obj)
        guard !nodeVisited.contains(oid) else { return }
        nodeVisited.insert(oid)

        let traits = obj.accessibilityTraits.rawValue
        let isElement = obj.isAccessibilityElement
        let label = obj.accessibilityLabel
        let cls = String(describing: type(of: obj))

        if traits != 0 || isElement {
            let displayLabel = label ?? cls
            let id = (obj as? UIAccessibilityIdentification)?.accessibilityIdentifier
            record(label: displayLabel, identifier: id, traits: traits, depth: depth, source: "node")
        }

        // Walk children
        if let elements = obj.accessibilityElements {
            for element in elements {
                guard let child = element as? NSObject else { continue }
                walkAccessibilityNode(child, depth: depth + 1)
            }
        }
    }

    private func probeScrollableSPI(_ view: UIView, depth: Int) {
        let sel = NSSelectorFromString("_accessibilityIsScrollable")
        guard view.responds(to: sel),
              let result = view.perform(sel) else { return }
        let isScrollable = Int(bitPattern: result.toOpaque()) != 0
        guard isScrollable else { return }

        let cls = String(describing: type(of: view))
        let label = view.accessibilityLabel ?? cls
        var extra = "scrollable=YES"
        let statusSel = NSSelectorFromString("_accessibilityScrollStatus")
        if view.responds(to: statusSel),
           let statusResult = view.perform(statusSel)?.takeUnretainedValue() as? String {
            extra += " \"\(statusResult)\""
        }
        record(label: "\(label) [\(extra)]", identifier: view.accessibilityIdentifier,
               traits: view.accessibilityTraits.rawValue, depth: depth, source: "spi")
    }

    // MARK: - Recording

    // Complete trait map: public + all confirmed private bits from AXRuntime
    private static let traitMap: [(Int, String)] = [
        // Public UIAccessibilityTraits
        (0, "button"), (1, "link"), (2, "image"), (3, "selected"),
        (4, "playsSound"), (5, "keyboardKey"), (6, "staticText"),
        (7, "summaryElement"), (8, "notEnabled"), (9, "updatesFrequently"),
        (10, "searchField"), (11, "startsMediaSession"), (12, "adjustable"),
        (13, "allowsDirectInteraction"), (14, "causesPageTurn"),
        // Public but different bit than old header constant
        (16, "header"),
        // Private — from AXRuntime / empirical observation
        (17, "webContent"), (18, "textEntry"), (19, "pickerElement"),
        (20, "radioButton"), (21, "isEditing"), (22, "launchIcon"),
        (23, "statusBarElement"), (24, "secureTextField"), (25, "inactive"),
        (26, "footer"), (27, "backButton"), (28, "tabBarItem"),
        (29, "autoCorrectCandidate"), (30, "deleteKey"),
        (31, "selectionDismissesItem"), (32, "visited"),
        (33, "AXScrollable"), (34, "spacer"), (35, "tableIndex"),
        (36, "map"), (37, "textOpsAvailable"), (38, "draggable"),
        (40, "popupButton"),
        // Higher bits
        (47, "textArea"), (48, "tabBar"),
        (52, "menuItem"), (53, "switchButton"),
        (56, "alert"),
    ]

    private func record(label: String, identifier: String?, traits: UInt64, depth: Int, source: String) {
        var bits: [String] = []
        var unknowns: [String] = []
        for b in 0..<64 where traits & (1 << b) != 0 {
            if let entry = Self.traitMap.first(where: { $0.0 == b }) {
                bits.append("\(b):\(entry.1)")
            } else {
                bits.append("\(b):???")
                unknowns.append("bit\(b)")
            }
        }

        let prefix = String(repeating: "  ", count: min(depth, 3))
        let idStr = identifier.map { " [\($0)]" } ?? ""
        results.append(TraitScanResult(
            label: "\(prefix)\(source)| \(label)\(idStr)",
            bitString: bits.joined(separator: " "),
            unknownBits: unknowns.joined(separator: " ")
        ))
    }
}

struct TraitScanResult: Identifiable {
    let id = UUID()
    let label: String
    let bitString: String
    let unknownBits: String
}

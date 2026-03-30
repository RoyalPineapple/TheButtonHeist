import SwiftUI
import UIKit

/// Test harness for probing private accessibility scroll SPI methods.
///
/// Layout: a tall ScrollView with 200 numbered items. The view exposes
/// accessibility identifiers on every element so Button Heist can target them.
/// Use LLDB to call SPI methods on the backing UIKit objects:
///
///   # Find the element's backing object
///   (lldb) po view.accessibilityElements
///
///   # Test _accessibilityScrollToVisible on an off-screen element
///   (lldb) po [element _accessibilityScrollToVisible]
///
///   # Test accessibilityScrollDownPage on the scroll view
///   (lldb) po [scrollView accessibilityScrollDownPage]
///
/// The "SPI Log" section at the top shows results from programmatic probes
/// triggered by the buttons, so you can also test without LLDB.
struct ScrollSPIHarnessView: View {
    @State private var logLines: [String] = []
    @State private var probeTargetIndex = 150

    var body: some View {
        VStack(spacing: 0) {
            controlPanel
            Divider()
            scrollContent
        }
        .navigationTitle("Scroll SPI Harness")
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Target item:")
                    .font(.caption)
                TextField("Index", value: $probeTargetIndex, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .accessibilityIdentifier("spiHarness.targetIndex")
            }

            HStack(spacing: 8) {
                Button("scrollToVisible") { probeScrollToVisible() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("spiHarness.btn.scrollToVisible")

                Button("respondsTo?") { probeRespondsTo() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("spiHarness.btn.respondsTo")

                Button("Clear") { logLines.removeAll() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("spiHarness.btn.clear")
            }
            .font(.caption)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                    }
                }
            }
            .frame(height: logLines.isEmpty ? 0 : 60)
            .accessibilityIdentifier("spiHarness.log")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<200, id: \.self) { index in
                    HStack {
                        Text("Item \(index)")
                            .font(.body)
                        Spacer()
                        Text("row \(index)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("spiHarness.item.\(index)")
                    .accessibilityLabel("Item \(index)")
                    if index < 199 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .accessibilityIdentifier("spiHarness.scrollView")
    }

    // MARK: - SPI Probes

    private func log(_ message: String) {
        logLines.append(message)
    }

    private func probeRespondsTo() {
        let selectors = [
            "_accessibilityScrollToVisible",
            "accessibilityScrollDownPage",
            "accessibilityScrollUpPage",
            "accessibilityScrollLeftPage",
            "accessibilityScrollRightPage",
            "_accessibilityScrollToTop",
            "_accessibilityScrollToBottom",
        ]
        guard let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else {
            log("ERR: no window")
            return
        }

        log("--- respondsTo check ---")

        // Walk the view hierarchy looking for our scroll view
        func findViews(in view: UIView, depth: Int = 0) {
            let name = String(describing: type(of: view))
            if name.contains("Scroll") || name.contains("Platform") || view is UIScrollView {
                let prefix = String(repeating: "  ", count: depth)
                log("\(prefix)\(name) [\(view.frame.width)x\(view.frame.height)]")
                for sel in selectors {
                    let responds = view.responds(to: NSSelectorFromString(sel))
                    if responds {
                        log("\(prefix)  ✓ \(sel)")
                    }
                }
            }
            for sub in view.subviews {
                findViews(in: sub, depth: depth + 1)
            }
        }

        findViews(in: window)
    }

    private func probeScrollToVisible() {
        guard let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else {
            log("ERR: no window")
            return
        }

        let targetId = "spiHarness.item.\(probeTargetIndex)"
        log("Probing _accessibilityScrollToVisible for \(targetId)")

        // Find the element by walking accessibility elements
        func findElement(in view: UIView) -> NSObject? {
            if view.accessibilityIdentifier == targetId {
                return view
            }
            // Check accessibility elements
            if let elements = view.accessibilityElements {
                for element in elements {
                    guard let obj = element as? NSObject else { continue }
                    if (obj as? UIAccessibilityIdentification)?.accessibilityIdentifier == targetId {
                        return obj
                    }
                }
            }
            for sub in view.subviews {
                if let found = findElement(in: sub) {
                    return found
                }
            }
            return nil
        }

        guard let element = findElement(in: window) else {
            log("ERR: element not found (may be off-screen in lazy container)")
            log("Try scrolling closer first, or use LLDB on a UIScrollView subview")
            return
        }

        let sel = NSSelectorFromString("_accessibilityScrollToVisible")
        let responds = element.responds(to: sel)
        log("responds(to: _accessibilityScrollToVisible) = \(responds)")

        if responds {
            let result = element.perform(sel)
            // The method returns BOOL, but perform returns Unmanaged<AnyObject>?
            // A non-nil result with value 1 = YES
            let boolResult = result != nil
            log("_accessibilityScrollToVisible() returned: \(boolResult)")
        } else {
            log("Element type: \(type(of: element))")
            // Check if the scroll view responds
            if let scrollView = findScrollView(in: window) {
                log("Found scroll view: \(type(of: scrollView))")
                log("ScrollView responds: \(scrollView.responds(to: sel))")
            }
        }
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let sv = view as? UIScrollView,
           sv.accessibilityIdentifier == "spiHarness.scrollView" {
            return sv
        }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) {
                return found
            }
        }
        return nil
    }
}

import SwiftUI
import UIKit

/// A grid of modal permutations exercising every code path in TheTripwire's
/// `getAccessibleWindows()` filtering:
///
/// 1. **No modal** — baseline, all elements visible.
/// 2. **`accessibilityViewIsModal` flag** — ModalWindowDemo handles the
///    separate-window case; this screen exercises the same flag set on a
///    subview within the main window.
/// 3. **Overlay window (`windowLevel > .normal`)** — SwiftUI `.alert` and
///    `.confirmationDialog` host a UIAlertController in its own alert-level
///    window with a rootViewController.
/// 4. **`presentedViewController`** — SwiftUI `.sheet`, `.fullScreenCover`,
///    and the UIKit-backed buttons walk the presentation chain.
/// 5. **Deeply stacked presentations** — sheet → sheet → alert exercises
///    the `while let presented` walk to the deepest VC.
struct ModalPermutationsDemo: View {
    @State private var presentation: Permutation?
    @State private var sheetLevel = 0
    @State private var lastEvent = "None"

    enum Permutation: String, Identifiable {
        case sheet
        case fullScreenCover
        case stackedSheets
        case stackedSheetsWithAlert
        case inlineModalFlag
        case uikitFullScreen
        case uikitFormSheet
        case uikitPageSheet

        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section("Background Content") {
                ForEach(0..<8) { index in
                    Text("Background row \(index)")
                        .accessibilityLabel("Background row \(index)")
                }
            }

            Section("Single-Level Presentations") {
                Button("Sheet (.sheet)") { trigger(.sheet, "Sheet shown") }
                Button("Full-screen cover") { trigger(.fullScreenCover, "Cover shown") }
                Button("UIKit fullScreen modal") { trigger(.uikitFullScreen, "UIKit fullScreen shown") }
                Button("UIKit formSheet modal") { trigger(.uikitFormSheet, "UIKit formSheet shown") }
                Button("UIKit pageSheet modal") { trigger(.uikitPageSheet, "UIKit pageSheet shown") }
            }

            Section("Stacked Presentations") {
                Button("Sheet → Sheet → Alert") {
                    sheetLevel = 1
                    trigger(.stackedSheets, "Stacked sheet level 1")
                }
                Button("Sheet → Alert (auto-show alert)") {
                    sheetLevel = 1
                    trigger(.stackedSheetsWithAlert, "Stacked → alert")
                }
            }

            Section("Inline Modal Flag (Same Window)") {
                Button("Toggle inline modal overlay") {
                    trigger(.inlineModalFlag, "Inline modal toggled")
                }
            }

            Section {
                Text("Last event: \(lastEvent)")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Modal Permutations")
        .sheet(item: bindingForSheet()) { current in
            sheetContent(for: current)
        }
        .fullScreenCover(item: bindingForFullScreen()) { current in
            fullScreenCoverContent(for: current)
        }
    }

    // MARK: - Triggers

    private func trigger(_ perm: Permutation, _ event: String) {
        lastEvent = event
        switch perm {
        case .uikitFullScreen, .uikitFormSheet, .uikitPageSheet:
            presentUIKit(style: presentationStyle(for: perm))
        case .inlineModalFlag:
            presentInlineModalFlag()
        default:
            presentation = perm
        }
    }

    private func presentationStyle(for perm: Permutation) -> UIModalPresentationStyle {
        switch perm {
        case .uikitFullScreen: return .fullScreen
        case .uikitFormSheet: return .formSheet
        case .uikitPageSheet: return .pageSheet
        default: return .automatic
        }
    }

    private func bindingForSheet() -> Binding<Permutation?> {
        Binding(
            get: {
                guard let presentation else { return nil }
                return [.sheet, .stackedSheets, .stackedSheetsWithAlert].contains(presentation)
                    ? presentation : nil
            },
            set: { newValue in
                if newValue == nil { presentation = nil }
            }
        )
    }

    private func bindingForFullScreen() -> Binding<Permutation?> {
        Binding(
            get: {
                guard presentation == .fullScreenCover else { return nil }
                return presentation
            },
            set: { newValue in
                if newValue == nil { presentation = nil }
            }
        )
    }

    // MARK: - Sheet Contents

    @ViewBuilder
    private func sheetContent(for current: Permutation) -> some View {
        switch current {
        case .sheet:
            SheetLevelContent(
                title: "Single Sheet",
                level: 1,
                action: { presentation = nil }
            )
        case .stackedSheets:
            StackedSheetContent(
                level: sheetLevel,
                showAlertAtLevel2: false,
                onClose: { presentation = nil }
            )
        case .stackedSheetsWithAlert:
            StackedSheetContent(
                level: sheetLevel,
                showAlertAtLevel2: true,
                onClose: { presentation = nil }
            )
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fullScreenCoverContent(for current: Permutation) -> some View {
        switch current {
        case .fullScreenCover:
            VStack(spacing: 16) {
                Text("Full-Screen Cover")
                    .font(.title)
                    .accessibilityAddTraits(.isHeader)
                Text("Only this content should be in the accessibility tree.")
                Button("Dismiss") { presentation = nil }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        default:
            EmptyView()
        }
    }

    // MARK: - UIKit Presentation

    private func presentUIKit(style: UIModalPresentationStyle) {
        guard let topVC = topViewController() else { return }
        let presented = UIKitModalContent(modalStyle: style)
        presented.modalPresentationStyle = style
        topVC.present(presented, animated: true)
    }

    private func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topMostPresented()
    }

    // MARK: - Inline Modal Flag (same window)

    private func presentInlineModalFlag() {
        guard let topVC = topViewController() else { return }
        let overlay = UIView(frame: topVC.view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        overlay.accessibilityViewIsModal = true

        let label = UILabel()
        label.text = "Inline Modal (same window)"
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .title2)
        label.accessibilityTraits = .header
        label.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(label)

        let dismiss = UIButton(type: .system)
        dismiss.setTitle("Tap to dismiss", for: .normal)
        dismiss.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        dismiss.tintColor = .white
        dismiss.translatesAutoresizingMaskIntoConstraints = false
        dismiss.addAction(UIAction { [weak overlay] _ in
            overlay?.removeFromSuperview()
        }, for: .touchUpInside)
        overlay.addSubview(dismiss)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -20),
            dismiss.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            dismiss.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
        ])

        topVC.view.addSubview(overlay)
    }
}

// MARK: - Stacked Sheet Content

private struct StackedSheetContent: View {
    let level: Int
    let showAlertAtLevel2: Bool
    let onClose: () -> Void

    @State private var nextLevel: Int?
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Stacked Sheet — Level \(level)")
                .font(.title)
                .accessibilityAddTraits(.isHeader)

            if level < 3 {
                Button("Present level \(level + 1)") {
                    nextLevel = level + 1
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Reached deepest level")
            }

            Button("Show alert") { showAlert = true }
            Button("Close all", role: .destructive) { onClose() }
        }
        .padding()
        .sheet(item: Binding(
            get: { nextLevel.map { Identified(id: $0) } },
            set: { newValue in nextLevel = newValue?.id }
        )) { ident in
            StackedSheetContent(
                level: ident.id,
                showAlertAtLevel2: showAlertAtLevel2,
                onClose: {
                    nextLevel = nil
                    onClose()
                }
            )
        }
        .alert("Alert at Level \(level)", isPresented: $showAlert) {
            Button("OK") { showAlert = false }
        } message: {
            Text("This alert is presented from sheet level \(level).")
        }
        .onAppear {
            // Auto-show alert at level 2 when requested, to exercise the
            // "sheet → alert" stacked path without manual taps.
            if level == 2 && showAlertAtLevel2 {
                showAlert = true
            }
        }
    }
}

private struct Identified: Identifiable, Hashable {
    let id: Int
}

// MARK: - Single Sheet Content

private struct SheetLevelContent: View {
    let title: String
    let level: Int
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title)
                .accessibilityAddTraits(.isHeader)
            Text("Level \(level) of presentation chain.")
            Button("Dismiss") { action() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - UIKit Modal

private final class UIKitModalContent: UIViewController {
    private let modalStyle: UIModalPresentationStyle

    init(modalStyle: UIModalPresentationStyle) {
        self.modalStyle = modalStyle
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let title = UILabel()
        title.text = "UIKit \(styleName) Modal"
        title.font = .preferredFont(forTextStyle: .title1)
        title.textAlignment = .center
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityTraits = .header
        stack.addArrangedSubview(title)

        let body = UILabel()
        body.text = "Only this UIKit content should be in the tree."
        body.numberOfLines = 0
        body.textAlignment = .center
        stack.addArrangedSubview(body)

        let dismiss = UIButton(type: .system)
        dismiss.setTitle("Dismiss", for: .normal)
        dismiss.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        dismiss.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)
        stack.addArrangedSubview(dismiss)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.85),
        ])
    }

    private var styleName: String {
        switch modalStyle {
        case .fullScreen: return "Full-Screen"
        case .formSheet: return "Form Sheet"
        case .pageSheet: return "Page Sheet"
        case .popover: return "Popover"
        default: return "Modal"
        }
    }
}

private extension UIViewController {
    func topMostPresented() -> UIViewController {
        sequence(first: self, next: \.presentedViewController)
            .reduce(self) { _, next in next }
    }
}

#Preview {
    NavigationStack {
        ModalPermutationsDemo()
    }
}

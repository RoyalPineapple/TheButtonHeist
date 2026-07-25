import SwiftUI
import UIKit

/// One control per settlement case, so the four-case rule can be asserted
/// end to end.
///
/// The rule under test: a settle cycle whose accessibility diff is unchanged
/// **and** whose active `UIView` animation count sits above the pre-action
/// baseline is not settlement evidence — it is falsified stability.
///
/// | Case | Animations | AX change | Expected |
/// |------|-----------|-----------|----------|
/// | 1 | none | none | settles |
/// | 2 | short, completes | none | settles |
/// | 3 | indefinite | none | **fails** |
/// | 4 | indefinite | yes | settles |
///
/// Case 3 is the only failure, and it is the case with no prior coverage.
/// Compare `AnalogClockDemo`, which is case 3's shape but drives raw
/// `CAAnimation` on a layer — invisible to the `UIViewAnimationState` swizzle,
/// so it settles and must keep doing so.
struct SettlementCasesDemo: View {

    var body: some View {
        List {
            Section("Case 1 — no animation, no change") {
                InertButton()
            }
            Section("Case 2 — animation completes, no change") {
                CompletingAnimationButton()
            }
            Section("Case 3 — animation outlasts the action, no change") {
                IndefiniteAnimationButton()
            }
            Section("Case 4 — animation outlasts the action, tree changes") {
                IndefiniteAnimationWithChangeButton()
            }
        }
        .navigationTitle("Settlement Cases")
    }
}

// MARK: - Case 1

/// Activating this does nothing observable at all.
private struct InertButton: View {
    var body: some View {
        Button("Inert Control") {}
            .accessibilityHint("Produces no animation and no accessibility change")
    }
}

// MARK: - Case 2

/// A brief `UIView` animation that finishes well inside any action budget,
/// leaving the accessibility tree untouched.
private struct CompletingAnimationButton: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView {
        let container = PulseOnTapView(mode: .completing)
        container.accessibilityLabel = "Briefly Animating Control"
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Case 3

/// A repeating `UIView` animation with no end and no accessibility change.
/// This is the case the rule exists to catch.
private struct IndefiniteAnimationButton: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView {
        let container = PulseOnTapView(mode: .indefinite)
        container.accessibilityLabel = "Endlessly Animating Control"
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Case 4

/// The same endless animation as case 3, but the activation also mutates the
/// accessibility tree. A satisfied predicate is the authority, so this settles.
private struct IndefiniteAnimationWithChangeButton: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView {
        let container = PulseOnTapView(mode: .indefiniteWithChange)
        container.accessibilityLabel = "Endlessly Animating Control With Change"
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Shared Control

/// A tappable control whose activation starts a `UIView` animation.
///
/// `UIView.animate` is what `AnimationObserver` counts — the swizzle hooks
/// `UIViewAnimationState`, so a `CAAnimation` added straight to a layer would
/// not register and could not exercise the rule.
private final class PulseOnTapView: UIControl {

    enum Mode {
        case completing
        case indefinite
        case indefiniteWithChange
    }

    private let mode: Mode
    private let swatch = UIView()
    private let readout = UILabel()
    private var activations = 0

    init(mode: Mode) {
        self.mode = mode
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button

        swatch.backgroundColor = .systemBlue
        swatch.layer.cornerRadius = 6
        swatch.isAccessibilityElement = false
        swatch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatch)

        readout.font = .preferredFont(forTextStyle: .footnote)
        readout.textColor = .secondaryLabel
        // Case 4 reads this label back through the AX tree; the others keep it
        // out so their trees stay provably static.
        readout.isAccessibilityElement = mode == .indefiniteWithChange
        readout.translatesAutoresizingMaskIntoConstraints = false
        addSubview(readout)

        NSLayoutConstraint.activate([
            swatch.leadingAnchor.constraint(equalTo: leadingAnchor),
            swatch.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatch.widthAnchor.constraint(equalToConstant: 44),
            swatch.heightAnchor.constraint(equalToConstant: 44),
            readout.leadingAnchor.constraint(equalTo: swatch.trailingAnchor, constant: 12),
            readout.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 60),
        ])

        addTarget(self, action: #selector(activate), for: .touchUpInside)
        refreshReadout()
    }

    required init?(coder: NSCoder) { return nil }

    @objc private func activate() {
        activations += 1
        if mode == .indefiniteWithChange {
            refreshReadout()
        }
        startAnimation()
    }

    private func refreshReadout() {
        readout.text = "Activations: \(activations)"
        readout.accessibilityLabel = readout.text
    }

    private func startAnimation() {
        switch mode {
        case .completing:
            UIView.animate(withDuration: 0.15) {
                self.swatch.alpha = 0.4
            } completion: { _ in
                UIView.animate(withDuration: 0.15) {
                    self.swatch.alpha = 1
                }
            }
        case .indefinite, .indefiniteWithChange:
            UIView.animate(
                withDuration: 0.4,
                delay: 0,
                options: [.repeat, .autoreverse, .allowUserInteraction]
            ) {
                self.swatch.alpha = 0.2
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettlementCasesDemo()
    }
}

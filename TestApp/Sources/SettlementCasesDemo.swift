import SwiftUI
import UIKit

/// Fixtures for the settle rule: settlement is a statement about the
/// accessibility tree, decided by comparing trees.
///
/// Every control here animates except the first, and every one settles at the
/// same speed, whichever animation API it reached for and whether or not the
/// animation ever ends. Motion the accessibility tree cannot describe is not
/// the agent's business. The runtime used to count running animations and
/// withhold settlement on the count, which made a keyboard sliding into place
/// over an already-quiet tree indistinguishable from a spinner that never
/// stops, and turned successful actions into timeouts.
///
/// `TwoStateWorkButton` is the case settlement does owe an answer to: work the
/// tree *does* describe, which must be waited out. A change that makes the
/// animating controls slow to settle, or the two-state control settle early,
/// is a regression in the rule rather than in these fixtures.
struct SettlementCasesDemo: View {

    var body: some View {
        List {
            Section("No animation, no change") {
                InertButton()
            }
            Section("Animation completes, no change") {
                CompletingAnimationButton()
            }
            Section("Animation outlasts the action, no change") {
                IndefiniteAnimationButton()
            }
            Section("Animation outlasts the action, tree changes") {
                IndefiniteAnimationWithChangeButton()
            }
            Section("Same via CAAnimation — same verdict, other API") {
                BoundedLayerAnimationButton()
            }
            Section("Two-state work — settlement must wait it out") {
                TwoStateWorkButton()
            }
        }
        .navigationTitle("Settlement Cases")
    }
}

// MARK: - Inert

/// Activating this does nothing observable at all.
private struct InertButton: View {
    var body: some View {
        Button("Inert Control") {}
            .accessibilityHint("Produces no animation and no accessibility change")
    }
}

// MARK: - Animation That Ends

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

// MARK: - Animation That Does Not End

/// A repeating `UIView` animation with no end and no accessibility change.
/// Settles as fast as the inert control: nothing observable happened.
private struct IndefiniteAnimationButton: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView {
        let container = PulseOnTapView(mode: .indefinite)
        container.accessibilityLabel = "Endlessly Animating Control"
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Animation With A Change

/// The same endless animation, but the activation also mutates the
/// accessibility tree. The change is what settlement waits on; the animation
/// is incidental to it.
private struct IndefiniteAnimationWithChangeButton: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView {
        let container = PulseOnTapView(mode: .indefiniteWithChange)
        container.accessibilityLabel = "Endlessly Animating Control With Change"
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Two-State Work

/// A control that alternates between two accessibility states: "Ready" at rest,
/// "Loading" while working, then "Ready" again.
///
/// Settlement must not return while this reads "Loading" — a control that is
/// mid-work is not settled, and a stream of changes must publish the
/// intermediate state rather than skipping to the end.
///
/// The loading phase is held far longer than the settle cycle count needs
/// (3 × 100ms), so the intermediate state is guaranteed observable across
/// several ticks rather than merely probable. That determinism is the whole
/// reason this control exists.
private struct TwoStateWorkButton: View {

    private static let loadingHold = Duration.milliseconds(800)

    @State private var isWorking = false
    @State private var workTask: Task<Void, Never>?

    var body: some View {
        Button {
            workTask?.cancel()
            workTask = Task {
                isWorking = true
                try? await Task.sleep(for: Self.loadingHold)
                guard !Task.isCancelled else { return }
                isWorking = false
            }
        } label: {
            Text(isWorking ? "Loading" : "Ready")
        }
        .accessibilityLabel(isWorking ? "Loading" : "Ready")
        .accessibilityHint("Holds a loading state across several settle cycles, then returns to ready")
        .onDisappear {
            workTask?.cancel()
            workTask = nil
        }
    }
}

// MARK: - The Same, Via CAAnimation

/// The same shape written with the other animation API: a long
/// `CABasicAnimation` on a layer, no accessibility change.
///
/// Settlement never asks which API the app reached for, so this and
/// "Endlessly Animating Control" must settle identically. A divergence between
/// them means something has started reading the animation APIs again.
private struct BoundedLayerAnimationButton: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView {
        let container = LayerPulseOnTapView()
        container.accessibilityLabel = "Layer Animating Control"
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// A tappable control whose activation adds a bounded `CAAnimation` straight to
/// a layer, bypassing `UIView.animate` entirely.
private final class LayerPulseOnTapView: UIControl {

    private let swatch = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Starts a bounded CAAnimation with no accessibility change"

        swatch.backgroundColor = .systemTeal
        swatch.layer.cornerRadius = 6
        swatch.isAccessibilityElement = false
        swatch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatch)

        NSLayoutConstraint.activate([
            swatch.leadingAnchor.constraint(equalTo: leadingAnchor),
            swatch.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatch.widthAnchor.constraint(equalToConstant: 44),
            swatch.heightAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(equalToConstant: 60),
        ])

        addTarget(self, action: #selector(activate), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { return nil }

    @objc private func activate() {
        // Bounded: a finite duration and no repetition. Long enough to outlast
        // the action budget, so it is still running when the tree goes quiet.
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0.2
        animation.duration = 30
        animation.autoreverses = true
        animation.isRemovedOnCompletion = true
        swatch.layer.add(animation, forKey: "boundedPulse")
    }
}

// MARK: - Shared Control

/// A tappable control whose activation starts a `UIView` animation.
///
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

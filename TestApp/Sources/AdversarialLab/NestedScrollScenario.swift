import SwiftUI
import UIKit

internal struct NestedScrollScenarioView: UIViewControllerRepresentable {
    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIViewController {
        NestedScrollViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// UIScrollView that publishes real offset attempts and movements as accessibility evidence.
internal final class AdversarialScrollEvidenceView: UIScrollView {
    // MARK: - Properties

    internal weak var attemptEvidenceLabel: UILabel?
    internal weak var movementEvidenceLabel: UILabel?
    internal weak var visibilityEvidenceLabel: UILabel?
    internal weak var observedTarget: UIView?
    internal var onEvidenceChange: (@MainActor (AdversarialScrollEvidenceView) -> Void)?
    internal private(set) var offsetAttemptCount = 0
    internal private(set) var offsetMovementCount = 0
    private var isTrackingEvidence = false

    override var contentOffset: CGPoint {
        didSet { publishEvidence() }
    }

    // MARK: - Offset Evidence

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        let previousOffset = self.contentOffset
        if isTrackingEvidence {
            offsetAttemptCount += 1
        }
        super.setContentOffset(contentOffset, animated: animated)
        if isTrackingEvidence, self.contentOffset != previousOffset {
            offsetMovementCount += 1
        }
        publishEvidence()
    }

    internal func beginEvidenceTracking() {
        guard !isTrackingEvidence else { return }
        resetEvidence()
        isTrackingEvidence = true
    }

    internal func resetEvidence() {
        offsetAttemptCount = 0
        offsetMovementCount = 0
        publishEvidence()
    }

    internal func publishEvidence() {
        attemptEvidenceLabel?.accessibilityValue = String(offsetAttemptCount)
        movementEvidenceLabel?.accessibilityValue = String(offsetMovementCount)
        if let visibilityEvidenceLabel, let observedTarget {
            visibilityEvidenceLabel.accessibilityValue = bounds.intersects(observedTarget.frame)
                ? "Visible"
                : "Offscreen"
        }
        onEvidenceChange?(self)
    }
}

private final class NestedScrollViewController: UIViewController {
    // MARK: - Properties

    private let evidenceStack = UIStackView()
    private let outerScrollView = AdversarialScrollEvidenceView()
    private let innerScrollView = AdversarialScrollEvidenceView()
    private let outerAttemptLabel = UILabel()
    private let outerMovementLabel = UILabel()
    private let innerAttemptLabel = UILabel()
    private let innerMovementLabel = UILabel()
    private let activationCountLabel = UILabel()
    private let selectedLabel = UILabel()
    private let deepCutsLabel = UILabel()
    private let targetButton = UIButton(type: .system)
    private var targetRevealOffset: CGFloat = 1
    private var activationCount = 0

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Nested Scroll"
        view.backgroundColor = .systemGroupedBackground

        configureEvidenceLabel(outerAttemptLabel, title: "Nested outer scroll attempts")
        configureEvidenceLabel(outerMovementLabel, title: "Nested outer scroll movements")
        configureEvidenceLabel(innerAttemptLabel, title: "Nested inner scroll attempts")
        configureEvidenceLabel(innerMovementLabel, title: "Nested inner scroll movements")
        configureEvidenceLabel(activationCountLabel, title: "Nested target activations")
        selectedLabel.text = "No nested selection"

        evidenceStack.axis = .vertical
        evidenceStack.spacing = 4
        evidenceStack.translatesAutoresizingMaskIntoConstraints = false
        let heading = UILabel()
        heading.text = "Nested Scroll"
        heading.accessibilityTraits.insert(.header)
        [
            heading,
            outerAttemptLabel,
            outerMovementLabel,
            innerAttemptLabel,
            innerMovementLabel,
            activationCountLabel,
            selectedLabel,
        ]
            .forEach(evidenceStack.addArrangedSubview)
        view.addSubview(evidenceStack)

        outerScrollView.contentInsetAdjustmentBehavior = .never
        outerScrollView.translatesAutoresizingMaskIntoConstraints = false
        outerScrollView.attemptEvidenceLabel = outerAttemptLabel
        outerScrollView.movementEvidenceLabel = outerMovementLabel
        view.addSubview(outerScrollView)

        deepCutsLabel.text = "Deep Cuts"
        deepCutsLabel.accessibilityTraits.insert(.header)
        outerScrollView.addSubview(deepCutsLabel)

        innerScrollView.contentInsetAdjustmentBehavior = .never
        innerScrollView.attemptEvidenceLabel = innerAttemptLabel
        innerScrollView.movementEvidenceLabel = innerMovementLabel
        innerScrollView.onEvidenceChange = { [weak self] scrollView in
            guard let self else { return }
            self.targetButton.isAccessibilityElement = scrollView.contentOffset.x >= self.targetRevealOffset
        }
        outerScrollView.addSubview(innerScrollView)

        let nearButton = UIButton(type: .system)
        nearButton.setTitle("Almost There", for: .normal)
        nearButton.frame = CGRect(x: 20, y: 32, width: 180, height: 96)
        innerScrollView.addSubview(nearButton)

        targetButton.setTitle("Verified by The Vibe Check", for: .normal)
        targetButton.accessibilityValue = "The Vibe Check"
        targetButton.isAccessibilityElement = false
        targetButton.addTarget(self, action: #selector(activateTarget), for: .touchUpInside)
        innerScrollView.addSubview(targetButton)

        NSLayoutConstraint.activate([
            evidenceStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            evidenceStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            evidenceStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            outerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outerScrollView.topAnchor.constraint(equalTo: evidenceStack.bottomAnchor, constant: 12),
            outerScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let outerContentHeight = max(900, outerScrollView.bounds.height + 500)
        outerScrollView.contentSize = CGSize(width: outerScrollView.bounds.width, height: outerContentHeight)
        deepCutsLabel.frame = CGRect(
            x: 20,
            y: outerContentHeight - 240,
            width: 260,
            height: 30
        )
        innerScrollView.frame = CGRect(
            x: 0,
            y: outerContentHeight - 200,
            width: outerScrollView.bounds.width,
            height: 160
        )
        let innerContentWidth = max(900, innerScrollView.bounds.width + 520)
        innerScrollView.contentSize = CGSize(width: innerContentWidth, height: innerScrollView.bounds.height)
        targetButton.frame = CGRect(x: innerContentWidth - 240, y: 32, width: 220, height: 96)
        targetRevealOffset = max(1, targetButton.frame.minX - innerScrollView.bounds.width + 40)
        outerScrollView.publishEvidence()
        innerScrollView.publishEvidence()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        outerScrollView.beginEvidenceTracking()
        innerScrollView.beginEvidenceTracking()
    }

    // MARK: - Target Action

    @objc private func activateTarget() {
        activationCount += 1
        activationCountLabel.accessibilityValue = String(activationCount)
        selectedLabel.text = "Selected Verified"
    }

    // MARK: - Evidence

    private func configureEvidenceLabel(_ label: UILabel, title: String) {
        label.text = title
        label.accessibilityLabel = title
        label.accessibilityValue = "0"
    }
}

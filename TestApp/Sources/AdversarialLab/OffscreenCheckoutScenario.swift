import SwiftUI
import UIKit

internal struct OffscreenCheckoutScenarioView: UIViewControllerRepresentable {
    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIViewController {
        OffscreenCheckoutViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class OffscreenCheckoutViewController: UIViewController {
    // MARK: - Properties

    private let evidenceStack = UIStackView()
    private let scrollView = AdversarialScrollEvidenceView()
    private let scrollAttemptLabel = UILabel()
    private let scrollMovementLabel = UILabel()
    private let targetVisibilityLabel = UILabel()
    private let activationCountLabel = UILabel()
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let placeOrderButton = UIButton(type: .system)
    private let unavailableOrderButton = UIButton(type: .system)
    private var activationCount = 0

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Offscreen Checkout"
        view.backgroundColor = .systemGroupedBackground

        configureEvidenceLabel(scrollAttemptLabel, title: "Checkout scroll attempts")
        configureEvidenceLabel(scrollMovementLabel, title: "Checkout scroll movements")
        configureEvidenceLabel(targetVisibilityLabel, title: "Checkout target visibility", value: "Offscreen")
        configureEvidenceLabel(activationCountLabel, title: "Checkout activations")

        evidenceStack.axis = .vertical
        evidenceStack.spacing = 4
        evidenceStack.translatesAutoresizingMaskIntoConstraints = false
        let heading = UILabel()
        heading.text = "Offscreen Checkout"
        heading.accessibilityTraits.insert(.header)
        [
            heading,
            scrollAttemptLabel,
            scrollMovementLabel,
            targetVisibilityLabel,
            activationCountLabel,
        ]
            .forEach(evidenceStack.addArrangedSubview)
        view.addSubview(evidenceStack)

        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.attemptEvidenceLabel = scrollAttemptLabel
        scrollView.movementEvidenceLabel = scrollMovementLabel
        scrollView.visibilityEvidenceLabel = targetVisibilityLabel
        scrollView.observedTarget = placeOrderButton
        view.addSubview(scrollView)

        statusLabel.text = "Cart ready"
        scrollView.addSubview(statusLabel)

        detailLabel.text = "Checkout details"
        detailLabel.accessibilityTraits.insert(.header)
        scrollView.addSubview(detailLabel)

        placeOrderButton.setTitle("Place order", for: .normal)
        placeOrderButton.addTarget(self, action: #selector(placeOrder), for: .touchUpInside)
        scrollView.addSubview(placeOrderButton)

        unavailableOrderButton.setTitle("Unavailable order", for: .normal)
        unavailableOrderButton.isEnabled = false
        scrollView.addSubview(unavailableOrderButton)

        NSLayoutConstraint.activate([
            evidenceStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            evidenceStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            evidenceStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: evidenceStack.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let contentHeight = max(900, scrollView.bounds.height + 480)
        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: contentHeight)
        statusLabel.frame = CGRect(x: 20, y: 20, width: 260, height: 30)
        detailLabel.frame = CGRect(
            x: 20,
            y: 150,
            width: 260,
            height: 30
        )
        placeOrderButton.frame = CGRect(x: 20, y: contentHeight - 124, width: 220, height: 44)
        unavailableOrderButton.frame = CGRect(x: 20, y: contentHeight - 70, width: 220, height: 44)
        scrollView.publishEvidence()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollView.beginEvidenceTracking()
    }

    // MARK: - Checkout Actions

    @objc private func placeOrder() {
        activationCount += 1
        activationCountLabel.accessibilityValue = String(activationCount)
        statusLabel.text = "Order placed"
    }

    // MARK: - Evidence

    private func configureEvidenceLabel(_ label: UILabel, title: String, value: String = "0") {
        label.text = title
        label.accessibilityLabel = title
        label.accessibilityValue = value
    }
}

import SwiftUI
import UIKit

internal struct ModalObstructionScenarioView: UIViewControllerRepresentable {
    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIViewController {
        ModalObstructionViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class ModalObstructionViewController: UIViewController {
    // MARK: - Properties

    private let rootStack = UIStackView()
    private let scrollView = AdversarialScrollEvidenceView()
    private let statusLabel = UILabel()
    private let archiveCountLabel = UILabel()
    private let actionCountLabel = UILabel()
    private let scrollAttemptLabel = UILabel()
    private let scrollMovementLabel = UILabel()
    private let archiveButton = UIButton(type: .system)
    private var sheetStatusLabel: UILabel?
    private var sheetArchiveCountLabel: UILabel?
    private var sheetActionCountLabel: UILabel?
    private var sheetScrollAttemptLabel: UILabel?
    private var sheetScrollMovementLabel: UILabel?
    private var archiveCount = 0
    private var actionCount = 0

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Modal Obstruction"
        view.backgroundColor = .systemGroupedBackground

        rootStack.axis = .vertical
        rootStack.spacing = 4
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        let heading = UILabel()
        heading.text = "Modal Obstruction"
        heading.accessibilityTraits.insert(.header)
        rootStack.addArrangedSubview(heading)

        let reviewButton = UIButton(type: .system)
        reviewButton.setTitle("Review order", for: .normal)
        reviewButton.addTarget(self, action: #selector(presentReview), for: .touchUpInside)
        rootStack.addArrangedSubview(reviewButton)

        statusLabel.text = "Status: None"
        rootStack.addArrangedSubview(statusLabel)

        configureEvidenceLabel(archiveCountLabel, title: "Archived orders")
        configureEvidenceLabel(actionCountLabel, title: "Background archive actions")
        configureEvidenceLabel(scrollAttemptLabel, title: "Background scroll attempts")
        configureEvidenceLabel(scrollMovementLabel, title: "Background scroll movements")
        [archiveCountLabel, actionCountLabel, scrollAttemptLabel, scrollMovementLabel]
            .forEach(rootStack.addArrangedSubview)

        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.onEvidenceChange = { [weak self] _ in self?.refreshEvidence() }
        view.addSubview(scrollView)

        let ordersLabel = UILabel()
        ordersLabel.text = "Orders"
        ordersLabel.accessibilityTraits.insert(.header)
        ordersLabel.frame = CGRect(x: 20, y: 20, width: 260, height: 30)
        scrollView.addSubview(ordersLabel)

        archiveButton.setTitle("Archive order 3", for: .normal)
        archiveButton.addTarget(self, action: #selector(archiveOrder), for: .touchUpInside)
        scrollView.addSubview(archiveButton)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootStack.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let contentHeight = max(860, scrollView.bounds.height + 440)
        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: contentHeight)
        archiveButton.frame = CGRect(x: 20, y: contentHeight - 70, width: 240, height: 44)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollView.beginEvidenceTracking()
        refreshEvidence()
    }

    // MARK: - Review Presentation

    @objc private func presentReview() {
        guard presentedViewController == nil else { return }
        scrollView.resetEvidence()
        let review = UIViewController()
        review.view.backgroundColor = .systemGroupedBackground
        review.modalPresentationStyle = .pageSheet
        review.isModalInPresentation = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        review.view.addSubview(stack)

        let heading = UILabel()
        heading.text = "Order review"
        heading.font = .preferredFont(forTextStyle: .title2)
        heading.accessibilityTraits.insert(.header)
        stack.addArrangedSubview(heading)

        let reviewStatus = UILabel()
        reviewStatus.text = statusLabel.text
        sheetStatusLabel = reviewStatus
        stack.addArrangedSubview(reviewStatus)

        let archiveEvidence = UILabel()
        let actionEvidence = UILabel()
        let scrollAttemptEvidence = UILabel()
        let scrollMovementEvidence = UILabel()
        configureEvidenceLabel(archiveEvidence, title: "Archived orders")
        configureEvidenceLabel(actionEvidence, title: "Background archive actions")
        configureEvidenceLabel(scrollAttemptEvidence, title: "Background scroll attempts")
        configureEvidenceLabel(scrollMovementEvidence, title: "Background scroll movements")
        sheetArchiveCountLabel = archiveEvidence
        sheetActionCountLabel = actionEvidence
        sheetScrollAttemptLabel = scrollAttemptEvidence
        sheetScrollMovementLabel = scrollMovementEvidence
        [archiveEvidence, actionEvidence, scrollAttemptEvidence, scrollMovementEvidence]
            .forEach(stack.addArrangedSubview)

        let confirmButton = UIButton(type: .system)
        confirmButton.setTitle("Confirm review", for: .normal)
        confirmButton.addTarget(self, action: #selector(confirmReview), for: .touchUpInside)
        stack.addArrangedSubview(confirmButton)

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.addTarget(self, action: #selector(closeReview), for: .touchUpInside)
        stack.addArrangedSubview(closeButton)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: review.view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: review.view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: review.view.safeAreaLayoutGuide.topAnchor, constant: 28),
        ])

        refreshEvidence()
        present(review, animated: true)
    }

    @objc private func confirmReview() {
        statusLabel.text = "Status: Review confirmed"
        sheetStatusLabel?.text = statusLabel.text
    }

    @objc private func closeReview() {
        dismiss(animated: true) { [weak self] in
            self?.sheetStatusLabel = nil
            self?.sheetArchiveCountLabel = nil
            self?.sheetActionCountLabel = nil
            self?.sheetScrollAttemptLabel = nil
            self?.sheetScrollMovementLabel = nil
        }
    }

    // MARK: - Background Actions

    @objc private func archiveOrder() {
        actionCount += 1
        archiveCount += 1
        statusLabel.text = "Status: Archived order 3"
        refreshEvidence()
    }

    // MARK: - Evidence

    private func refreshEvidence() {
        archiveCountLabel.accessibilityValue = String(archiveCount)
        actionCountLabel.accessibilityValue = String(actionCount)
        scrollAttemptLabel.accessibilityValue = String(scrollView.offsetAttemptCount)
        scrollMovementLabel.accessibilityValue = String(scrollView.offsetMovementCount)
        sheetArchiveCountLabel?.accessibilityValue = String(archiveCount)
        sheetActionCountLabel?.accessibilityValue = String(actionCount)
        sheetScrollAttemptLabel?.accessibilityValue = String(scrollView.offsetAttemptCount)
        sheetScrollMovementLabel?.accessibilityValue = String(scrollView.offsetMovementCount)
    }

    private func configureEvidenceLabel(_ label: UILabel, title: String) {
        label.text = title
        label.accessibilityLabel = title
        label.accessibilityValue = "0"
    }
}

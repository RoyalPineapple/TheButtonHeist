import Accessibility
import SwiftUI
import UIKit

internal struct DuplicateLabelsScenarioView: UIViewControllerRepresentable {
    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIViewController {
        DuplicateLabelsViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class DuplicateReviewButton: UIButton, AXCustomContentProvider {
    var accessibilityCustomContent: [AXCustomContent] = []
}

private final class DuplicateLabelsViewController: UIViewController {
    private enum RowID: Hashable {
        case workHigh
        case workLow
        case homeHigh
    }

    private struct Row {
        let id: RowID
        let category: String
        let priority: String
        let notes: String

        var activationEvidenceLabel: String {
            "\(category) \(priority) activations"
        }
    }

    // MARK: - Properties

    private let rows = [
        Row(
            id: .workHigh,
            category: "Work",
            priority: "High",
            notes: "Blocking release"
        ),
        Row(
            id: .workLow,
            category: "Work",
            priority: "Low",
            notes: "Nice to have"
        ),
        Row(
            id: .homeHigh,
            category: "Home",
            priority: "High",
            notes: "Personal admin"
        ),
    ]
    private let evidenceStack = UIStackView()
    private let scrollView = AdversarialScrollEvidenceView()
    private let targetVisibilityLabel = UILabel()
    private let candidateOrderLabel = UILabel()
    private let returnToTopButton = UIButton(type: .system)
    private var activationCounts: [RowID: Int] = [:]
    private var activationLabels: [RowID: UILabel] = [:]
    private var rowButtons: [RowID: DuplicateReviewButton] = [:]
    private var didReorderRows = false

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Duplicate Labels"
        view.backgroundColor = .systemGroupedBackground

        configureEvidenceLabel(
            targetVisibilityLabel,
            title: "Duplicate target visibility",
            value: "Offscreen"
        )
        configureEvidenceLabel(
            candidateOrderLabel,
            title: "Duplicate candidate order",
            value: "Initial"
        )
        rows.forEach { row in
            let label = UILabel()
            configureEvidenceLabel(label, title: row.activationEvidenceLabel)
            activationLabels[row.id] = label
            activationCounts[row.id] = 0
        }
        configureEvidenceStack()
        configureScrollView()
        configureRows()

        NSLayoutConstraint.activate([
            evidenceStack.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 20
            ),
            evidenceStack.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -20
            ),
            evidenceStack.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 12
            ),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: evidenceStack.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let contentHeight = max(1_200, scrollView.bounds.height + 680)
        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: contentHeight)
        returnToTopButton.frame = CGRect(x: 20, y: 20, width: 260, height: 44)
        rowButtons[.workHigh]?.frame = CGRect(x: 20, y: 150, width: 280, height: 64)
        rowButtons[.workLow]?.frame = CGRect(x: 20, y: 420, width: 280, height: 64)
        rowButtons[.homeHigh]?.frame = CGRect(
            x: 20,
            y: contentHeight - 100,
            width: 280,
            height: 64
        )
        scrollView.publishEvidence()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollView.beginEvidenceTracking()
    }

    // MARK: - Configuration

    private func configureEvidenceStack() {
        evidenceStack.axis = .vertical
        evidenceStack.spacing = 4
        evidenceStack.translatesAutoresizingMaskIntoConstraints = false
        let heading = UILabel()
        heading.text = "Duplicate Labels"
        heading.accessibilityTraits.insert(.header)
        evidenceStack.addArrangedSubview(heading)
        evidenceStack.addArrangedSubview(targetVisibilityLabel)
        evidenceStack.addArrangedSubview(candidateOrderLabel)
        rows.compactMap { activationLabels[$0.id] }
            .forEach(evidenceStack.addArrangedSubview)
        view.addSubview(evidenceStack)
    }

    private func configureScrollView() {
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.visibilityEvidenceLabel = targetVisibilityLabel
        scrollView.onEvidenceChange = { [weak self] scrollView in
            self?.reorderCandidatesIfNeeded(in: scrollView)
        }
        view.addSubview(scrollView)

        returnToTopButton.setTitle("Return to duplicate top", for: .normal)
        returnToTopButton.addTarget(self, action: #selector(returnToTop), for: .touchUpInside)
        scrollView.addSubview(returnToTopButton)
    }

    private func configureRows() {
        for row in rows {
            let button = DuplicateReviewButton(type: .system)
            button.setTitle("Review PR", for: .normal)
            button.accessibilityLabel = "Review PR"
            button.accessibilityCustomContent = customContent(for: row)
            button.addAction(UIAction { [weak self] _ in
                self?.recordActivation(for: row.id)
            }, for: .touchUpInside)
            rowButtons[row.id] = button
            scrollView.addSubview(button)
        }
        scrollView.observedTarget = rowButtons[.homeHigh]
    }

    private func configureEvidenceLabel(_ label: UILabel, title: String, value: String = "0") {
        label.text = title
        label.accessibilityLabel = title
        label.accessibilityValue = value
    }

    private func customContent(for row: Row) -> [AXCustomContent] {
        let category = AXCustomContent(label: "Category", value: row.category)
        category.importance = .high
        let priority = AXCustomContent(label: "Priority", value: row.priority)
        priority.importance = .high
        let notes = AXCustomContent(label: "Notes", value: row.notes)
        return [category, priority, notes]
    }

    // MARK: - Actions

    private func recordActivation(for rowID: RowID) {
        let count = (activationCounts[rowID] ?? 0) + 1
        activationCounts[rowID] = count
        activationLabels[rowID]?.accessibilityValue = String(count)
    }

    @objc private func returnToTop() {
        scrollView.setContentOffset(.zero, animated: false)
    }

    // MARK: - Candidate Order

    private func reorderCandidatesIfNeeded(in scrollView: AdversarialScrollEvidenceView) {
        guard !didReorderRows,
              let target = rowButtons[.homeHigh],
              scrollView.bounds.intersects(target.frame),
              let sibling = rowButtons[.workHigh]
        else { return }
        scrollView.bringSubviewToFront(sibling)
        didReorderRows = true
        candidateOrderLabel.accessibilityValue = "Reordered"
    }
}

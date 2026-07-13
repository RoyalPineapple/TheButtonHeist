import SwiftUI
import UIKit

internal struct StaleLiveObjectScenarioView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        StaleLiveObjectViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class StaleLiveObjectViewController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let resultLabel = UILabel()
    private var targetButton: ReplacingOnAccessibilityReadButton?
    private var duplicateButton: UIButton?
    private var actionCounts: [Int: Int] = [:]
    private var generation = 1
    private var showsDuplicate = false
    private var replacementArmed = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stale Live Object"
        view.backgroundColor = .systemGroupedBackground

        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let headingLabel = UILabel()
        headingLabel.text = "Stale Live Object"
        headingLabel.font = .preferredFont(forTextStyle: .title2)
        headingLabel.accessibilityTraits.insert(.header)
        stack.addArrangedSubview(headingLabel)

        let duplicateButton = UIButton(type: .system)
        duplicateButton.setTitle("Show Duplicate Target", for: .normal)
        duplicateButton.addTarget(self, action: #selector(showDuplicateTarget), for: .touchUpInside)
        stack.addArrangedSubview(duplicateButton)

        resultLabel.text = "Result: waiting"
        stack.addArrangedSubview(resultLabel)

        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: 900).isActive = true
        stack.addArrangedSubview(spacer)

        installTargetButton()

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    private func installTargetButton() {
        let insertionIndex = targetButton.flatMap { stack.arrangedSubviews.firstIndex(of: $0) }
            ?? stack.arrangedSubviews.count
        if let targetButton {
            stack.removeArrangedSubview(targetButton)
            targetButton.removeFromSuperview()
        }
        let currentGeneration = generation
        let button = ReplacingOnAccessibilityReadButton(type: .system)
        button.setTitle("Submit Order", for: .normal)
        button.onAccessibilityValueRead = { [weak self] in
            self?.replaceTargetDuringAccessibilityRead()
        }
        button.addAction(UIAction { [weak self] _ in
            self?.recordAction(generation: currentGeneration)
        }, for: .touchUpInside)
        targetButton = button
        stack.insertArrangedSubview(button, at: insertionIndex)
        refreshAccessibilityValues()
    }

    private func replaceTargetDuringAccessibilityRead() {
        guard replacementArmed, generation == 1 else { return }
        generation = 2
        installTargetButton()
    }

    @objc private func showDuplicateTarget() {
        guard !showsDuplicate else { return }
        showsDuplicate = true
        let button = UIButton(type: .system)
        button.setTitle("Submit Order", for: .normal)
        button.addAction(UIAction { [weak self] _ in
            self?.recordAction(generation: 3)
        }, for: .touchUpInside)
        duplicateButton = button
        let targetIndex = targetButton.flatMap { stack.arrangedSubviews.firstIndex(of: $0) }
            ?? stack.arrangedSubviews.count
        stack.insertArrangedSubview(button, at: targetIndex + 1)
        refreshAccessibilityValues()
        view.layoutIfNeeded()
        scrollView.setContentOffset(
            CGPoint(x: 0, y: max(0, scrollView.contentSize.height - scrollView.bounds.height)),
            animated: false
        )
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y > 100 {
            replacementArmed = true
        }
    }

    private func recordAction(generation: Int) {
        actionCounts[generation, default: 0] += 1
        resultLabel.text = "Result: submitted generation \(generation)"
        refreshAccessibilityValues()
    }

    private func refreshAccessibilityValues() {
        if let targetButton {
            targetButton.accessibilityValue = targetValue(generation: generation)
        }
        duplicateButton?.accessibilityValue = targetValue(generation: 3)
    }

    private func targetValue(generation: Int) -> String {
        "Generation \(generation), actions \(actionCounts[generation, default: 0]), "
            + "generation 1 actions \(actionCounts[1, default: 0])"
    }
}

private final class ReplacingOnAccessibilityReadButton: UIButton {
    var onAccessibilityValueRead: (@MainActor () -> Void)?

    override var accessibilityValue: String? {
        get {
            onAccessibilityValueRead?()
            return super.accessibilityValue
        }
        set {
            super.accessibilityValue = newValue
        }
    }
}

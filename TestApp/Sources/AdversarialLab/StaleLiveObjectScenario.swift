import SwiftUI
import UIKit

internal struct StaleLiveObjectScenarioView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        StaleLiveObjectViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class StaleLiveObjectViewController: UIViewController {
    private let stack = UIStackView()
    private let resultLabel = UILabel()
    private var targetButton: UIButton?
    private var generation = 1
    private var showsDuplicate = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stale Live Object"
        view.backgroundColor = .systemGroupedBackground

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let headingLabel = UILabel()
        headingLabel.text = "Stale Live Object"
        headingLabel.font = .preferredFont(forTextStyle: .title2)
        headingLabel.accessibilityTraits.insert(.header)
        stack.addArrangedSubview(headingLabel)

        let replaceButton = UIButton(type: .system)
        replaceButton.setTitle("Replace Target", for: .normal)
        replaceButton.addTarget(self, action: #selector(replaceTarget), for: .touchUpInside)
        stack.addArrangedSubview(replaceButton)

        let duplicateButton = UIButton(type: .system)
        duplicateButton.setTitle("Show Duplicate Target", for: .normal)
        duplicateButton.addTarget(self, action: #selector(showDuplicateTarget), for: .touchUpInside)
        stack.addArrangedSubview(duplicateButton)

        resultLabel.text = "Result: waiting"
        stack.addArrangedSubview(resultLabel)

        installTargetButton()

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])
    }

    private func installTargetButton() {
        targetButton?.removeFromSuperview()
        let currentGeneration = generation
        let button = UIButton(type: .system)
        button.setTitle("Submit Order", for: .normal)
        button.accessibilityValue = "version \(currentGeneration)"
        button.addAction(UIAction { [weak self] _ in
            self?.resultLabel.text = "Result: submitted version \(currentGeneration)"
        }, for: .touchUpInside)
        targetButton = button
        stack.insertArrangedSubview(button, at: 3)
    }

    @objc private func replaceTarget() {
        generation = 2
        resultLabel.text = "Result: waiting"
        installTargetButton()
    }

    @objc private func showDuplicateTarget() {
        guard !showsDuplicate else { return }
        showsDuplicate = true
        let button = UIButton(type: .system)
        button.setTitle("Submit Order", for: .normal)
        button.accessibilityValue = "version duplicate"
        button.addAction(UIAction { [weak self] _ in
            self?.resultLabel.text = "Result: duplicate submitted"
        }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }
}

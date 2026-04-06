import SwiftUI
import UIKit

/// SwiftUI wrapper that embeds the pure UIKit obscuring harness.
/// The harness must be UIKit-native so the accessibility snapshot parser
/// walks the full view hierarchy and finds scroll containers behind
/// the presented modal — matching the real-world Square Register scenario.
struct PresentationObscuringHarnessView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ObscuringHarnessViewController {
        ObscuringHarnessViewController()
    }

    func updateUIViewController(_ uiViewController: ObscuringHarnessViewController, context: Context) {}
}

// MARK: - UIKit Harness

/// Pure UIKit view controller with 3 horizontal UIScrollViews (each containing
/// 100 items) and a "Present Modal" button. The modal uses UIKit
/// `.present(_:animated:)` with `.overCurrentContext` to keep background
/// scroll containers in the accessibility tree while establishing a
/// `presentedViewController` chain that `isObscuredByPresentation` can detect.
///
/// Verification via CLI:
///   1. Navigate to this screen
///   2. `buttonheist get_interface` — note containersExplored and explorationTime
///   3. `buttonheist activate --label "Present Modal"`
///   4. `buttonheist get_interface` — should show containersSkippedObscured > 0
///   5. `buttonheist activate --label "Dismiss Modal"`
///   6. `buttonheist get_interface` — full exploration resumes
final class ObscuringHarnessViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Obscuring Harness"
        view.backgroundColor = .systemGroupedBackground

        let presentButton = UIButton(type: .system)
        presentButton.setTitle("Present Modal", for: .normal)
        presentButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        presentButton.addTarget(self, action: #selector(presentModalTapped), for: .touchUpInside)
        presentButton.accessibilityIdentifier = "obscuringHarness.presentModal"
        presentButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(presentButton)

        NSLayoutConstraint.activate([
            presentButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            presentButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        let outerScroll = UIScrollView()
        outerScroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outerScroll)

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 24
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        outerScroll.addSubview(contentStack)

        NSLayoutConstraint.activate([
            outerScroll.topAnchor.constraint(equalTo: presentButton.bottomAnchor, constant: 8),
            outerScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outerScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: outerScroll.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: outerScroll.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: outerScroll.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: outerScroll.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: outerScroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        let instructions = UILabel()
        instructions.text = "3 scroll containers below. Present a modal to test that exploration skips them."
        instructions.font = .preferredFont(forTextStyle: .caption1)
        instructions.textColor = .secondaryLabel
        instructions.numberOfLines = 0
        instructions.accessibilityIdentifier = "obscuringHarness.instructions"
        contentStack.addArrangedSubview(instructions)

        contentStack.addArrangedSubview(makeScrollSection(title: "Catalog", prefix: "catalog", count: 100))
        contentStack.addArrangedSubview(makeScrollSection(title: "Inventory", prefix: "inventory", count: 100))
        contentStack.addArrangedSubview(makeScrollSection(title: "History", prefix: "history", count: 100))
    }

    // MARK: - Scroll Section Builder

    private func makeScrollSection(title: String, prefix: String, count: Int) -> UIView {
        let container = UIView()

        let header = UILabel()
        header.text = title
        header.font = .preferredFont(forTextStyle: .headline)
        header.accessibilityIdentifier = "obscuringHarness.\(prefix).header"
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        for index in 0..<count {
            let label = UILabel()
            label.text = "\(title) \(index)"
            label.font = .preferredFont(forTextStyle: .body)
            label.textAlignment = .center
            label.backgroundColor = .quaternarySystemFill
            label.layer.cornerRadius = 8
            label.clipsToBounds = true
            label.translatesAutoresizingMaskIntoConstraints = false
            label.accessibilityIdentifier = "obscuringHarness.\(prefix).item\(index)"
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
            label.heightAnchor.constraint(equalToConstant: 40).isActive = true
            stack.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 50),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        return container
    }

    // MARK: - Modal Presentation

    @objc private func presentModalTapped() {
        let modalVC = ModalContentViewController()
        modalVC.modalPresentationStyle = .overCurrentContext
        present(modalVC, animated: true)
    }
}

// MARK: - Modal VC

/// Minimal UIKit view controller presented as a modal.
/// Uses `.overCurrentContext` so the presenting VC's views (including scroll
/// containers) remain in the accessibility tree — matching the Square Register
/// scenario where a receipt sheet sits over a checkout view with scroll containers.
private final class ModalContentViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "Modal Over Scroll Containers"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.accessibilityIdentifier = "obscuringHarness.modal.title"

        let descriptionLabel = UILabel()
        descriptionLabel.text = "The 3 scroll containers behind this modal should be skipped during exploration."
        descriptionLabel.font = .preferredFont(forTextStyle: .body)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textAlignment = .center
        descriptionLabel.accessibilityIdentifier = "obscuringHarness.modal.description"

        let dismissButton = UIButton(type: .system)
        dismissButton.setTitle("Dismiss Modal", for: .normal)
        dismissButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        dismissButton.accessibilityIdentifier = "obscuringHarness.modal.dismiss"

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(descriptionLabel)
        stack.addArrangedSubview(dismissButton)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    @objc private func dismissTapped() {
        dismiss(animated: true)
    }
}

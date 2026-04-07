import SwiftUI
import UIKit

/// SwiftUI wrapper that embeds the pure UIKit obscuring harness.
struct PresentationObscuringHarnessView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ObscuringHarnessViewController {
        ObscuringHarnessViewController()
    }

    func updateUIViewController(_ uiViewController: ObscuringHarnessViewController, context: Context) {}
}

// MARK: - UIKit Harness

/// Pure UIKit view controller with 3 UITableViews (each with 5000 rows using
/// cell recycling) and a "Present Modal" button. Cell recycling forces the
/// exploration engine to scroll through pages to discover off-screen elements —
/// this is what causes the multi-second hang when containers behind a modal
/// are explored unnecessarily.
///
/// Verification via CLI:
///   1. Navigate to this screen
///   2. `buttonheist get_interface` — note scrollCount and explorationTime
///   3. `buttonheist activate --label "Present Modal"`
///   4. `buttonheist get_interface` — with fix: fast (containers skipped); without: slow
///   5. `buttonheist activate --label "Dismiss Modal"`
///   6. `buttonheist get_interface` — full exploration resumes
final class ObscuringHarnessViewController: UIViewController {

    private let sectionPrefixes = ["catalog", "inventory", "history"]
    private let sectionTitles = ["Catalog", "Inventory", "History"]
    private let rowCount = 5000

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

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            presentButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            presentButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            contentStack.topAnchor.constraint(equalTo: presentButton.bottomAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])

        let instructions = UILabel()
        instructions.text = "3 table views with cell recycling (5000 rows each). Present a modal to test that exploration skips them."
        instructions.font = .preferredFont(forTextStyle: .caption1)
        instructions.textColor = .secondaryLabel
        instructions.numberOfLines = 0
        instructions.accessibilityIdentifier = "obscuringHarness.instructions"
        contentStack.addArrangedSubview(instructions)

        for (index, title) in sectionTitles.enumerated() {
            contentStack.addArrangedSubview(
                makeTableSection(title: title, prefix: sectionPrefixes[index], tag: index)
            )
        }
    }

    // MARK: - Table View Section Builder

    private func makeTableSection(title: String, prefix: String, tag: Int) -> UIView {
        let container = UIView()

        let header = UILabel()
        header.text = title
        header.font = .preferredFont(forTextStyle: .headline)
        header.accessibilityIdentifier = "obscuringHarness.\(prefix).header"
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.tag = tag
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tableView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
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

// MARK: - UITableViewDataSource

extension ObscuringHarnessViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rowCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let prefix = sectionPrefixes[tableView.tag]
        let title = sectionTitles[tableView.tag]
        cell.textLabel?.text = "\(title) \(indexPath.row)"
        cell.accessibilityIdentifier = "obscuringHarness.\(prefix).item\(indexPath.row)"
        return cell
    }
}

// MARK: - Modal VC

/// Minimal UIKit view controller presented as a modal.
/// Uses `.overCurrentContext` so the presenting VC's views (including table
/// views) remain in the accessibility tree — matching the Square Register
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
        descriptionLabel.text = "The 3 table views behind this modal should be skipped during exploration."
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

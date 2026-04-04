import UIKit

class FormViewController: UIViewController {

    // MARK: - UI Elements

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let nameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Name"
        textField.borderStyle = .roundedRect
        textField.accessibilityLabel = "Name"
        return textField
    }()

    private let emailTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Email"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .emailAddress
        textField.accessibilityLabel = "Email"
        return textField
    }()

    private let subscribeSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.accessibilityLabel = "Subscribe to newsletter"
        return toggle
    }()

    private let subscribeSwitchLabel: UILabel = {
        let label = UILabel()
        label.text = "Subscribe to newsletter"
        return label
    }()

    private let frequencySegment: UISegmentedControl = {
        let segmentedControl = UISegmentedControl(items: ["Daily", "Weekly", "Monthly"])
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.accessibilityLabel = "Notification frequency"
        return segmentedControl
    }()

    private let frequencyLabel: UILabel = {
        let label = UILabel()
        label.text = "Notification frequency"
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        return label
    }()

    private let submitButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Submit", for: .normal)
        return button
    }()

    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        button.setTitleColor(.systemRed, for: .normal)
        return button
    }()

    private let infoLabel: UILabel = {
        let label = UILabel()
        label.text = "This is a UIKit demo app for testing accessibility inspection."
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        return label
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UIKit Form Demo"
        view.backgroundColor = .systemGroupedBackground
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let personalSection = createSection(title: "Personal Information", views: [
            nameTextField,
            emailTextField
        ])
        contentStack.addArrangedSubview(personalSection)

        let switchStack = UIStackView(arrangedSubviews: [subscribeSwitchLabel, subscribeSwitch])
        switchStack.distribution = .equalSpacing

        let frequencyStack = UIStackView(arrangedSubviews: [frequencyLabel, frequencySegment])
        frequencyStack.axis = .vertical
        frequencyStack.spacing = 8

        let preferencesSection = createSection(title: "Preferences", views: [
            switchStack,
            frequencyStack
        ])
        contentStack.addArrangedSubview(preferencesSection)

        let actionsSection = createSection(title: "Actions", views: [
            submitButton,
            cancelButton
        ])
        contentStack.addArrangedSubview(actionsSection)

        let infoSection = createSection(title: "Information", views: [infoLabel])
        contentStack.addArrangedSubview(infoSection)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])
    }

    private func createSection(title: String, views: [UIView]) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = 10

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            stack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        return container
    }
}

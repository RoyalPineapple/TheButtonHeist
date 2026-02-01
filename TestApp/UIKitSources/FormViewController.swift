import UIKit

class FormViewController: UIViewController {

    // MARK: - UI Elements

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let nameTextField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "Name"
        tf.borderStyle = .roundedRect
        tf.accessibilityIdentifier = "nameField"
        return tf
    }()

    private let emailTextField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "Email"
        tf.borderStyle = .roundedRect
        tf.keyboardType = .emailAddress
        tf.accessibilityIdentifier = "emailField"
        return tf
    }()

    private let subscribeSwitch: UISwitch = {
        let sw = UISwitch()
        sw.accessibilityIdentifier = "subscribeToggle"
        return sw
    }()

    private let subscribeSwitchLabel: UILabel = {
        let label = UILabel()
        label.text = "Subscribe to newsletter"
        return label
    }()

    private let frequencySegment: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Daily", "Weekly", "Monthly"])
        sc.selectedSegmentIndex = 0
        sc.accessibilityIdentifier = "frequencyPicker"
        return sc
    }()

    private let frequencyLabel: UILabel = {
        let label = UILabel()
        label.text = "Notification frequency"
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        return label
    }()

    private let submitButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Submit", for: .normal)
        btn.accessibilityIdentifier = "submitButton"
        return btn
    }()

    private let cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Cancel", for: .normal)
        btn.setTitleColor(.systemRed, for: .normal)
        btn.accessibilityIdentifier = "cancelButton"
        return btn
    }()

    private let infoLabel: UILabel = {
        let label = UILabel()
        label.text = "ℹ️ This is a UIKit demo app for testing accessibility inspection."
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.accessibilityIdentifier = "infoLabel"
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
        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Content stack
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        // Personal info section
        let personalSection = createSection(title: "Personal Information", views: [
            nameTextField,
            emailTextField
        ])
        contentStack.addArrangedSubview(personalSection)

        // Preferences section
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

        // Actions section
        let actionsSection = createSection(title: "Actions", views: [
            submitButton,
            cancelButton
        ])
        contentStack.addArrangedSubview(actionsSection)

        // Info section
        let infoSection = createSection(title: "Information", views: [infoLabel])
        contentStack.addArrangedSubview(infoSection)

        // Constraints
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

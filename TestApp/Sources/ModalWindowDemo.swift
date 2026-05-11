import SwiftUI
import UIKit

/// Demonstrates a modal popup presented in a separate UIWindow — the same
/// pattern used by apps that present action sheets or popups in their own
/// window. The popup sets `accessibilityViewIsModal` on its container,
/// which should cause `get_interface` to return only the popup's elements
/// (not the background catalog list). Screenshots should show the popup
/// composited on top of the dimmed background.
struct ModalWindowDemo: View {
    @State private var lastAction = "None"
    @State private var popupController = ModalPopupController()

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(Self.catalogItems, id: \.self) { item in
                        HStack {
                            Text(item)
                            Spacer()
                            Text("$ \(Int.random(in: 5...99)).00")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Catalog")
                }
            }

            Divider()

            HStack {
                Button("Create Item") {
                    lastAction = "Popup shown"
                    popupController.showPopup { action in
                        lastAction = action
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Text(lastAction)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Last action: \(lastAction)")
            }
            .padding()
        }
        .navigationTitle("Modal Window")
    }

    private static let catalogItems: [String] = [
        "Espresso",
        "Cappuccino",
        "Latte",
        "Cold Brew",
        "Matcha",
        "Chai Tea",
        "Hot Chocolate",
        "Croissant",
        "Muffin",
        "Bagel",
    ]
}

// MARK: - UIWindow-Based Popup

/// Presents a popup in a separate UIWindow with `accessibilityViewIsModal`,
/// replicating how system action sheets and third-party popups work. The
/// modal flag on the popup's container should tell accessibility consumers
/// to ignore all background windows.
@MainActor
final class ModalPopupController {
    private enum Phase {
        case idle
        case presenting(UIWindow, (String) -> Void)
    }

    private var phase: Phase = .idle

    func showPopup(onAction: @escaping (String) -> Void) {
        guard case .idle = phase else { return }

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear

        let viewController = ModalPopupViewController()
        viewController.onAction = { [weak self] action in
            self?.dismiss(action: action)
        }
        window.rootViewController = viewController
        window.isHidden = false

        phase = .presenting(window, onAction)
    }

    private func dismiss(action: String) {
        guard case .presenting(let window, let onAction) = phase else { return }
        window.isHidden = true
        phase = .idle
        onAction(action)
    }
}

// MARK: - Popup View Controller

private final class ModalPopupViewController: UIViewController {
    var onAction: (@MainActor (String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Dimming background
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        // Modal container — this is the key: accessibilityViewIsModal = true
        // tells the accessibility system to ignore everything behind it.
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.layer.cornerRadius = 14
        container.clipsToBounds = true
        container.accessibilityViewIsModal = true
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let actions: [(String, UIColor)] = [
            ("Create item", .label),
            ("Create service", .label),
            ("Create discount", .label),
            ("Dismiss", .secondaryLabel),
        ]

        for (index, (title, color)) in actions.enumerated() {
            var configuration = UIButton.Configuration.plain()
            configuration.title = title
            configuration.baseForegroundColor = color
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24)

            let button = UIButton(configuration: configuration)
            button.tag = index
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)

            if index < actions.count - 1 {
                let separator = UIView()
                separator.backgroundColor = .separator
                separator.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(separator)
                separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
            }
        }

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 300),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        guard let title = sender.configuration?.title else { return }
        onAction?(title)
    }
}

#Preview {
    NavigationStack {
        ModalWindowDemo()
    }
}

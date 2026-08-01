import Accessibility
import SwiftUI
import UIKit

internal struct KeyboardViewportScenarioView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        KeyboardViewportViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class KeyboardViewportTextField: UITextField, AXCustomContentProvider {
    var accessibilityCustomContent: [AXCustomContent] = []
}

private final class KeyboardViewportActionButton: UIButton, AXCustomContentProvider {
    var accessibilityCustomContent: [AXCustomContent] = []
}

private final class KeyboardViewportViewController: UIViewController, UIScrollViewDelegate {
    private enum ReplacementMode: String {
        case unique
        case ambiguous
        case mismatched
    }

    private enum FieldSlot: Hashable {
        case original
        case replacement
        case ambiguousFirst
        case ambiguousSecond
        case mismatched
    }

    private let scrollView = UIScrollView()
    private let headingLabel = UILabel()
    private let modeLabel = UILabel()
    private let originalEditLabel = UILabel()
    private let replacementEditLabel = UILabel()
    private let replacementValueLabel = UILabel()
    private let ambiguousEditLabel = UILabel()
    private let mismatchedEditLabel = UILabel()
    private let postInteractionValueLabel = UILabel()
    private let commitActionLabel = UILabel()
    private let discardActionLabel = UILabel()
    private let prepareAmbiguousButton = UIButton(type: .system)
    private let prepareMismatchedButton = UIButton(type: .system)
    private let commitButton = KeyboardViewportActionButton(type: .system)
    private let discardButton = KeyboardViewportActionButton(type: .system)
    private var replacementMode = ReplacementMode.unique
    private var didReplaceTarget = false
    private var editCounts: [FieldSlot: Int] = [:]
    private var fieldSlots: [ObjectIdentifier: FieldSlot] = [:]
    private var targetFields: [KeyboardViewportTextField] = []
    private var commitActionCount = 0
    private var discardActionCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Keyboard Viewport"
        view.backgroundColor = .systemGroupedBackground

        scrollView.delegate = self
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        configureEvidenceLabels()
        configureHeading()
        configurePreparationButtons()
        configureContinuationButtons()
        installTargetFields()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = scrollView.bounds.width
        let fieldWidth = max(1, width - 40)
        let actionWidth = max(1, width - 40)

        headingLabel.frame = CGRect(x: 20, y: 20, width: fieldWidth, height: 28)
        modeLabel.frame = CGRect(x: 20, y: 60, width: fieldWidth, height: 24)
        prepareAmbiguousButton.frame = CGRect(x: 20, y: 100, width: actionWidth, height: 44)
        prepareMismatchedButton.frame = CGRect(x: 20, y: 156, width: actionWidth, height: 44)

        originalEditLabel.frame = CGRect(x: 20, y: 220, width: fieldWidth, height: 24)
        replacementEditLabel.frame = CGRect(x: 20, y: 248, width: fieldWidth, height: 24)
        replacementValueLabel.frame = CGRect(x: 20, y: 276, width: fieldWidth, height: 24)
        ambiguousEditLabel.frame = CGRect(x: 20, y: 304, width: fieldWidth, height: 24)
        mismatchedEditLabel.frame = CGRect(x: 20, y: 332, width: fieldWidth, height: 24)
        postInteractionValueLabel.frame = CGRect(x: 20, y: 360, width: fieldWidth, height: 24)
        commitActionLabel.frame = CGRect(x: 20, y: 388, width: fieldWidth, height: 24)
        discardActionLabel.frame = CGRect(x: 20, y: 416, width: fieldWidth, height: 24)

        for (index, field) in targetFields.enumerated() {
            field.frame = CGRect(x: 20, y: 940 + CGFloat(index) * 70, width: fieldWidth, height: 44)
        }
        commitButton.frame = CGRect(x: 20, y: 1_130, width: actionWidth, height: 44)
        discardButton.frame = CGRect(x: 20, y: 1_186, width: actionWidth, height: 44)
        scrollView.contentSize = CGSize(width: width, height: 1_270)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !didReplaceTarget, scrollView.contentOffset.y > 120 else { return }
        didReplaceTarget = true
        installTargetFields()
    }

    private func configureEvidenceLabels() {
        let labels: [(UILabel, String)] = [
            (modeLabel, "Viewport replacement mode"),
            (originalEditLabel, "Original viewport edits"),
            (replacementEditLabel, "Replacement viewport edits"),
            (replacementValueLabel, "Replacement viewport value"),
            (ambiguousEditLabel, "Ambiguous viewport edits"),
            (mismatchedEditLabel, "Mismatched viewport edits"),
            (postInteractionValueLabel, "Post interaction viewport value"),
            (commitActionLabel, "Keyboard continuation actions"),
            (discardActionLabel, "Decoy continuation actions"),
        ]
        for (label, title) in labels {
            label.text = title
            label.accessibilityLabel = title
            label.isAccessibilityElement = true
            scrollView.addSubview(label)
        }
        refreshEvidence()
    }

    private func configureHeading() {
        headingLabel.text = "Keyboard Viewport"
        headingLabel.accessibilityTraits.insert(.header)
        scrollView.addSubview(headingLabel)
    }

    private func configurePreparationButtons() {
        prepareAmbiguousButton.setTitle("Prepare ambiguous viewport replacement", for: .normal)
        prepareAmbiguousButton.addTarget(
            self,
            action: #selector(prepareAmbiguousReplacement),
            for: .touchUpInside
        )
        scrollView.addSubview(prepareAmbiguousButton)

        prepareMismatchedButton.setTitle("Prepare mismatched viewport replacement", for: .normal)
        prepareMismatchedButton.addTarget(
            self,
            action: #selector(prepareMismatchedReplacement),
            for: .touchUpInside
        )
        scrollView.addSubview(prepareMismatchedButton)
    }

    private func configureContinuationButtons() {
        configureContinuationButton(commitButton, role: "commit") { [weak self] in
            self?.commitActionCount += 1
            self?.refreshEvidence()
        }
        configureContinuationButton(discardButton, role: "discard") { [weak self] in
            self?.discardActionCount += 1
            self?.refreshEvidence()
        }
    }

    private func configureContinuationButton(
        _ button: KeyboardViewportActionButton,
        role: String,
        action: @escaping () -> Void
    ) {
        button.setTitle("Continue after keyboard", for: .normal)
        button.accessibilityLabel = "Continue after keyboard"
        button.accessibilityCustomContent = [importantCustomContent(label: "Action role", value: role)]
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        scrollView.addSubview(button)
    }

    @objc private func prepareAmbiguousReplacement() {
        replacementMode = .ambiguous
        refreshEvidence()
    }

    @objc private func prepareMismatchedReplacement() {
        replacementMode = .mismatched
        refreshEvidence()
    }

    @objc private func recordEdit(_ sender: KeyboardViewportTextField) {
        guard let slot = fieldSlots[ObjectIdentifier(sender)] else { return }
        editCounts[slot, default: 0] += 1
        if slot == .replacement {
            replacementValueLabel.accessibilityValue = sender.text ?? ""
        }
        postInteractionValueLabel.accessibilityValue = sender.text ?? ""
        refreshEvidence()
    }

    private func installTargetFields() {
        targetFields.forEach { field in
            fieldSlots[ObjectIdentifier(field)] = nil
            field.removeFromSuperview()
        }
        targetFields.removeAll()

        switch didReplaceTarget ? replacementMode : .unique {
        case .unique:
            let slot: FieldSlot = didReplaceTarget ? .replacement : .original
            let generation = didReplaceTarget ? "2" : "1"
            targetFields = [makeTargetField(slot: slot, semanticRole: "body", generation: generation)]
        case .ambiguous:
            targetFields = [
                makeTargetField(slot: .ambiguousFirst, semanticRole: "body", generation: "2A"),
                makeTargetField(slot: .ambiguousSecond, semanticRole: "body", generation: "2B"),
            ]
        case .mismatched:
            targetFields = [makeTargetField(slot: .mismatched, semanticRole: "scratch", generation: "2")]
        }
        targetFields.forEach(scrollView.addSubview)
        view.setNeedsLayout()
        refreshEvidence()
    }

    private func makeTargetField(
        slot: FieldSlot,
        semanticRole: String,
        generation: String
    ) -> KeyboardViewportTextField {
        let field = KeyboardViewportTextField(frame: .zero)
        field.borderStyle = .roundedRect
        field.placeholder = "Viewport note"
        field.accessibilityLabel = "Viewport note"
        field.accessibilityCustomContent = [
            importantCustomContent(label: "Semantic role", value: semanticRole),
            importantCustomContent(label: "Generation", value: generation),
        ]
        field.addTarget(self, action: #selector(recordEdit(_:)), for: .editingChanged)
        fieldSlots[ObjectIdentifier(field)] = slot
        return field
    }

    private func importantCustomContent(label: String, value: String) -> AXCustomContent {
        let content = AXCustomContent(label: label, value: value)
        content.importance = .high
        return content
    }

    private func refreshEvidence() {
        modeLabel.accessibilityValue = replacementMode.rawValue
        originalEditLabel.accessibilityValue = String(editCounts[.original, default: 0])
        replacementEditLabel.accessibilityValue = String(editCounts[.replacement, default: 0])
        if replacementValueLabel.accessibilityValue == nil {
            replacementValueLabel.accessibilityValue = ""
        }
        ambiguousEditLabel.accessibilityValue = [
            editCounts[.ambiguousFirst, default: 0],
            editCounts[.ambiguousSecond, default: 0],
        ]
        .map(String.init)
        .joined(separator: ", ")
        mismatchedEditLabel.accessibilityValue = String(editCounts[.mismatched, default: 0])
        if postInteractionValueLabel.accessibilityValue == nil {
            postInteractionValueLabel.accessibilityValue = ""
        }
        commitActionLabel.accessibilityValue = String(commitActionCount)
        discardActionLabel.accessibilityValue = String(discardActionCount)
    }
}

import SwiftUI
import UIKit

private struct TextFieldInteractionCounts: Equatable {
    var activationAttempts = 0
    var focusAcquisitions = 0
    var edits = 0
}

internal struct TextFieldFallbackScenarioView: View {
    @State private var draft = ""
    @State private var counts = TextFieldInteractionCounts()

    var body: some View {
        Form {
            Section {
                FalseActivateTextField(text: $draft, counts: $counts)
                    .frame(height: 44)
                Text(draft.isEmpty ? "Fallback field empty" : "Fallback field value: \(draft)")
                Text("Fallback field activity")
                    .accessibilityValue(
                        "Activation attempts \(counts.activationAttempts), "
                            + "focus acquisitions \(counts.focusAcquisitions), edits \(counts.edits)"
                    )
            }
        }
        .navigationTitle("Text Field Fallback")
        .onAppear {
            draft = ""
            counts = TextFieldInteractionCounts()
        }
    }
}

private struct FalseActivateTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var counts: TextFieldInteractionCounts

    func makeUIView(context: Context) -> UITextField {
        let field = RefusingActivationTextField(frame: .zero)
        field.borderStyle = .roundedRect
        field.placeholder = "Fallback field"
        field.accessibilityLabel = "Fallback field"
        field.delegate = context.coordinator
        field.onActivationAttempt = { [weak coordinator = context.coordinator] in
            coordinator?.recordActivationAttempt()
        }
        field.onFocusAcquired = { [weak coordinator = context.coordinator] in
            coordinator?.recordFocusAcquisition()
        }
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.accessibilityValue = text.isEmpty ? nil : text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, counts: $counts)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        @Binding var counts: TextFieldInteractionCounts

        init(text: Binding<String>, counts: Binding<TextFieldInteractionCounts>) {
            _text = text
            _counts = counts
        }

        @objc func changed(_ sender: UITextField) {
            text = sender.text ?? ""
            counts.edits += 1
        }

        func recordActivationAttempt() {
            counts.activationAttempts += 1
        }

        func recordFocusAcquisition() {
            counts.focusAcquisitions += 1
        }
    }
}

private final class RefusingActivationTextField: UITextField {
    var onActivationAttempt: (() -> Void)?
    var onFocusAcquired: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        onActivationAttempt?()
        return false
    }

    override func becomeFirstResponder() -> Bool {
        let wasFirstResponder = isFirstResponder
        let acquiredFocus = super.becomeFirstResponder()
        if acquiredFocus && !wasFirstResponder {
            onFocusAcquired?()
        }
        return acquiredFocus
    }
}

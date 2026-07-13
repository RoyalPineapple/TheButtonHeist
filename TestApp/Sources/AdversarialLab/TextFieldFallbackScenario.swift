import SwiftUI
import UIKit

internal struct TextFieldFallbackScenarioView: View {
    @State private var draft = ""

    var body: some View {
        Form {
            Section {
                FalseActivateTextField(text: $draft)
                    .frame(height: 44)
                Text(draft.isEmpty ? "Fallback field empty" : "Fallback field value: \(draft)")
            }
        }
        .navigationTitle("Text Field Fallback")
        .onAppear { draft = "" }
    }
}

private struct FalseActivateTextField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let field = RefusingActivationTextField(frame: .zero)
        field.borderStyle = .roundedRect
        field.placeholder = "Fallback field"
        field.accessibilityLabel = "Fallback field"
        field.delegate = context.coordinator
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
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func changed(_ sender: UITextField) {
            text = sender.text ?? ""
        }
    }
}

private final class RefusingActivationTextField: UITextField {
    override func accessibilityActivate() -> Bool {
        false
    }
}

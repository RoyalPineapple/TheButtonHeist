import SwiftUI
import ButtonHeist

struct ElementInspectorView: View {
    let element: UIElement
    let onActivate: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Element Details")
                        .font(.headline)
                    Spacer()
                    Button("Activate") {
                        onActivate()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                }

                Divider()

                InspectorSection(title: "Description") {
                    Text(element.description)
                        .textSelection(.enabled)
                }

                if let label = element.label {
                    InspectorSection(title: "Label") {
                        Text(label)
                            .textSelection(.enabled)
                    }
                }

                if let value = element.value, !value.isEmpty {
                    InspectorSection(title: "Value") {
                        Text(value)
                            .textSelection(.enabled)
                    }
                }

                InspectorSection(title: "Frame") {
                    Text("(\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))×\(Int(element.frameHeight))")
                        .font(.system(.body, design: .monospaced))
                }

                if let identifier = element.identifier, !identifier.isEmpty {
                    InspectorSection(title: "Identifier") {
                        Text(identifier)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if !element.actions.isEmpty {
                    InspectorSection(title: "Actions") {
                        Text(element.actions.joined(separator: ", "))
                    }
                }
            }
            .padding()
        }
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

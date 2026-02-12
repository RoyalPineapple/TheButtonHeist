import SwiftUI
import TheGoods

struct ElementInspectorView: View {
    let element: AccessibilityElementData
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

                if let hint = element.hint, !hint.isEmpty {
                    InspectorSection(title: "Hint") {
                        Text(hint)
                            .textSelection(.enabled)
                    }
                }

                if !element.traits.isEmpty {
                    InspectorSection(title: "Traits") {
                        Text(element.traits.joined(separator: ", "))
                            .font(.system(.body, design: .monospaced))
                    }
                }

                InspectorSection(title: "Frame") {
                    Text("(\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))×\(Int(element.frameHeight))")
                        .font(.system(.body, design: .monospaced))
                }

                InspectorSection(title: "Activation Point") {
                    Text("(\(Int(element.activationPointX)), \(Int(element.activationPointY)))")
                        .font(.system(.body, design: .monospaced))
                }

                if let identifier = element.identifier, !identifier.isEmpty {
                    InspectorSection(title: "Identifier") {
                        Text(identifier)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if !element.customActions.isEmpty {
                    InspectorSection(title: "Custom Actions") {
                        Text(element.customActions.joined(separator: ", "))
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

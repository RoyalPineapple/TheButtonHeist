import SwiftUI

struct SwiftUIAccessibilityValueProbeView: View {
    @State private var counter = 0
    @State private var level = 1
    @State private var remoteValue = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Every card is a hand-rolled SwiftUI accessibility element.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ActivatingSwiftUIValueCard(
                    title: "SwiftUI Counter",
                    value: counter.formatted(),
                    hint: "Increments the counter"
                ) {
                    counter += 1
                }

                AdjustableSwiftUIValueCard(
                    title: "SwiftUI Level",
                    value: $level,
                    range: 0...5
                )

                PassiveSwiftUIValueCard(
                    title: "SwiftUI Remote Value",
                    value: remoteValue.formatted()
                )

                Button("Update SwiftUI Remote Value") {
                    remoteValue += 1
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Text("The fixture never explicitly posts an accessibility notification.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("SwiftUI Value Probe")
    }
}

private struct ActivatingSwiftUIValueCard: View {
    let title: String
    let value: String
    let hint: String
    let activate: () -> Void

    var body: some View {
        SwiftUIValueCardContent(title: title, value: value)
            .contentShape(Rectangle())
            .onTapGesture(perform: activate)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                activate()
            }
    }
}

private struct AdjustableSwiftUIValueCard: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        SwiftUIValueCardContent(title: title, value: value.formatted())
            .contentShape(Rectangle())
            .onTapGesture {
                increment()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value.formatted())
            .accessibilityHint("Swipe up or down to adjust the level")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    increment()
                case .decrement:
                    decrement()
                @unknown default:
                    break
                }
            }
    }

    private func increment() {
        value = min(value + 1, range.upperBound)
    }

    private func decrement() {
        value = max(value - 1, range.lowerBound)
    }
}

private struct PassiveSwiftUIValueCard: View {
    let title: String
    let value: String

    var body: some View {
        SwiftUIValueCardContent(title: title, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
    }
}

private struct SwiftUIValueCardContent: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.title2)
                .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        SwiftUIAccessibilityValueProbeView()
    }
}

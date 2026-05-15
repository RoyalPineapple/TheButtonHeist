import SwiftUI
import UIKit

struct RotorsDemo: View {
    @Namespace private var issueNamespace

    private let issues = RotorDemoIssue.samples

    private var errorIssues: [RotorDemoIssue] {
        issues.filter { $0.severity == .error }
    }

    private var warningIssues: [RotorDemoIssue] {
        issues.filter { $0.severity == .warning }
    }

    var body: some View {
        List {
            Section("Validation Results") {
                ForEach(issues) { issue in
                    RotorDemoIssueRow(issue: issue)
                        .accessibilityRotorEntry(id: issue.id, in: issueNamespace)
                }
            }

            Section("Release Notes") {
                TextRangeRotorView()
                    .frame(minHeight: 160)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Validation Results")
        .accessibilityRotor("Errors") {
            ForEach(errorIssues) { issue in
                AccessibilityRotorEntry(Text(issue.rotorLabel), id: issue.id, in: issueNamespace)
            }
        }
        .accessibilityRotor("Warnings") {
            ForEach(warningIssues) { issue in
                AccessibilityRotorEntry(Text(issue.rotorLabel), id: issue.id, in: issueNamespace)
            }
        }
        .navigationTitle("Custom Rotors")
    }
}

private struct TextRangeRotorView: UIViewRepresentable {
    private let text = """
    Review @maria for payment wording.
    Ask @jules to confirm receipt copy.
    Route @nina through final risk review.
    """

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.text = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.isAccessibilityElement = true
        textView.accessibilityLabel = "Release Notes"
        textView.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Mentions") { [weak textView] predicate in
                guard let textView else { return nil }
                return Self.searchMentions(in: textView, predicate: predicate)
            }
        ]
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }

    private static func searchMentions(
        in textView: UITextView,
        predicate: UIAccessibilityCustomRotorSearchPredicate
    ) -> UIAccessibilityCustomRotorItemResult? {
        let ranges = mentionRanges(in: textView)
        guard !ranges.isEmpty else { return nil }

        let ordered = predicate.searchDirection == .next ? ranges : Array(ranges.reversed())
        if let currentRange = predicate.currentItem.targetRange,
           let index = ordered.firstIndex(of: currentRange) {
            let nextIndex = ordered.index(after: index)
            guard nextIndex < ordered.endIndex else { return nil }
            return UIAccessibilityCustomRotorItemResult(targetElement: textView, targetRange: ordered[nextIndex])
        }

        return UIAccessibilityCustomRotorItemResult(targetElement: textView, targetRange: ordered.first)
    }

    private static func mentionRanges(in textView: UITextView) -> [UITextRange] {
        let fullRange = NSRange(textView.text.startIndex..., in: textView.text)
        return mentionRegex.matches(in: textView.text, range: fullRange).compactMap { match in
            guard let start = textView.position(from: textView.beginningOfDocument, offset: match.range.location),
                  let end = textView.position(from: start, offset: match.range.length) else {
                return nil
            }
            return textView.textRange(from: start, to: end)
        }
    }

    private static let mentionRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: "@[A-Za-z]+")
        } catch {
            preconditionFailure("Static mention rotor regex failed to compile: \(error)")
        }
    }()
}

private struct RotorDemoIssueRow: View {
    let issue: RotorDemoIssue

    var body: some View {
        HStack(spacing: 12) {
            Text(issue.severity.symbol)
                .font(.headline)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.field)
                    .font(.headline)
                Text(issue.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(issue.severity.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(issue.severity.tint)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(issue.field). \(issue.message)")
        .accessibilityValue(issue.severity.title)
    }
}

private struct RotorDemoIssue: Identifiable {
    enum Severity {
        case error
        case warning

        var title: String {
            switch self {
            case .error: "Error"
            case .warning: "Warning"
            }
        }

        var symbol: String {
            switch self {
            case .error: "!"
            case .warning: "?"
            }
        }

        var tint: Color {
            switch self {
            case .error: .red
            case .warning: .orange
            }
        }
    }

    let id: String
    let field: String
    let message: String
    let severity: Severity

    var rotorLabel: String {
        "\(field), \(message)"
    }

    static let samples: [RotorDemoIssue] = [
        .init(id: "email_required", field: "Email", message: "Required", severity: .error),
        .init(id: "password_short", field: "Password", message: "Too short", severity: .warning),
        .init(id: "postal_code", field: "Postal Code", message: "Invalid format", severity: .error),
        .init(id: "phone_optional", field: "Phone", message: "Recommended", severity: .warning),
        .init(id: "terms_required", field: "Terms", message: "Must be accepted", severity: .error),
    ]
}

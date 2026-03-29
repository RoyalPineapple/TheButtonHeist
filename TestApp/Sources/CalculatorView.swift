import SwiftUI
import UIKit

struct CalculatorView: View {
    @State private var display = "0"
    @State private var currentValue: Double = 0
    @State private var pendingOperation: Operation?
    @State private var shouldResetDisplay = false

    enum Operation: String {
        case add = "+"
        case subtract = "−"
        case multiply = "×"
        case divide = "÷"
    }

    private let buttons: [[CalcButton]] = [
        [.clear, .negate, .percent, .op(.divide)],
        [.digit(7), .digit(8), .digit(9), .op(.multiply)],
        [.digit(4), .digit(5), .digit(6), .op(.subtract)],
        [.digit(1), .digit(2), .digit(3), .op(.add)],
        [.digit(0), .decimal, .equals],
    ]

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Text(display)
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("buttonheist.calc.display")

            ForEach(Array(buttons.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { button in
                        CalcButtonView(button: button, isActive: isActive(button)) {
                            handleButton(button)
                        }
                    }
                }
            }
        }
        .padding(12)
        .navigationTitle("Calculator")
    }

    private func isActive(_ button: CalcButton) -> Bool {
        if case .op(let op) = button, pendingOperation == op, shouldResetDisplay {
            return true
        }
        return false
    }

    private func handleButton(_ button: CalcButton) {
        switch button {
        case .digit(let n):
            if shouldResetDisplay {
                display = "\(n)"
                shouldResetDisplay = false
            } else if display == "0" {
                display = "\(n)"
            } else {
                display += "\(n)"
            }
            NSLog("[Calc] Digit: %d, display: %@", n, display)

        case .decimal:
            if shouldResetDisplay {
                display = "0."
                shouldResetDisplay = false
            } else if !display.contains(".") {
                display += "."
            }

        case .clear:
            display = "0"
            currentValue = 0
            pendingOperation = nil
            shouldResetDisplay = false
            NSLog("[Calc] Clear")

        case .negate:
            if display != "0" {
                if display.hasPrefix("-") {
                    display.removeFirst()
                } else {
                    display = "-" + display
                }
            }

        case .percent:
            if let value = Double(display) {
                let result = value / 100
                display = formatNumber(result)
            }

        case .op(let op):
            if let displayValue = Double(display) {
                if let pending = pendingOperation, !shouldResetDisplay {
                    currentValue = calculate(currentValue, displayValue, pending)
                    display = formatNumber(currentValue)
                } else {
                    currentValue = displayValue
                }
            }
            pendingOperation = op
            shouldResetDisplay = true
            NSLog("[Calc] Operation: %@", op.rawValue)

        case .equals:
            if let pending = pendingOperation, let displayValue = Double(display) {
                let result = calculate(currentValue, displayValue, pending)
                display = formatNumber(result)
                currentValue = result
                pendingOperation = nil
                shouldResetDisplay = true
                NSLog("[Calc] Equals: %@", display)
            }
        }
    }

    private func calculate(_ a: Double, _ b: Double, _ op: Operation) -> Double {
        switch op {
        case .add: return a + b
        case .subtract: return a - b
        case .multiply: return a * b
        case .divide: return b != 0 ? a / b : 0
        }
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        let formatted = String(format: "%.8f", value)
        return formatted.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}

enum CalcButton: Hashable {
    case digit(Int)
    case decimal
    case op(CalculatorView.Operation)
    case equals
    case clear
    case negate
    case percent

    var label: String {
        switch self {
        case .digit(let n): return "\(n)"
        case .decimal: return "."
        case .op(let op): return op.rawValue
        case .equals: return "="
        case .clear: return "AC"
        case .negate: return "±"
        case .percent: return "%"
        }
    }

    var accessibilityId: String {
        switch self {
        case .digit(let n): return "buttonheist.calc.digit\(n)"
        case .decimal: return "buttonheist.calc.decimal"
        case .op(let op):
            switch op {
            case .add: return "buttonheist.calc.add"
            case .subtract: return "buttonheist.calc.subtract"
            case .multiply: return "buttonheist.calc.multiply"
            case .divide: return "buttonheist.calc.divide"
            }
        case .equals: return "buttonheist.calc.equals"
        case .clear: return "buttonheist.calc.clear"
        case .negate: return "buttonheist.calc.negate"
        case .percent: return "buttonheist.calc.percent"
        }
    }
}

struct CalcButtonView: View {
    let button: CalcButton
    let isActive: Bool
    let action: () -> Void

    private var backgroundColor: Color {
        switch button {
        case .clear, .negate, .percent:
            return Color(UIColor.systemGray4)
        case .op, .equals:
            return isActive ? .white : .orange
        default:
            return Color(UIColor.systemGray5)
        }
    }

    private var foregroundColor: Color {
        switch button {
        case .op, .equals:
            return isActive ? .orange : .white
        default:
            return .primary
        }
    }

    var body: some View {
        Button(action: action) {
            Text(button.label)
                .font(.title2.weight(.medium))
                .frame(maxWidth: button == .digit(0) ? .infinity : 72, maxHeight: 72)
                .background(backgroundColor)
                .foregroundStyle(foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityIdentifier(button.accessibilityId)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        switch button {
        case .digit(let n): return "\(n)"
        case .decimal: return "decimal point"
        case .op(let op): return op.rawValue
        case .equals: return "equals"
        case .clear: return "all clear"
        case .negate: return "plus minus"
        case .percent: return "percent"
        }
    }
}

#Preview {
    NavigationStack {
        CalculatorView()
    }
}

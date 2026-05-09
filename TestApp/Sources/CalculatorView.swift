import SwiftUI
import UIKit

struct CalculatorView: View {
    @State private var display = "0"
    @State private var entryState: EntryState = .clean

    enum EntryState {
        case clean
        case operatorPending(accumulated: Double, operation: Operation)
        case enteringOperand(accumulated: Double, operation: Operation)
    }

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
        guard case .op(let operation) = button else { return false }
        switch entryState {
        case .operatorPending(_, let pending), .enteringOperand(_, let pending):
            return pending == operation
        case .clean:
            return false
        }
    }

    private func handleButton(_ button: CalcButton) {
        switch button {
        case .digit(let number): handleDigit(number)
        case .decimal: handleDecimal()
        case .clear: handleClear()
        case .negate: handleNegate()
        case .percent: handlePercent()
        case .op(let operation): handleOperator(operation)
        case .equals: handleEquals()
        }
    }

    private func handleDigit(_ number: Int) {
        switch entryState {
        case .operatorPending(let accumulated, let operation):
            display = "\(number)"
            entryState = .enteringOperand(accumulated: accumulated, operation: operation)
        case .clean, .enteringOperand:
            if display == "0" {
                display = "\(number)"
            } else {
                display += "\(number)"
            }
        }
    }

    private func handleDecimal() {
        switch entryState {
        case .operatorPending(let accumulated, let operation):
            display = "0."
            entryState = .enteringOperand(accumulated: accumulated, operation: operation)
        case .clean, .enteringOperand:
            if !display.contains(".") {
                display += "."
            }
        }
    }

    private func handleClear() {
        display = "0"
        entryState = .clean
    }

    private func handleNegate() {
        if display != "0" {
            if display.hasPrefix("-") {
                display.removeFirst()
            } else {
                display = "-" + display
            }
        }
    }

    private func handlePercent() {
        if let value = Double(display) {
            let result = value / 100
            display = formatNumber(result)
        }
    }

    private func handleOperator(_ operation: Operation) {
        if let displayValue = Double(display) {
            let accumulated: Double
            switch entryState {
            case .enteringOperand(let current, let pending):
                accumulated = calculate(current, displayValue, pending)
                display = formatNumber(accumulated)
            case .clean, .operatorPending:
                accumulated = displayValue
            }
            entryState = .operatorPending(accumulated: accumulated, operation: operation)
        }
    }

    private func handleEquals() {
        switch entryState {
        case .enteringOperand(let accumulated, let pending):
            if let displayValue = Double(display) {
                let result = calculate(accumulated, displayValue, pending)
                display = formatNumber(result)
                entryState = .clean
            }
        case .operatorPending(let accumulated, let pending):
            // "5 + =" repeats the operand: 5 + 5 = 10 (matches iOS Calculator)
            let result = calculate(accumulated, accumulated, pending)
            display = formatNumber(result)
            entryState = .clean
        case .clean:
            break
        }
    }

    private func calculate(_ a: Double, _ b: Double, _ operation: Operation) -> Double {
        switch operation {
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
        case .digit(let number): return "\(number)"
        case .decimal: return "."
        case .op(let operation): return operation.rawValue
        case .equals: return "="
        case .clear: return "AC"
        case .negate: return "±"
        case .percent: return "%"
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        switch button {
        case .digit(let number): return "\(number)"
        case .decimal: return "decimal point"
        case .op(let operation): return operation.rawValue
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

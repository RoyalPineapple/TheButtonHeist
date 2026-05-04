import SwiftUI

/// Analog-clock face with hands that rotate continuously via CALayer
/// animation. Used as a regression fixture for AX-tree-only settle:
/// callers should see actions on this screen settle within ~300ms even
/// though CALayer animations are running indefinitely. (Pre-auto-settle,
/// the single-cycle waitForAllClear timed out at 1s on this screen
/// because the layer fingerprint never quiesced.)
///
/// The accessibility tree is intentionally stable: one element labelled
/// "Analog clock" plus the action button. The hands have no AX
/// representation — they're purely visual.
struct AnalogClockDemo: View {

    @State private var actionsTapped = 0

    var body: some View {
        VStack(spacing: 32) {
            ClockFace()
                .frame(width: 220, height: 220)
                .accessibilityElement()
                .accessibilityLabel("Analog clock")
                .accessibilityAddTraits(.updatesFrequently)

            Button {
                actionsTapped += 1
            } label: {
                Text("Tap me — should still settle")
            }
            .buttonStyle(.borderedProminent)

            Text("Taps: \(actionsTapped)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .navigationTitle("Analog Clock")
    }
}

// MARK: - Clock Face

private struct ClockFace: UIViewRepresentable {

    func makeUIView(context: Context) -> ClockView {
        let view = ClockView(frame: CGRect(x: 0, y: 0, width: 220, height: 220))
        view.startAnimating()
        return view
    }

    func updateUIView(_ uiView: ClockView, context: Context) {}
}

private final class ClockView: UIView {

    private let secondHand = CAShapeLayer()
    private let minuteHand = CAShapeLayer()
    private let hourHand = CAShapeLayer()
    private let face = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        configureFace()
        configureHand(secondHand, length: 0.45, width: 1.5, color: .systemRed)
        configureHand(minuteHand, length: 0.40, width: 3, color: .label)
        configureHand(hourHand, length: 0.28, width: 4, color: .label)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        face.position = center
        face.bounds = bounds
        let facePath = UIBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
        face.path = facePath.cgPath
        for hand in [secondHand, minuteHand, hourHand] {
            hand.position = center
        }
    }

    private func configureFace() {
        face.fillColor = UIColor.tertiarySystemBackground.cgColor
        face.strokeColor = UIColor.label.cgColor
        face.lineWidth = 2
        layer.addSublayer(face)
    }

    private func configureHand(_ hand: CAShapeLayer, length: CGFloat, width: CGFloat, color: UIColor) {
        hand.strokeColor = color.cgColor
        hand.lineWidth = width
        hand.lineCap = .round
        layer.addSublayer(hand)
        let radius = bounds.width / 2 - 8
        let path = UIBezierPath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: -radius * length))
        hand.path = path.cgPath
    }

    func startAnimating() {
        addRotation(to: secondHand, period: 60)
        addRotation(to: minuteHand, period: 60 * 60)
        addRotation(to: hourHand, period: 60 * 60 * 12)
    }

    private func addRotation(to layer: CAShapeLayer, period: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = 2 * Double.pi
        animation.duration = period
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(animation, forKey: "rotate")
    }
}

#Preview {
    NavigationStack {
        AnalogClockDemo()
    }
}

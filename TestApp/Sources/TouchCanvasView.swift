import SwiftUI
import UIKit

// MARK: - UIKit Multi-Touch Drawing View

class TouchCanvasUIView: UIView {
    private var paths: [(color: UIColor, points: [CGPoint])] = []
    private var activeTouches: [UITouch: Int] = [:]
    private var nextColorIndex = 0

    private let colors: [UIColor] = [
        .systemRed, .systemBlue, .systemGreen, .systemOrange,
        .systemPurple, .systemTeal, .systemPink, .systemYellow
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .systemBackground
        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
        accessibilityLabel = "Touch Canvas"
    }

    required init?(coder: NSCoder) { fatalError() }

    func clearPaths() {
        paths.removeAll()
        activeTouches.removeAll()
        nextColorIndex = 0
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let color = colors[nextColorIndex]
            nextColorIndex = (nextColorIndex + 1) % colors.count
            let pathIndex = paths.count
            paths.append((color: color, points: [touch.location(in: self)]))
            activeTouches[touch] = pathIndex
        }
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let pathIndex = activeTouches[touch] else { continue }
            paths[pathIndex].points.append(touch.location(in: self))
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let pathIndex = activeTouches[touch] {
                paths[pathIndex].points.append(touch.location(in: self))
            }
            activeTouches.removeValue(forKey: touch)
        }
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(3)

        for path in paths {
            guard path.points.count > 1 else {
                if let point = path.points.first {
                    path.color.setFill()
                    context.fillEllipse(in: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                }
                continue
            }
            path.color.setStroke()
            context.beginPath()
            context.move(to: path.points[0])
            for point in path.points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }
    }
}

// MARK: - View Controller that defers system edge gestures

class TouchCanvasViewController: UIViewController {
    let canvasView = TouchCanvasUIView()

    override func loadView() {
        view = canvasView
    }

    private var disabledGestureRecognizers: [UIGestureRecognizer] = []

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        disableEdgePanGestures()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        reEnableEdgePanGestures()
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        .all
    }

    /// Walk the view hierarchy upward and disable any UIScreenEdgePanGestureRecognizer
    /// (used by UINavigationController for the interactive pop gesture).
    private func disableEdgePanGestures() {
        disabledGestureRecognizers.removeAll()
        var current: UIView? = view.superview
        while let v = current {
            for gr in v.gestureRecognizers ?? [] {
                if let edgePan = gr as? UIScreenEdgePanGestureRecognizer,
                   edgePan.edges.contains(.left), edgePan.isEnabled {
                    edgePan.isEnabled = false
                    disabledGestureRecognizers.append(edgePan)
                }
            }
            current = v.superview
        }
    }

    private func reEnableEdgePanGestures() {
        for gr in disabledGestureRecognizers {
            gr.isEnabled = true
        }
        disabledGestureRecognizers.removeAll()
    }
}

// MARK: - UIViewControllerRepresentable Bridge

struct TouchCanvasRepresentable: UIViewControllerRepresentable {
    let clearAction: Binding<Bool>

    func makeUIViewController(context: Context) -> TouchCanvasViewController {
        TouchCanvasViewController()
    }

    func updateUIViewController(_ vc: TouchCanvasViewController, context: Context) {
        if clearAction.wrappedValue {
            vc.canvasView.clearPaths()
            DispatchQueue.main.async {
                clearAction.wrappedValue = false
            }
        }
    }
}

// MARK: - SwiftUI View

struct TouchCanvasView: View {
    @State private var shouldClear = false

    var body: some View {
        TouchCanvasRepresentable(clearAction: $shouldClear)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Touch Canvas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        shouldClear = true
                    }
                }
            }
    }
}

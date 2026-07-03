import SwiftUI
import UIKit

struct UIKitFormDemoView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: FormViewController())
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

struct UIKitTableDemoView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: DemoTableViewController())
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

struct UIKitCollectionDemoView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: DemoCollectionViewController())
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

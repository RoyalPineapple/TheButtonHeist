import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        window = UIWindow(windowScene: windowScene)

        let tabBarController = UITabBarController()

        // Form tab
        let formVC = FormViewController()
        formVC.tabBarItem = UITabBarItem(title: "Form", image: UIImage(systemName: "doc.text"), tag: 0)

        // Table View tab
        let tableVC = DemoTableViewController()
        tableVC.tabBarItem = UITabBarItem(title: "Table", image: UIImage(systemName: "list.bullet"), tag: 1)

        // Collection View tab
        let collectionVC = DemoCollectionViewController()
        collectionVC.tabBarItem = UITabBarItem(title: "Collection", image: UIImage(systemName: "square.grid.2x2"), tag: 2)

        tabBarController.viewControllers = [
            UINavigationController(rootViewController: formVC),
            UINavigationController(rootViewController: tableVC),
            UINavigationController(rootViewController: collectionVC)
        ]

        window?.rootViewController = tabBarController
        window?.makeKeyAndVisible()
    }
}

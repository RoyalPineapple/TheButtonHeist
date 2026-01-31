import UIKit

class DemoTableViewController: UITableViewController {

    // MARK: - Data

    private struct Section {
        let title: String
        let items: [Item]
    }

    private struct Item {
        let title: String
        let subtitle: String?
        let accessoryType: UITableViewCell.AccessoryType
    }

    private let sections: [Section] = [
        Section(title: "Accessibility Features", items: [
            Item(title: "VoiceOver", subtitle: "Screen reader for blind users", accessoryType: .disclosureIndicator),
            Item(title: "Dynamic Type", subtitle: "Adjustable text sizes", accessoryType: .disclosureIndicator),
            Item(title: "Reduce Motion", subtitle: "Minimize animations", accessoryType: .disclosureIndicator),
            Item(title: "Increase Contrast", subtitle: "Enhanced visual distinction", accessoryType: .disclosureIndicator),
        ]),
        Section(title: "Testing Tools", items: [
            Item(title: "Accessibility Inspector", subtitle: "macOS debugging tool", accessoryType: .disclosureIndicator),
            Item(title: "XCTest", subtitle: "Automated UI testing", accessoryType: .disclosureIndicator),
            Item(title: "Voice Control", subtitle: "Hands-free navigation", accessoryType: .disclosureIndicator),
        ]),
        Section(title: "Best Practices", items: [
            Item(title: "Labels", subtitle: "Descriptive accessibility labels", accessoryType: .none),
            Item(title: "Hints", subtitle: "Contextual usage hints", accessoryType: .none),
            Item(title: "Traits", subtitle: "Element type identification", accessoryType: .none),
            Item(title: "Actions", subtitle: "Custom accessibility actions", accessoryType: .none),
        ])
    ]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UITableView Demo"
        tableView.accessibilityIdentifier = "demoTableView"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].items.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let item = sections[indexPath.section].items[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText = item.subtitle
        cell.contentConfiguration = config
        cell.accessoryType = item.accessoryType
        cell.accessibilityIdentifier = "tableCell_\(indexPath.section)_\(indexPath.row)"

        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let item = sections[indexPath.section].items[indexPath.row]
        let alert = UIAlertController(title: item.title, message: item.subtitle, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

import UIKit

class DemoCollectionViewController: UICollectionViewController {

    // MARK: - Data

    private struct AccessibilityItem {
        let symbol: String
        let title: String
        let color: UIColor
    }

    private let items: [AccessibilityItem] = [
        AccessibilityItem(symbol: "eye", title: "Vision", color: .systemBlue),
        AccessibilityItem(symbol: "ear", title: "Hearing", color: .systemGreen),
        AccessibilityItem(symbol: "hand.raised", title: "Motor", color: .systemOrange),
        AccessibilityItem(symbol: "brain", title: "Cognitive", color: .systemPurple),
        AccessibilityItem(symbol: "textformat.size", title: "Text Size", color: .systemRed),
        AccessibilityItem(symbol: "speaker.wave.3", title: "Audio", color: .systemTeal),
        AccessibilityItem(symbol: "rectangle.3.group", title: "Layout", color: .systemIndigo),
        AccessibilityItem(symbol: "arrow.left.arrow.right", title: "Navigation", color: .systemPink),
        AccessibilityItem(symbol: "hand.tap", title: "Touch", color: .systemYellow),
        AccessibilityItem(symbol: "keyboard", title: "Keyboard", color: .systemGray),
        AccessibilityItem(symbol: "mic", title: "Voice", color: .systemCyan),
        AccessibilityItem(symbol: "face.smiling", title: "Focus", color: .systemMint),
    ]

    // MARK: - Init

    init() {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1/3),
                heightDimension: .fractionalHeight(1.0)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(120)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 8, bottom: 16, trailing: 8)

            return section
        }

        super.init(collectionViewLayout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UICollectionView Demo"
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.accessibilityIdentifier = "demoCollectionView"
        collectionView.register(AccessibilityCell.self, forCellWithReuseIdentifier: "Cell")
    }

    // MARK: - UICollectionViewDataSource

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! AccessibilityCell
        let item = items[indexPath.item]
        cell.configure(symbol: item.symbol, title: item.title, color: item.color)
        cell.accessibilityIdentifier = "collectionCell_\(indexPath.item)"
        return cell
    }

    // MARK: - UICollectionViewDelegate

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = items[indexPath.item]
        let alert = UIAlertController(
            title: item.title,
            message: "Accessibility category: \(item.title)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Custom Cell

class AccessibilityCell: UICollectionViewCell {

    private let symbolView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .white
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textAlignment = .center
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.layer.cornerRadius = 12
        contentView.addSubview(symbolView)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -10),
            symbolView.widthAnchor.constraint(equalToConstant: 32),
            symbolView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: symbolView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
        ])
    }

    func configure(symbol: String, title: String, color: UIColor) {
        symbolView.image = UIImage(systemName: symbol)
        titleLabel.text = title
        contentView.backgroundColor = color

        // Accessibility
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
    }
}

import UIKit
import SnapKit

final class EctViewController: HTViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Item: Int, CaseIterable {
        case settings
        case paceCalculator

        var title: String {
            switch self {
            case .settings: return "설정"
            case .paceCalculator: return "페이스 계산기"
            }
        }

        var symbol: String {
            switch self {
            case .settings: return "gearshape.fill"
            case .paceCalculator: return "function"
            }
        }
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func configHierarchy() {
        view.addSubview(tableView)
    }

    override func configLayout() {
        tableView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
    }

    override func configView() {
        title = "기타"
        view.backgroundColor = AppColor.UI.backgroundGrouped
        tableView.backgroundColor = AppColor.UI.backgroundGrouped
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "EctCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Item.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = Item.allCases[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "EctCell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
        content.textProperties.color = AppColor.UI.textPrimary
        content.image = UIImage(systemName: item.symbol)
        content.imageProperties.tintColor = AppColor.UI.primary
        content.directionalLayoutMargins.top = 18
        content.directionalLayoutMargins.bottom = 18
        cell.contentConfiguration = content
        cell.backgroundColor = AppColor.UI.cardBackground
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let destination: UIViewController
        switch Item.allCases[indexPath.row] {
        case .settings: destination = SettingsViewController()
        case .paceCalculator: destination = PaceCalculatorViewController()
        }
        navigationController?.pushViewController(destination, animated: true)
    }
}

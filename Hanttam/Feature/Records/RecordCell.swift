//
//  RecordCell.swift
//  Hanttam
//

import UIKit
import SnapKit

final class RecordCell: UITableViewCell {

    static let id = "RecordCell"

    private let dateLabel     = UILabel()
    private let sourceLabel   = UILabel()
    private let distanceLabel = UILabel()
    private let detailStack   = UIStackView()
    private let durationLabel = UILabel()
    private let caloriesLabel = UILabel()
    private let routeImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.backgroundColor = AppColor.UI.tertiarySystemFill
        return iv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        accessoryType = .disclosureIndicator
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        routeImageView.image = nil
        routeImageView.contentMode = .scaleAspectFill
        routeImageView.tintColor = nil
        routeImageView.backgroundColor = AppColor.UI.tertiarySystemFill
        sourceLabel.textColor = AppColor.UI.textTertiary
    }

    private func setupUI() {
        dateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        dateLabel.textColor = AppColor.UI.textSecondary

        sourceLabel.font = .systemFont(ofSize: 11, weight: .regular)
        sourceLabel.textColor = AppColor.UI.textTertiary

        distanceLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .light)

        durationLabel.font = .systemFont(ofSize: 13)
        durationLabel.textColor = AppColor.UI.textSecondary

        caloriesLabel.font = .systemFont(ofSize: 13)
        caloriesLabel.textColor = AppColor.UI.textSecondary

        detailStack.axis = .horizontal
        detailStack.spacing = 12
        detailStack.addArrangedSubview(durationLabel)
        detailStack.addArrangedSubview(caloriesLabel)

        let topStack = UIStackView(arrangedSubviews: [dateLabel, sourceLabel, UIView()])
        topStack.axis = .horizontal
        topStack.spacing = 8
        topStack.alignment = .firstBaseline

        let vStack = UIStackView(arrangedSubviews: [topStack, distanceLabel, detailStack])
        vStack.axis = .vertical
        vStack.spacing = 2

        contentView.addSubview(vStack)
        contentView.addSubview(routeImageView)

        routeImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(60)
        }
        vStack.snp.makeConstraints { make in
            make.leading.equalTo(routeImageView.snp.trailing).offset(12)
            make.trailing.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
        }
    }

    func configure(with record: RunningRecord, dateFormatter: DateFormatter) {
        dateLabel.text = dateFormatter.string(from: record.date)
        sourceLabel.text = record.sourceName
        updateRouteIcon(isIndoor: record.isIndoor)
        distanceLabel.text = AppFormatter.distance2f(record.distance)
        durationLabel.text = AppFormatter.duration(record.duration)
        caloriesLabel.text = AppFormatter.calories(record.calories)
    }

    func configureInterval(with record: IntervalRecord, isIndoor: Bool, dateFormatter: DateFormatter) {
        dateLabel.text = dateFormatter.string(from: record.date)
        sourceLabel.text = "INTERVAL"
        sourceLabel.textColor = RunningLevelManager.shared.accentUIColor
        updateRouteIcon(isIndoor: isIndoor)
        distanceLabel.text = AppFormatter.distance2f(record.totalDistance)
        durationLabel.text = AppFormatter.duration(record.totalDuration)
        caloriesLabel.text = "\(record.settings.sets)세트 · \(Int(record.settings.lapDistance))m"
    }

    private func updateRouteIcon(isIndoor: Bool) {
        if isIndoor {
            let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .light)
            routeImageView.image = UIImage(systemName: "figure.run.treadmill", withConfiguration: config)
            routeImageView.tintColor = RunningLevelManager.shared.accentUIColor.withAlphaComponent(0.6)
            routeImageView.contentMode = .center
            routeImageView.backgroundColor = RunningLevelManager.shared.accentUIColor.withAlphaComponent(0.08)
        } else {
            routeImageView.image = nil
            routeImageView.contentMode = .scaleAspectFill
            routeImageView.backgroundColor = AppColor.UI.tertiarySystemFill
        }
    }

    func setRouteImage(_ image: UIImage?) {
        guard let image else { return }
        routeImageView.image = image
        routeImageView.contentMode = .scaleAspectFill
        routeImageView.backgroundColor = AppColor.UI.tertiarySystemFill
        routeImageView.tintColor = nil
    }
}

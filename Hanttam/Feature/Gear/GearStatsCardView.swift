//
//  GearStatsCardView.swift
//  Hanttam
//

import UIKit
import SnapKit

final class GearStatsCardView: HTView {
    private let titleLabel        = UILabel()
    private let subtitleLabel     = UILabel()
    private let metricsStackView  = UIStackView()
    private let runsMetricView    = GearMetricView()
    private let paceMetricView    = GearMetricView()
    private let durationMetricView = GearMetricView()

    override func configHierarchy() {
        [titleLabel, subtitleLabel, metricsStackView].forEach { addSubview($0) }
        [runsMetricView, paceMetricView, durationMetricView].forEach { metricsStackView.addArrangedSubview($0) }
    }

    override func configLayout() {
        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(24)
        }
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        metricsStackView.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(24)
            make.leading.trailing.bottom.equalToSuperview().inset(24)
        }
    }

    override func configView() {
        backgroundColor = AppColor.UI.cardBackground
        layer.cornerRadius = 24
        layer.borderWidth = 1
        layer.borderColor = AppColor.UI.border.cgColor

        titleLabel.font = AppFont.UI.headlineSM
        titleLabel.textColor = AppColor.UI.textPrimary
        titleLabel.numberOfLines = 2

        subtitleLabel.font = AppFont.UI.bodyMD
        subtitleLabel.textColor = AppColor.UI.textSecondary
        subtitleLabel.numberOfLines = 2

        metricsStackView.axis = .horizontal
        metricsStackView.distribution = .fillEqually
        metricsStackView.spacing = 12
    }

    func configure(with shoe: RegisteredShoe, stats: ShoeAggregateStats, sessionsCount: Int) {
        titleLabel.text = "\(shoe.brandName) \(shoe.modelName)"

        var metaParts: [String] = []
        if shoe.displayName != shoe.modelName { metaParts.append("별칭: \(shoe.displayName)") }
        if !shoe.colors.isEmpty { metaParts.append(shoe.colors.joined(separator: ", ")) }
        subtitleLabel.text = metaParts.isEmpty ? shoe.sku : metaParts.joined(separator: "\n")

        runsMetricView.configure(value: "\(sessionsCount)", title: "러닝")
        paceMetricView.configure(value: GearFormatters.pace(stats.averagePace), title: "평균 페이스")
        durationMetricView.configure(value: GearFormatters.duration(stats.totalDuration), title: "시간")
    }
}

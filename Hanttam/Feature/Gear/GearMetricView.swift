//
//  GearMetricView.swift
//  Hanttam
//

import UIKit
import SnapKit

final class GearMetricView: HTView {
    private let valueLabel = UILabel()
    private let titleLabel = UILabel()

    override func configHierarchy() {
        [valueLabel, titleLabel].forEach { addSubview($0) }
    }

    override func configLayout() {
        valueLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(valueLabel.snp.bottom).offset(6)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    override func configView() {
        valueLabel.font = AppFont.UI.metricLabel
        valueLabel.textColor = AppColor.UI.textPrimary
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        titleLabel.font = AppFont.UI.bodyMD
        titleLabel.textColor = AppColor.UI.textSecondary
        titleLabel.textAlignment = .center
    }

    func configure(value: String, title: String) {
        valueLabel.text = value
        titleLabel.text = title
    }
}

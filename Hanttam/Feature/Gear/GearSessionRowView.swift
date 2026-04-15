//
//  GearSessionRowView.swift
//  Hanttam
//

import UIKit
import RxSwift
import RxCocoa
import SnapKit

final class GearSessionRowView: HTView {
    private let button     = UIButton(type: .system)
    private let kindLabel  = UILabel()
    private let dateLabel  = UILabel()
    private let valueLabel = UILabel()

    var onTap: (() -> Void)?

    override func configHierarchy() {
        addSubview(button)
        [kindLabel, dateLabel, valueLabel].forEach { button.addSubview($0) }
    }

    override func configLayout() {
        button.snp.makeConstraints { make in make.edges.equalToSuperview() }
        kindLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(16)
            make.trailing.lessThanOrEqualTo(valueLabel.snp.leading).offset(-12)
        }
        dateLabel.snp.makeConstraints { make in
            make.top.equalTo(kindLabel.snp.bottom).offset(6)
            make.leading.bottom.equalToSuperview().inset(16)
            make.trailing.lessThanOrEqualTo(valueLabel.snp.leading).offset(-12)
        }
        valueLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().inset(16)
        }
    }

    override func configView() {
        button.backgroundColor = AppColor.UI.cardBackground
        button.layer.cornerRadius = 18
        button.layer.borderWidth = 1
        button.layer.borderColor = AppColor.UI.border.cgColor
        button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)

        kindLabel.font = AppFont.UI.titleSM
        kindLabel.textColor = AppColor.UI.textPrimary

        dateLabel.font = AppFont.UI.bodySM
        dateLabel.textColor = AppColor.UI.textSecondary

        valueLabel.font = AppFont.UI.metricCaption
        valueLabel.textColor = AppColor.UI.textPrimary
        valueLabel.numberOfLines = 2
        valueLabel.textAlignment = .right
    }

    func configure(with session: GearLinkedSessionItem) {
        kindLabel.text = session.title
        dateLabel.text = AppFormatter.recordDate.string(from: session.startedAt)
        valueLabel.text = "\(AppFormatter.distance1f(session.distance))\n\(GearFormatters.duration(session.duration))"
    }

    @objc private func handleTap() { onTap?() }
}

//
//  RunDetailGearLinkCardView.swift
//  Hanttam
//
//  Created by Codex on 4/8/26.
//

import UIKit
import SnapKit

final class RunDetailGearLinkCardView: HTView {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)

    var onPrimaryTap: (() -> Void)?
    var onSecondaryTap: (() -> Void)?

    override func configHierarchy() {
        [titleLabel, subtitleLabel, primaryButton, secondaryButton].forEach { addSubview($0) }
    }

    override func configLayout() {
        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(18)
        }
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.equalTo(titleLabel)
        }
        primaryButton.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(16)
            make.leading.equalTo(titleLabel)
            make.height.equalTo(42)
            make.bottom.equalToSuperview().inset(18)
        }
        secondaryButton.snp.makeConstraints { make in
            make.top.height.bottom.equalTo(primaryButton)
            make.leading.equalTo(primaryButton.snp.trailing).offset(10)
            make.trailing.equalTo(titleLabel)
            make.width.equalTo(primaryButton)
        }
    }

    override func configView() {
        backgroundColor = AppColor.UI.cardBackground
        layer.cornerRadius = 20
        layer.borderWidth = 1
        layer.borderColor = AppColor.UI.border.cgColor

        titleLabel.font = AppFont.UI.titleMD
        titleLabel.textColor = AppColor.UI.textPrimary
        titleLabel.text = "연결 운동화"

        subtitleLabel.font = AppFont.UI.bodyMD
        subtitleLabel.textColor = AppColor.UI.textSecondary
        subtitleLabel.numberOfLines = 0

        primaryButton.layer.cornerRadius = 12
        primaryButton.backgroundColor = AppColor.UI.primary
        primaryButton.setTitleColor(.white, for: .normal)
        primaryButton.titleLabel?.font = AppFont.UI.bodyLG
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        secondaryButton.layer.cornerRadius = 12
        secondaryButton.layer.borderWidth = 1
        secondaryButton.layer.borderColor = AppColor.UI.border.cgColor
        secondaryButton.backgroundColor = AppColor.UI.cardBackground
        secondaryButton.setTitleColor(AppColor.UI.textPrimary, for: .normal)
        secondaryButton.titleLabel?.font = AppFont.UI.bodyLG
        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)
    }

    func configure(with shoe: RegisteredShoe?) {
        if let shoe {
            subtitleLabel.text = "\(shoe.brandName.uppercased())\n\(shoe.modelName)"
            primaryButton.setTitle("운동화 변경", for: .normal)
            secondaryButton.setTitle("연결 해제", for: .normal)
            secondaryButton.isHidden = false
        } else {
            subtitleLabel.text = "현재 세션에 연결된 운동화가 없습니다."
            primaryButton.setTitle("운동화 연결", for: .normal)
            secondaryButton.isHidden = true
        }
    }

    @objc private func primaryTapped() {
        onPrimaryTap?()
    }

    @objc private func secondaryTapped() {
        onSecondaryTap?()
    }
}

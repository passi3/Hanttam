//
//  BrandCell.swift
//  Hanttam
//

import UIKit
import Kingfisher
import SnapKit

final class BrandCell: HTCollectionViewCell {
    static let reuseID = "BrandCell"

    private let cardView  = UIView()
    private let imageView = UIImageView()
    private let nameLabel = UILabel()

    override func configHierarchy() {
        contentView.addSubview(cardView)
        cardView.addSubview(imageView)
        cardView.addSubview(nameLabel)
    }

    override func configLayout() {
        cardView.snp.makeConstraints { make in make.edges.equalToSuperview() }
        imageView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(12)
            make.height.equalTo(44)
        }
        nameLabel.snp.makeConstraints { make in
            make.top.equalTo(imageView.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(8)
            make.bottom.lessThanOrEqualToSuperview().inset(12)
        }
    }

    override func configView() {
        backgroundColor = .clear
        cardView.backgroundColor = AppColor.UI.cardBackground
        cardView.layer.cornerRadius = 16
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = AppColor.UI.border.cgColor

        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = AppColor.UI.textSecondary
        imageView.image = UIImage(systemName: "shoeprints.fill")

        nameLabel.font = AppFont.UI.labelLG
        nameLabel.textColor = AppColor.UI.textPrimary
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.kf.cancelDownloadTask()
        imageView.image = UIImage(systemName: "shoeprints.fill")
    }

    func configure(with brand: BrandSummary) {
        nameLabel.text = brand.name
        let placeholder = UIImage(systemName: "shoeprints.fill")
        if let logoURL = brand.logoURL, let url = URL(string: logoURL) {
            imageView.kf.setImage(with: url, placeholder: placeholder)
        } else {
            imageView.image = placeholder
        }
    }
}

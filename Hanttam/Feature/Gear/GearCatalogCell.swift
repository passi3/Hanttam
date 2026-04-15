//
//  GearCatalogCell.swift
//  Hanttam
//

import UIKit
import SnapKit

final class GearCatalogCell: HTTableViewCell {
    static let reuseID = "GearCatalogCell"

    private let cardView      = HTView()
    private let shoeImageView = UIImageView()
    private let brandLabel    = UILabel()
    private let modelLabel    = UILabel()
    private let metaLabel     = UILabel()
    private var imageTask: URLSessionDataTask?

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        shoeImageView.image = UIImage(systemName: "shoeprints.fill")
    }

    override func configHierarchy() {
        contentView.addSubview(cardView)
        [shoeImageView, brandLabel, modelLabel, metaLabel].forEach { cardView.addSubview($0) }
    }

    override func configLayout() {
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4))
        }
        shoeImageView.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(14)
            make.width.height.equalTo(68)
            make.bottom.lessThanOrEqualToSuperview().inset(14)
        }
        brandLabel.snp.makeConstraints { make in
            make.top.equalTo(shoeImageView)
            make.leading.equalTo(shoeImageView.snp.trailing).offset(12)
            make.trailing.equalToSuperview().inset(14)
        }
        modelLabel.snp.makeConstraints { make in
            make.top.equalTo(brandLabel.snp.bottom).offset(4)
            make.leading.trailing.equalTo(brandLabel)
        }
        metaLabel.snp.makeConstraints { make in
            make.top.equalTo(modelLabel.snp.bottom).offset(8)
            make.leading.trailing.equalTo(brandLabel)
            make.bottom.equalToSuperview().inset(16)
        }
    }

    override func configView() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        cardView.backgroundColor = AppColor.UI.cardBackground
        cardView.layer.cornerRadius = 18
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = AppColor.UI.border.cgColor

        shoeImageView.contentMode = .scaleAspectFit
        shoeImageView.layer.cornerRadius = 12
        shoeImageView.clipsToBounds = true
        shoeImageView.backgroundColor = AppColor.UI.backgroundSecondary
        shoeImageView.image = UIImage(systemName: "shoe")
        shoeImageView.tintColor = AppColor.UI.textSecondary

        brandLabel.font = AppFont.UI.labelLG
        brandLabel.textColor = AppColor.UI.textSecondary

        modelLabel.font = AppFont.UI.titleMD
        modelLabel.textColor = AppColor.UI.textPrimary
        modelLabel.numberOfLines = 2

        metaLabel.font = AppFont.UI.bodySM
        metaLabel.textColor = AppColor.UI.textSecondary
        metaLabel.numberOfLines = 2

        accessoryType = .none
    }

    func configure(with item: ShoeSearchResult, fallbackImageURL: String?) {
        let representative = item.representativeItem
        brandLabel.text = item.brandName.uppercased()
        modelLabel.text = item.modelName
        let summary = "\(max(item.variantCount, item.variants.count))개 옵션"
        let sku = representative?.sku ?? ""
        metaLabel.text = [sku, summary].filter { !$0.isEmpty }.joined(separator: "\n")
        imageTask = RemoteImageLoader.shared.loadImage(
            from: representative?.imageURL ?? item.thumbnailURL ?? fallbackImageURL
        ) { [weak self] image in
            self?.shoeImageView.image = image ?? UIImage(systemName: "shoe")
            self?.shoeImageView.tintColor = AppColor.UI.textSecondary
        }
    }
}

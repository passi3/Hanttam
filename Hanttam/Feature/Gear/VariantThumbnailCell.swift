//
//  VariantThumbnailCell.swift
//  Hanttam
//

import UIKit
import SnapKit

final class VariantThumbnailCell: HTCollectionViewCell {
    static let reuseID = "VariantThumbnailCell"

    private let imageView = UIImageView()
    private var imageTask: URLSessionDataTask?

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        imageView.image = UIImage(systemName: "shoe")
    }

    override func configHierarchy() {
        contentView.addSubview(imageView)
    }

    override func configLayout() {
        imageView.snp.makeConstraints { make in make.edges.equalToSuperview() }
    }

    override func configView() {
        contentView.backgroundColor = AppColor.UI.cardBackground
        contentView.layer.cornerRadius = 14
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = AppColor.UI.border.cgColor

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 14
        imageView.backgroundColor = AppColor.UI.backgroundSecondary
        imageView.tintColor = AppColor.UI.textSecondary
        imageView.image = UIImage(systemName: "shoe")
    }

    func configure(with item: ShoeCatalogItem, isSelected: Bool) {
        setSelectedAppearance(isSelected)
        imageTask = RemoteImageLoader.shared.loadImage(from: item.imageURL) { [weak self] image in
            self?.imageView.image = image ?? UIImage(systemName: "shoe")
            self?.imageView.tintColor = AppColor.UI.textSecondary
        }
    }

    func setSelectedAppearance(_ isSelected: Bool) {
        contentView.layer.borderColor = isSelected
            ? RunningLevelManager.shared.accentUIColor.cgColor
            : AppColor.UI.border.cgColor
        contentView.layer.borderWidth = isSelected ? 2 : 1
    }
}

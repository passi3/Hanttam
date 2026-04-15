//
//  ShoeEditPreviewView.swift
//  Hanttam
//

import UIKit
import SnapKit

final class ShoeEditPreviewView: HTView {
    private let shoeImageView          = UIImageView()
    private let variantsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let titleLabel             = UILabel()
    private let metaLabel              = UILabel()
    private var collectionHeightConstraint: Constraint?

    private var variants: [ShoeCatalogItem] = []
    private var currentShoe: RegisteredShoe?
    private var onSelectVariant: ((ShoeCatalogItem) -> Void)?
    private var imageTask: URLSessionDataTask?
    private var currentImageURL: String?

    override func configHierarchy() {
        [shoeImageView, variantsCollectionView, titleLabel, metaLabel].forEach { addSubview($0) }
    }

    override func configLayout() {
        shoeImageView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(220)
        }
        variantsCollectionView.snp.makeConstraints { make in
            make.top.equalTo(shoeImageView.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(20)
            collectionHeightConstraint = make.height.equalTo(60).constraint
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(variantsCollectionView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        metaLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview().inset(20)
        }
    }

    override func configView() {
        backgroundColor = AppColor.UI.cardBackground
        layer.cornerRadius = 24
        layer.borderWidth = 1
        layer.borderColor = AppColor.UI.border.cgColor

        shoeImageView.contentMode = .scaleAspectFit
        shoeImageView.backgroundColor = AppColor.UI.backgroundSecondary
        shoeImageView.layer.cornerRadius = 18
        shoeImageView.clipsToBounds = true
        shoeImageView.image = UIImage(systemName: "shoeprints.fill")
        shoeImageView.tintColor = AppColor.UI.textSecondary

        if let layout = variantsCollectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.scrollDirection = .horizontal
            layout.minimumLineSpacing = 8
            layout.minimumInteritemSpacing = 8
        }
        variantsCollectionView.register(ShoeEditColorwayCell.self, forCellWithReuseIdentifier: ShoeEditColorwayCell.reuseID)
        variantsCollectionView.backgroundColor = .clear
        variantsCollectionView.showsHorizontalScrollIndicator = false
        variantsCollectionView.dataSource = self
        variantsCollectionView.delegate = self

        titleLabel.font = AppFont.UI.headlineSM
        titleLabel.textColor = AppColor.UI.textPrimary
        titleLabel.numberOfLines = 2

        metaLabel.font = AppFont.UI.bodyMD
        metaLabel.textColor = AppColor.UI.textSecondary
        metaLabel.numberOfLines = 3
    }

    func configure(
        with shoe: RegisteredShoe,
        variants: [ShoeCatalogItem],
        onSelectVariant: ((ShoeCatalogItem) -> Void)?
    ) {
        let previousSKU = currentShoe?.sku
        let didVariantsChange = self.variants != variants
        currentShoe = shoe
        self.variants = variants
        self.onSelectVariant = onSelectVariant

        titleLabel.text = shoe.displayName
        metaLabel.text = [shoe.brandName.uppercased(), shoe.modelName, shoe.colors.joined(separator: ", ")]
            .filter { !$0.isEmpty }.joined(separator: "\n")

        let collectionHeight: CGFloat = variants.isEmpty ? 0 : 60
        collectionHeightConstraint?.update(offset: collectionHeight)
        variantsCollectionView.isHidden = variants.isEmpty

        if didVariantsChange {
            UIView.performWithoutAnimation {
                variantsCollectionView.reloadData()
                variantsCollectionView.layoutIfNeeded()
            }
        } else if previousSKU != shoe.sku {
            if let prev = previousSKU, let idx = variants.firstIndex(where: { $0.sku == prev }) {
                updateSelectionAppearance(at: IndexPath(item: idx, section: 0), isSelected: false)
            }
            if let idx = variants.firstIndex(where: { $0.sku == shoe.sku }) {
                updateSelectionAppearance(at: IndexPath(item: idx, section: 0), isSelected: true)
            }
        }

        if currentImageURL != shoe.imageURL {
            currentImageURL = shoe.imageURL
            imageTask?.cancel()
            imageTask = RemoteImageLoader.shared.loadImage(from: shoe.imageURL) { [weak self] image in
                self?.shoeImageView.image = image ?? UIImage(systemName: "shoeprints.fill")
                self?.shoeImageView.tintColor = AppColor.UI.textSecondary
            }
        }
    }

    private func updateSelectionAppearance(at indexPath: IndexPath, isSelected: Bool) {
        UIView.performWithoutAnimation {
            if let cell = variantsCollectionView.cellForItem(at: indexPath) as? ShoeEditColorwayCell {
                cell.setSelectedAppearance(isSelected)
            }
            variantsCollectionView.layoutIfNeeded()
        }
    }
}

extension ShoeEditPreviewView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        variants.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ShoeEditColorwayCell.reuseID, for: indexPath
        ) as! ShoeEditColorwayCell
        let item = variants[indexPath.item]
        cell.configure(with: item, isSelected: item.sku == currentShoe?.sku)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard variants.indices.contains(indexPath.item) else { return }
        onSelectVariant?(variants[indexPath.item])
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        CGSize(width: 52, height: 52)
    }
}

//
//  ShoeBrandSelectViewController.swift
//  Hanttam
//
//  Created by passi on 4/10/26.
//

import UIKit
import SnapKit
import Kingfisher

final class ShoeBrandSelectViewController: HTViewController {
    private let onRegistered: ((RegisteredShoe) -> Void)?
    private let service: BrandServicing

    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let manualRegisterButton = UIButton(type: .system)
    private let searchController = UISearchController(searchResultsController: nil)

    private var brands: [BrandSummary] = []
    private var filteredBrands: [BrandSummary] = []
    private let itemSpacing: CGFloat = 12

    init(
        onRegistered: ((RegisteredShoe) -> Void)? = nil,
        service: BrandServicing = SupabaseShoeSearchService()
    ) {
        self.onRegistered = onRegistered
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        fetchBrands()
    }

    override func configHierarchy() {
        view.addSubview(collectionView)
        view.addSubview(statusLabel)
        view.addSubview(spinner)
        view.addSubview(manualRegisterButton)
    }

    override func configLayout() {
        collectionView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        statusLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(28)
        }
        spinner.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(statusLabel.snp.top).offset(-12)
        }
        manualRegisterButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.height.equalTo(54)
        }
    }

    override func configView() {
        title = "브랜드 선택"
        view.backgroundColor = AppColor.UI.backgroundGrouped
        definesPresentationContext = true

        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "브랜드 검색"
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController

        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.minimumLineSpacing = itemSpacing
            layout.minimumInteritemSpacing = itemSpacing
            layout.sectionInset = UIEdgeInsets(top: 20, left: 20, bottom: 94, right: 20)
        }
        collectionView.register(BrandCell.self, forCellWithReuseIdentifier: BrandCell.reuseID)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self

        manualRegisterButton.setTitle("직접 등록", for: .normal)
        manualRegisterButton.titleLabel?.font = AppFont.UI.buttonMD
        manualRegisterButton.setTitleColor(AppColor.UI.textPrimary, for: .normal)
        manualRegisterButton.backgroundColor = AppColor.UI.cardBackground
        manualRegisterButton.layer.cornerRadius = 16
        manualRegisterButton.layer.borderWidth = 1
        manualRegisterButton.layer.borderColor = AppColor.UI.border.cgColor
        manualRegisterButton.addTarget(self, action: #selector(manualRegisterTapped), for: .touchUpInside)

        statusLabel.font = AppFont.UI.bodyLG
        statusLabel.textColor = AppColor.UI.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "브랜드를 불러오는 중입니다."
    }

    private func fetchBrands() {
        spinner.startAnimating()
        service.fetchBrands { [weak self] result in
            guard let self else { return }
            self.spinner.stopAnimating()
            switch result {
            case .success(let brands):
                self.brands = brands
                self.applyFilter(query: self.searchController.searchBar.text ?? "")
            case .failure(let error):
                self.brands = []
                self.filteredBrands = []
                self.collectionView.reloadData()
                self.statusLabel.text = error.localizedDescription
                self.statusLabel.isHidden = false
            }
        }
    }

    private func applyFilter(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            filteredBrands = brands
        } else {
            filteredBrands = brands.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        }
        collectionView.reloadData()
        if brands.isEmpty {
            statusLabel.text = "등록 가능한 브랜드가 없습니다."
            statusLabel.isHidden = false
        } else if filteredBrands.isEmpty {
            statusLabel.text = "검색 결과가 없습니다."
            statusLabel.isHidden = false
        } else {
            statusLabel.isHidden = true
        }
    }

    private func selectBrand(at indexPath: IndexPath) {
        guard filteredBrands.indices.contains(indexPath.item) else { return }
        let brand = filteredBrands[indexPath.item]
        let viewController = ShoeSearchViewController(
            brand: brand,
            onRegistered: onRegistered
        )
        navigationController?.pushViewController(viewController, animated: true)
    }

    @objc private func manualRegisterTapped() {
        let viewController = RegisterShoeViewController(
            mode: .manual,
            onRegistered: onRegistered
        )
        navigationController?.pushViewController(viewController, animated: true)
    }
}

extension ShoeBrandSelectViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        filteredBrands.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: BrandCell.reuseID,
            for: indexPath
        ) as! BrandCell
        cell.configure(with: filteredBrands[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectBrand(at: indexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let horizontalInset: CGFloat = 20 * 2
        let totalSpacing = itemSpacing * 2
        let width = floor((collectionView.bounds.width - horizontalInset - totalSpacing) / 3)
        return CGSize(width: width, height: 92)
    }
}

extension ShoeBrandSelectViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        applyFilter(query: searchController.searchBar.text ?? "")
    }
}

private final class BrandCell: HTCollectionViewCell {
    static let reuseID = "BrandCell"

    private let cardView = UIView()
    private let imageView = UIImageView()
    private let nameLabel = UILabel()

    override func configHierarchy() {
        contentView.addSubview(cardView)
        cardView.addSubview(imageView)
        cardView.addSubview(nameLabel)
    }

    override func configLayout() {
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
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
        if let logoURL = brand.logoURL,
           let url = URL(string: logoURL) {
            imageView.kf.setImage(with: url, placeholder: placeholder)
        } else {
            imageView.image = placeholder
        }
    }
}

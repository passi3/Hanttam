//
//  ShoeSearchViewController.swift
//  Hanttam
//
//  Created by passi on 4/8/26.
//

import UIKit
import RxCocoa
import RxSwift
import SnapKit

final class ShoeSearchViewController: HTViewController {
    private let viewModel: ShoeSearchViewModel
    private let onRegistered: ((RegisteredShoe) -> Void)?
    private let brand: BrandSummary?
    private let viewDidLoadSubject = PublishSubject<Void>()
    private let selectItemSubject = PublishSubject<Int>()
    private let disposeBag = DisposeBag()

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let searchController = UISearchController(searchResultsController: nil)

    private var results: [ShoeSearchResult] = []

    init(
        brand: BrandSummary? = nil,
        viewModel: ShoeSearchViewModel? = nil,
        onRegistered: ((RegisteredShoe) -> Void)? = nil
    ) {
        self.brand = brand
        self.viewModel = viewModel ?? ShoeSearchViewModel(brand: brand)
        self.onRegistered = onRegistered
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        bind()
        viewDidLoadSubject.onNext(())
    }

    override func configHierarchy() {
        view.addSubview(tableView)
        view.addSubview(statusLabel)
        view.addSubview(spinner)
    }

    override func configLayout() {
        tableView.snp.makeConstraints { make in
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
    }

    override func configView() {
        title = "운동화 검색"
        view.backgroundColor = AppColor.UI.backgroundGrouped
        definesPresentationContext = true

        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "브랜드 또는 모델명을 입력하세요"
        searchController.searchBar.returnKeyType = .search
        navigationItem.searchController = searchController

        tableView.register(GearCatalogCell.self, forCellReuseIdentifier: GearCatalogCell.reuseID)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.keyboardDismissMode = .onDrag

        statusLabel.font = AppFont.UI.bodyLG
        statusLabel.textColor = AppColor.UI.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
    }

    private func bind() {
        let input = ShoeSearchViewModel.Input(
            viewDidLoad: viewDidLoadSubject.asObservable(),
            query: searchController.searchBar.rx.searchButtonClicked
                .withLatestFrom(searchController.searchBar.rx.text.orEmpty)
                .asObservable(),
            selectItem: selectItemSubject.asObservable()
        )
        let output = viewModel.transform(input: input)

        output.results
            .drive(onNext: { [weak self] results in
                self?.results = results
                self?.tableView.reloadData()
            })
            .disposed(by: disposeBag)

        output.isLoading
            .drive(spinner.rx.isAnimating)
            .disposed(by: disposeBag)

        output.statusText
            .drive(statusLabel.rx.text)
            .disposed(by: disposeBag)

        output.selectedItem
            .emit(onNext: { [weak self] item in
                guard let self else { return }
                let viewController = RegisterShoeViewController(searchResult: item, onRegistered: self.onRegistered)
                self.navigationController?.pushViewController(viewController, animated: true)
            })
            .disposed(by: disposeBag)
    }
}

extension ShoeSearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: GearCatalogCell.reuseID, for: indexPath) as! GearCatalogCell
        cell.configure(with: results[indexPath.row], fallbackImageURL: brand?.logoURL)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        selectItemSubject.onNext(indexPath.row)
    }
}

private final class GearCatalogCell: HTTableViewCell {
    static let reuseID = "GearCatalogCell"

    private let cardView = HTView()
    private let shoeImageView = UIImageView()
    private let brandLabel = UILabel()
    private let modelLabel = UILabel()
    private let metaLabel = UILabel()
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
        imageTask = RemoteImageLoader.shared.loadImage(from: representative?.imageURL ?? item.thumbnailURL ?? fallbackImageURL) { [weak self] image in
            self?.shoeImageView.image = image ?? UIImage(systemName: "shoe")
            self?.shoeImageView.tintColor = AppColor.UI.textSecondary
        }
    }
}

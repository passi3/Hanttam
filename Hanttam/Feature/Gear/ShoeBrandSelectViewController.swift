//
//  ShoeBrandSelectViewController.swift
//  Hanttam
//
//  Created by passi on 4/10/26.
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class ShoeBrandSelectViewController: HTViewController {

    private let viewModel     : ShoeBrandSelectViewModel
    private let onRegistered  : ((RegisteredShoe) -> Void)?
    private let disposeBag    = DisposeBag()

    private let collectionView       = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let statusLabel          = UILabel()
    private let spinner              = UIActivityIndicatorView(style: .medium)
    private let manualRegisterButton = UIButton(type: .system)
    private let searchController     = UISearchController(searchResultsController: nil)

    private let viewDidLoadSubject = PublishSubject<Void>()
    private let selectItemSubject  = PublishSubject<Int>()
    private let itemSpacing: CGFloat = 12

    init(
        onRegistered: ((RegisteredShoe) -> Void)? = nil,
        service: BrandServicing = SupabaseShoeSearchService()
    ) {
        self.onRegistered = onRegistered
        self.viewModel = ShoeBrandSelectViewModel(service: service)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadSubject.onNext(())
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
        navigationItem.searchController = searchController

        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.minimumLineSpacing = itemSpacing
            layout.minimumInteritemSpacing = itemSpacing
            layout.sectionInset = UIEdgeInsets(top: 20, left: 20, bottom: 94, right: 20)
        }
        collectionView.register(BrandCell.self, forCellWithReuseIdentifier: BrandCell.reuseID)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true

        manualRegisterButton.setTitle("직접 등록", for: .normal)
        manualRegisterButton.titleLabel?.font = AppFont.UI.buttonMD
        manualRegisterButton.setTitleColor(AppColor.UI.textPrimary, for: .normal)
        manualRegisterButton.backgroundColor = AppColor.UI.cardBackground
        manualRegisterButton.layer.cornerRadius = 16
        manualRegisterButton.layer.borderWidth = 1
        manualRegisterButton.layer.borderColor = AppColor.UI.border.cgColor

        statusLabel.font = AppFont.UI.bodyLG
        statusLabel.textColor = AppColor.UI.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
    }

    override func setupBindings() {
        let searchText = searchController.searchBar.rx.text
            .orEmpty
            .distinctUntilChanged()
            .asObservable()

        let input = ShoeBrandSelectViewModel.Input(
            viewDidLoad: viewDidLoadSubject.asObservable(),
            searchText : searchText,
            selectItem : selectItemSubject.asObservable()
        )
        let output = viewModel.transform(input: input)

        output.filteredBrands
            .drive(collectionView.rx.items(cellIdentifier: BrandCell.reuseID, cellType: BrandCell.self)) { _, brand, cell in
                cell.configure(with: brand)
            }
            .disposed(by: disposeBag)

        output.isLoading
            .drive(spinner.rx.isAnimating)
            .disposed(by: disposeBag)

        output.statusText
            .drive(onNext: { [weak self] text in
                self?.statusLabel.text = text
                self?.statusLabel.isHidden = text == nil
            })
            .disposed(by: disposeBag)

        output.selectedBrand
            .emit(onNext: { [weak self] brand in
                guard let self else { return }
                let vc = ShoeSearchViewController(brand: brand, onRegistered: self.onRegistered)
                self.navigationController?.pushViewController(vc, animated: true)
            })
            .disposed(by: disposeBag)

        collectionView.rx.itemSelected
            .subscribe(onNext: { [weak self] indexPath in
                self?.selectItemSubject.onNext(indexPath.item)
            })
            .disposed(by: disposeBag)

        collectionView.rx.setDelegate(self)
            .disposed(by: disposeBag)

        manualRegisterButton.rx.tap
            .subscribe(onNext: { [weak self] in
                let vc = RegisterShoeViewController(mode: .manual, onRegistered: self?.onRegistered)
                self?.navigationController?.pushViewController(vc, animated: true)
            })
            .disposed(by: disposeBag)
    }
}

extension ShoeBrandSelectViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = floor((collectionView.bounds.width - 40 - itemSpacing * 2) / 3)
        return CGSize(width: width, height: 92)
    }
}

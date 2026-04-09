//
//  GearListViewController.swift
//  Hanttam
//
//  Created by passi on 4/8/26.
//

import UIKit
import RxCocoa
import RxSwift
import SnapKit

final class GearListViewController: HTViewController {
    private let viewModel: GearListViewModel
    private let viewDidLoadSubject = PublishSubject<Void>()
    private let refreshSubject = PublishSubject<Void>()
    private let addTapSubject = PublishSubject<Void>()
    private let selectItemSubject = PublishSubject<Int>()
    private let disposeBag = DisposeBag()

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyView = GearEmptyView()
    private var items: [GearListViewModel.Item] = []

    init(viewModel: GearListViewModel = GearListViewModel()) {
        self.viewModel = viewModel
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
        view.addSubview(emptyView)
    }

    override func configLayout() {
        tableView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        emptyView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(28)
        }
    }

    override func configView() {
        title = "장비"
        view.backgroundColor = AppColor.UI.backgroundGrouped
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addShoeTapped)
        )

        tableView.register(GearShoeCell.self, forCellReuseIdentifier: GearShoeCell.reuseID)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = AppColor.UI.backgroundGrouped
        tableView.separatorStyle = .none

        let refreshControl = UIRefreshControl()
        tableView.refreshControl = refreshControl
        refreshControl.rx.controlEvent(.valueChanged)
            .bind(to: refreshSubject)
            .disposed(by: disposeBag)
    }

    private func bind() {
        let output = viewModel.transform(
            input: .init(
                viewDidLoad: viewDidLoadSubject.asObservable(),
                refresh: refreshSubject.asObservable(),
                addTap: addTapSubject.asObservable(),
                selectItem: selectItemSubject.asObservable()
            )
        )

        output.items
            .drive(onNext: { [weak self] items in
                self?.items = items
                self?.tableView.reloadData()
            })
            .disposed(by: disposeBag)

        output.isLoading
            .drive(onNext: { [weak self] loading in
                if !loading {
                    self?.tableView.refreshControl?.endRefreshing()
                }
            })
            .disposed(by: disposeBag)

        output.isEmpty
            .drive(onNext: { [weak self] isEmpty in
                self?.emptyView.isHidden = !isEmpty
            })
            .disposed(by: disposeBag)

        output.showErrorMessage
            .emit(onNext: { [weak self] message in
                self?.showTransientMessage(message)
            })
            .disposed(by: disposeBag)

        output.showSearch
            .emit(onNext: { [weak self] in
                self?.navigationController?.pushViewController(ShoeSearchViewController(), animated: true)
            })
            .disposed(by: disposeBag)

        output.showDetail
            .emit(onNext: { [weak self] shoe in
                self?.navigationController?.pushViewController(ShoeDetailViewController(shoe: shoe), animated: true)
            })
            .disposed(by: disposeBag)
    }

    @objc private func addShoeTapped() {
        addTapSubject.onNext(())
    }

    private func showTransientMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak alert] in
            alert?.dismiss(animated: true)
        }
    }
}

extension GearListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: GearShoeCell.reuseID, for: indexPath) as! GearShoeCell
        cell.configure(with: items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        selectItemSubject.onNext(indexPath.row)
    }
}

private final class GearEmptyView: HTView {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override func configHierarchy() {
        addSubview(titleLabel)
        addSubview(detailLabel)
    }

    override func configLayout() {
        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        detailLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    override func configView() {
        titleLabel.text = "등록된 운동화가 없습니다"
        titleLabel.font = AppFont.UI.titleLG
        titleLabel.textColor = AppColor.UI.textPrimary
        titleLabel.textAlignment = .center

        detailLabel.text = "우측 상단 + 버튼으로 첫 운동화를 추가하세요."
        detailLabel.font = AppFont.UI.bodyLG
        detailLabel.textColor = AppColor.UI.textSecondary
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
    }
}

private final class GearShoeCell: HTTableViewCell {
    static let reuseID = "GearShoeCell"

    private let cardView = HTView()
    private let shoeImageView = UIImageView()
    private let brandLabel = UILabel()
    private let modelLabel = UILabel()
    private let summaryLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let progressLabel = UILabel()
    private var imageTask: URLSessionDataTask?

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        shoeImageView.image = UIImage(systemName: "shoeprints.fill")
    }

    override func configHierarchy() {
        contentView.addSubview(cardView)
        [shoeImageView, brandLabel, modelLabel, summaryLabel, progressView, progressLabel].forEach {
            cardView.addSubview($0)
        }
    }

    override func configLayout() {
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4))
        }
        shoeImageView.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(16)
            make.width.height.equalTo(76)
            make.bottom.lessThanOrEqualToSuperview().inset(16)
        }
        brandLabel.snp.makeConstraints { make in
            make.top.equalTo(shoeImageView)
            make.leading.equalTo(shoeImageView.snp.trailing).offset(14)
            make.trailing.equalToSuperview().inset(16)
        }
        modelLabel.snp.makeConstraints { make in
            make.top.equalTo(brandLabel.snp.bottom).offset(4)
            make.leading.trailing.equalTo(brandLabel)
        }
        summaryLabel.snp.makeConstraints { make in
            make.top.equalTo(modelLabel.snp.bottom).offset(8)
            make.leading.trailing.equalTo(brandLabel)
        }
        progressView.snp.makeConstraints { make in
            make.top.equalTo(summaryLabel.snp.bottom).offset(12)
            make.leading.trailing.equalTo(brandLabel)
            make.height.equalTo(8)
        }
        progressLabel.snp.makeConstraints { make in
            make.top.equalTo(progressView.snp.bottom).offset(6)
            make.trailing.equalTo(progressView)
            make.bottom.equalToSuperview().inset(18)
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

        shoeImageView.contentMode = .scaleAspectFill
        shoeImageView.clipsToBounds = true
        shoeImageView.layer.cornerRadius = 14
        shoeImageView.backgroundColor = AppColor.UI.backgroundSecondary
        shoeImageView.image = UIImage(systemName: "shoeprints.fill")
        shoeImageView.tintColor = AppColor.UI.textSecondary

        brandLabel.font = AppFont.UI.labelLG
        brandLabel.textColor = AppColor.UI.textSecondary

        modelLabel.font = AppFont.UI.titleMD
        modelLabel.textColor = AppColor.UI.textPrimary
        modelLabel.numberOfLines = 2

        summaryLabel.font = AppFont.UI.bodySM
        summaryLabel.textColor = AppColor.UI.textSecondary
        summaryLabel.numberOfLines = 2

        progressView.progressTintColor = AppColor.UI.primary
        progressView.trackTintColor = AppColor.UI.systemGray6
        progressView.layer.cornerRadius = 4
        progressView.clipsToBounds = true

        progressLabel.font = AppFont.UI.labelMD
        progressLabel.textColor = AppColor.UI.textSecondary
    }

    func configure(with item: GearListViewModel.Item) {
        brandLabel.text = item.shoe.brandName.uppercased()
        modelLabel.text = item.shoe.displayName
        summaryLabel.text = [
            AppFormatter.distance1f(item.stats.totalDistance),
            "세션 \(item.linkedSessionsCount)개"
        ].joined(separator: " · ")
        progressView.progress = Float(item.stats.progress)
        progressLabel.text = "\(AppFormatter.distance1f(item.stats.totalDistance)) / \(AppFormatter.distance1f(item.shoe.targetDistanceMeters))"
        imageTask = RemoteImageLoader.shared.loadImage(from: item.shoe.imageURL) { [weak self] image in
            self?.shoeImageView.image = image ?? UIImage(systemName: "shoeprints.fill")
            self?.shoeImageView.tintColor = AppColor.UI.textSecondary
        }
    }
}

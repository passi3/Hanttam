//
//  ShoeDetailViewController.swift
//  Hanttam
//
//  Created by passi on 4/8/26.
//

import UIKit
import RxCocoa
import RxSwift
import SnapKit

final class ShoeDetailViewController: HTViewController {
    private let viewModel: ShoeDetailViewModel
    private let variantService: ShoeCatalogVariantServicing
    private let store: GearLocalStoring
    private let initialShoe: RegisteredShoe
    private let viewDidLoadSubject = PublishSubject<Void>()
    private let disposeBag = DisposeBag()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private let headerView: GearDetailHeaderView
    private let summaryCardView = GearStatsCardView()
    private let sessionsHeaderLabel = UILabel()
    private let sessionsStackView = UIStackView()
    private let emptySessionsLabel = UILabel()

    private var currentViewData: ShoeDetailViewModel.ViewData?

    init(
        shoe: RegisteredShoe,
        variantService: ShoeCatalogVariantServicing = SupabaseShoeSearchService(),
        store: GearLocalStoring = GearLocalStore.shared
    ) {
        self.initialShoe = shoe
        self.viewModel = ShoeDetailViewModel(shoe: shoe)
        self.variantService = variantService
        self.store = store
        self.headerView = GearDetailHeaderView(shoe: shoe)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        bind()
        viewDidLoadSubject.onNext(())
    }

    override func configHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)
        [headerView, summaryCardView, sessionsHeaderLabel, sessionsStackView, emptySessionsLabel].forEach {
            stackView.addArrangedSubview($0)
        }
    }

    override func configLayout() {
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.snp.width)
        }
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 20, left: 20, bottom: 32, right: 20))
        }
    }

    override func configView() {
        title = initialShoe.displayName
        view.backgroundColor = AppColor.UI.backgroundGrouped

        let editButton = UIBarButtonItem(
            title: "수정",
            style: .plain,
            target: self,
            action: #selector(editButtonTapped)
        )
        editButton.tintColor = AppColor.UI.textPrimary

        let deleteButton = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(deleteButtonTapped)
        )
        deleteButton.tintColor = AppColor.UI.red
        navigationItem.rightBarButtonItems = [deleteButton, editButton]

        stackView.axis = .vertical
        stackView.spacing = 18

        sessionsHeaderLabel.font = AppFont.UI.titleMD
        sessionsHeaderLabel.textColor = AppColor.UI.textPrimary
        sessionsHeaderLabel.text = "연결된 워크아웃"

        sessionsStackView.axis = .vertical
        sessionsStackView.spacing = 12

        emptySessionsLabel.font = AppFont.UI.bodyMD
        emptySessionsLabel.textColor = AppColor.UI.textSecondary
        emptySessionsLabel.text = "아직 연결된 워크아웃이 없습니다."
        emptySessionsLabel.numberOfLines = 0
        emptySessionsLabel.textAlignment = .center
        emptySessionsLabel.isHidden = true
    }

    private func bind() {
        let output = viewModel.transform(
            input: .init(
                viewDidLoad: viewDidLoadSubject.asObservable()
            )
        )

        output.viewData
            .drive(onNext: { [weak self] viewData in
                guard let self else { return }
                currentViewData = viewData
                title = viewData.shoe.displayName
                headerView.configure(with: viewData.shoe, stats: viewData.stats)
                summaryCardView.configure(
                    with: viewData.shoe,
                    stats: viewData.stats,
                    sessionsCount: viewData.sessions.count
                )
                renderSessions(viewData.sessions)
            })
            .disposed(by: disposeBag)

        output.showErrorMessage
            .emit(onNext: { [weak self] message in
                self?.showTransientMessage(message)
            })
            .disposed(by: disposeBag)
    }

    @objc private func editButtonTapped() {
        let shoe = currentViewData?.shoe ?? initialShoe
        let viewController = ShoeEditViewController(
            shoe: shoe,
            variantService: variantService,
            store: store
        )
        navigationController?.pushViewController(viewController, animated: true)
    }

    @objc private func deleteButtonTapped() {
        let shoe = currentViewData?.shoe ?? initialShoe
        let sessionsCount = currentViewData?.sessions.count ?? 0
        let message: String
        if sessionsCount > 0 {
            message = "이 운동화를 삭제하면 연결된 워크아웃 \(sessionsCount)개의 장비 연결도 해제됩니다. 워크아웃 기록은 삭제되지 않습니다."
        } else {
            message = "이 운동화를 삭제하시겠습니까?"
        }

        let alert = UIAlertController(title: "운동화 삭제", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "삭제", style: .destructive) { [weak self] _ in
            guard let self else { return }
            store.deleteRegisteredShoe(id: shoe.id)
            navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    private func renderSessions(_ sessions: [GearLinkedSessionItem]) {
        sessionsStackView.arrangedSubviews.forEach { view in
            sessionsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        emptySessionsLabel.isHidden = !sessions.isEmpty
        sessionsStackView.isHidden = sessions.isEmpty

        sessions.forEach { session in
            let rowView = GearSessionRowView()
            rowView.configure(with: session)
            rowView.onTap = { [weak self] in
                self?.presentRunDetail(for: session)
            }
            sessionsStackView.addArrangedSubview(rowView)
        }
    }

    private func presentRunDetail(for session: GearLinkedSessionItem) {
        guard let record = session.runningRecord else {
            showTransientMessage("워크아웃 상세 데이터를 불러올 수 없습니다.")
            return
        }

        let viewController: RunDetailTabViewController
        if let intervalRecord = session.intervalRecord {
            viewController = RunDetailTabViewController(record: record, intervalRecord: intervalRecord)
        } else {
            viewController = RunDetailTabViewController(record: record)
        }
        present(viewController, animated: true)
    }

    private func showTransientMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak alert] in
            alert?.dismiss(animated: true)
        }
    }
}


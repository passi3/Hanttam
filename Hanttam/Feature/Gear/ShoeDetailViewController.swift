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

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "수정",
            style: .plain,
            target: self,
            action: #selector(editButtonTapped)
        )
        navigationItem.rightBarButtonItem?.tintColor = AppColor.UI.textPrimary

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

private final class GearDetailHeaderView: HTView {
    private let distanceValueLabel = UILabel()
    private let distanceUnitLabel = UILabel()
    private let shoeImageView = UIImageView()
    private let progressLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)

    private var imageTask: URLSessionDataTask?
    private var currentImageURL: String?
    private let shoe: RegisteredShoe

    init(shoe: RegisteredShoe) {
        self.shoe = shoe
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func configHierarchy() {
        [distanceValueLabel, distanceUnitLabel, shoeImageView, progressLabel, progressView].forEach { addSubview($0) }
    }

    override func configLayout() {
        distanceValueLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(28)
            make.centerX.equalToSuperview()
        }
        distanceUnitLabel.snp.makeConstraints { make in
            make.top.equalTo(distanceValueLabel.snp.bottom).offset(-18)
            make.centerX.equalToSuperview()
        }
        shoeImageView.snp.makeConstraints { make in
            make.top.equalTo(distanceUnitLabel.snp.top).offset(16)
            make.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(220)
        }
        progressLabel.snp.makeConstraints { make in
            make.top.equalTo(shoeImageView.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        progressView.snp.makeConstraints { make in
            make.top.equalTo(progressLabel.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(24)
            make.height.equalTo(8)
        }
    }

    override func configView() {
        backgroundColor = AppColor.UI.cardBackground
        layer.cornerRadius = 28
        layer.borderWidth = 1
        layer.borderColor = AppColor.UI.border.cgColor

        distanceValueLabel.font = UIFont.systemFont(ofSize: 70, weight: .black)
        distanceValueLabel.textColor = .black
        distanceValueLabel.textAlignment = .center

        distanceUnitLabel.font = UIFont.systemFont(ofSize: 70, weight: .black)
        distanceUnitLabel.textColor = .black
        distanceUnitLabel.text = "KM"
        distanceUnitLabel.textAlignment = .center

        shoeImageView.contentMode = .scaleAspectFit
        shoeImageView.image = UIImage(systemName: "shoeprints.fill")
        shoeImageView.tintColor = AppColor.UI.textSecondary

        progressLabel.font = AppFont.UI.headlineSM
        progressLabel.textColor = AppColor.UI.textPrimary
        progressLabel.textAlignment = .center
        progressLabel.numberOfLines = 0

        progressView.trackTintColor = AppColor.UI.border
        progressView.progressTintColor = RunningLevelManager.shared.accentUIColor
        progressView.layer.cornerRadius = 4
        progressView.clipsToBounds = true
    }

    func configure(with shoe: RegisteredShoe, stats: ShoeAggregateStats) {
        distanceValueLabel.text = formattedDistanceText(for: stats.totalDistance)

        if stats.overDistance > 0 {
            progressLabel.text = "목표 \(AppFormatter.distance1f(shoe.targetDistanceMeters)) 초과 · +\(AppFormatter.distance1f(stats.overDistance))"
        } else {
            let remainingDistance = max(shoe.targetDistanceMeters - stats.totalDistance, 0)
            progressLabel.text = "목표 달성까지 \(AppFormatter.distance1f(remainingDistance))"
        }

        progressView.progress = Float(stats.progress)

        if currentImageURL != shoe.imageURL {
            currentImageURL = shoe.imageURL
            imageTask?.cancel()
            imageTask = RemoteImageLoader.shared.loadImage(from: shoe.imageURL) { [weak self] image in
                self?.shoeImageView.image = image ?? UIImage(systemName: "shoeprints.fill")
                self?.shoeImageView.tintColor = AppColor.UI.textSecondary
            }
        }
    }

    private func formattedDistanceText(for distanceMeters: Double) -> String {
        let distanceKilometers = distanceMeters / 1000.0
        let rounded = (distanceKilometers * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.05 {
            return "\(Int(rounded.rounded()))"
        }
        return String(format: "%.1f", rounded)
    }
}

private final class GearStatsCardView: HTView {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let metricsStackView = UIStackView()
    private let runsMetricView = GearMetricView()
    private let paceMetricView = GearMetricView()
    private let durationMetricView = GearMetricView()

    override func configHierarchy() {
        [titleLabel, subtitleLabel, metricsStackView].forEach { addSubview($0) }
        [runsMetricView, paceMetricView, durationMetricView].forEach { metricsStackView.addArrangedSubview($0) }
    }

    override func configLayout() {
        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(24)
        }
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        metricsStackView.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(24)
            make.leading.trailing.bottom.equalToSuperview().inset(24)
        }
    }

    override func configView() {
        backgroundColor = AppColor.UI.cardBackground
        layer.cornerRadius = 24
        layer.borderWidth = 1
        layer.borderColor = AppColor.UI.border.cgColor

        titleLabel.font = AppFont.UI.headlineSM
        titleLabel.textColor = AppColor.UI.textPrimary
        titleLabel.numberOfLines = 2

        subtitleLabel.font = AppFont.UI.bodyMD
        subtitleLabel.textColor = AppColor.UI.textSecondary
        subtitleLabel.numberOfLines = 2

        metricsStackView.axis = .horizontal
        metricsStackView.distribution = .fillEqually
        metricsStackView.spacing = 12
    }

    func configure(with shoe: RegisteredShoe, stats: ShoeAggregateStats, sessionsCount: Int) {
        titleLabel.text = "\(shoe.brandName) \(shoe.modelName)"

        var metaParts: [String] = []
        if shoe.displayName != shoe.modelName {
            metaParts.append("별칭: \(shoe.displayName)")
        }
        if !shoe.colors.isEmpty {
            metaParts.append(shoe.colors.joined(separator: ", "))
        }
        subtitleLabel.text = metaParts.isEmpty ? shoe.sku : metaParts.joined(separator: "\n")

        runsMetricView.configure(value: "\(sessionsCount)", title: "러닝")
        paceMetricView.configure(value: GearFormatters.pace(stats.averagePace), title: "평균 페이스")
        durationMetricView.configure(value: GearFormatters.duration(stats.totalDuration), title: "시간")
    }
}

private final class GearMetricView: HTView {
    private let valueLabel = UILabel()
    private let titleLabel = UILabel()

    override func configHierarchy() {
        [valueLabel, titleLabel].forEach { addSubview($0) }
    }

    override func configLayout() {
        valueLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(valueLabel.snp.bottom).offset(6)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    override func configView() {
        valueLabel.font = AppFont.UI.metricLabel
        valueLabel.textColor = AppColor.UI.textPrimary
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        titleLabel.font = AppFont.UI.bodyMD
        titleLabel.textColor = AppColor.UI.textSecondary
        titleLabel.textAlignment = .center
    }

    func configure(value: String, title: String) {
        valueLabel.text = value
        titleLabel.text = title
    }
}

private final class GearSessionRowView: HTView {
    private let button = UIButton(type: .system)
    private let kindLabel = UILabel()
    private let dateLabel = UILabel()
    private let valueLabel = UILabel()
    var onTap: (() -> Void)?

    override func configHierarchy() {
        addSubview(button)
        [kindLabel, dateLabel, valueLabel].forEach { button.addSubview($0) }
    }

    override func configLayout() {
        button.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        kindLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(16)
            make.trailing.lessThanOrEqualTo(valueLabel.snp.leading).offset(-12)
        }
        dateLabel.snp.makeConstraints { make in
            make.top.equalTo(kindLabel.snp.bottom).offset(6)
            make.leading.bottom.equalToSuperview().inset(16)
            make.trailing.lessThanOrEqualTo(valueLabel.snp.leading).offset(-12)
        }
        valueLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().inset(16)
        }
    }

    override func configView() {
        button.backgroundColor = AppColor.UI.cardBackground
        button.layer.cornerRadius = 18
        button.layer.borderWidth = 1
        button.layer.borderColor = AppColor.UI.border.cgColor
        button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)

        kindLabel.font = AppFont.UI.titleSM
        kindLabel.textColor = AppColor.UI.textPrimary

        dateLabel.font = AppFont.UI.bodySM
        dateLabel.textColor = AppColor.UI.textSecondary

        valueLabel.font = AppFont.UI.metricCaption
        valueLabel.textColor = AppColor.UI.textPrimary
        valueLabel.numberOfLines = 2
        valueLabel.textAlignment = .right
    }

    func configure(with session: GearLinkedSessionItem) {
        kindLabel.text = session.title
        dateLabel.text = AppFormatter.recordDate.string(from: session.startedAt)
        valueLabel.text = "\(AppFormatter.distance1f(session.distance))\n\(GearFormatters.duration(session.duration))"
    }

    @objc private func handleTap() {
        onTap?()
    }
}

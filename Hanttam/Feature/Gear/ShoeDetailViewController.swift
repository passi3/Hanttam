//
//  ShoeDetailViewController.swift
//  Hanttam
//
//  Created by Codex on 4/8/26.
//

import UIKit
import RxCocoa
import RxSwift
import SnapKit

final class ShoeDetailViewController: HTViewController {
    private let viewModel: ShoeDetailViewModel
    private let viewDidLoadSubject = PublishSubject<Void>()
    private let selectSessionSubject = PublishSubject<Int>()
    private let disposeBag = DisposeBag()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private let headerView: GearDetailHeaderView
    private let statsCardView = GearStatsCardView()
    private let sessionsHeaderLabel = UILabel()
    private let sessionsStackView = UIStackView()
    private let emptySessionsLabel = UILabel()

    private var sessions: [GearLinkedSessionItem] = []

    init(shoe: RegisteredShoe) {
        let viewModel = ShoeDetailViewModel(shoe: shoe)
        self.viewModel = viewModel
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
        [headerView, statsCardView, sessionsHeaderLabel, sessionsStackView, emptySessionsLabel].forEach {
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
        title = "운동화 상세"
        view.backgroundColor = AppColor.UI.backgroundGrouped

        stackView.axis = .vertical
        stackView.spacing = 18

        sessionsHeaderLabel.font = AppFont.UI.titleMD
        sessionsHeaderLabel.textColor = AppColor.UI.textPrimary
        sessionsHeaderLabel.text = "연결된 세션"

        sessionsStackView.axis = .vertical
        sessionsStackView.spacing = 12

        emptySessionsLabel.font = AppFont.UI.bodyMD
        emptySessionsLabel.textColor = AppColor.UI.textSecondary
        emptySessionsLabel.text = "아직 연결된 세션이 없습니다."
        emptySessionsLabel.numberOfLines = 0
        emptySessionsLabel.textAlignment = .center
        emptySessionsLabel.isHidden = true
    }

    private func bind() {
        let output = viewModel.transform(
            input: .init(
                viewDidLoad: viewDidLoadSubject.asObservable(),
                selectSession: selectSessionSubject.asObservable()
            )
        )

        output.viewData
            .drive(onNext: { [weak self] viewData in
                self?.headerView.configure(with: viewData.shoe, stats: viewData.stats)
                self?.statsCardView.configure(with: viewData.stats)
                self?.renderSessions(viewData.sessions)
            })
            .disposed(by: disposeBag)

        output.showErrorMessage
            .emit(onNext: { [weak self] message in
                self?.showTransientMessage(message)
            })
            .disposed(by: disposeBag)

        output.showSessionDetail
            .emit(onNext: { [weak self] target in
                switch target {
                case .freeRun(let record):
                    self?.navigationController?.pushViewController(RunDetailTabViewController(record: record), animated: true)
                case .interval(let record, let intervalRecord):
                    self?.navigationController?.pushViewController(
                        RunDetailTabViewController(record: record, intervalRecord: intervalRecord),
                        animated: true
                    )
                }
            })
            .disposed(by: disposeBag)
    }

    private func renderSessions(_ sessions: [GearLinkedSessionItem]) {
        self.sessions = sessions
        sessionsStackView.arrangedSubviews.forEach { view in
            sessionsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        emptySessionsLabel.isHidden = !sessions.isEmpty
        sessionsStackView.isHidden = sessions.isEmpty

        sessions.enumerated().forEach { index, session in
            let rowView = GearSessionRowView()
            rowView.configure(with: session)
            rowView.onTap = { [weak self] in
                self?.selectSessionSubject.onNext(index)
            }
            sessionsStackView.addArrangedSubview(rowView)
        }
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
    private let shoeImageView = UIImageView()
    private let brandLabel = UILabel()
    private let modelLabel = UILabel()
    private let metaLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private var imageTask: URLSessionDataTask?
    private let shoe: RegisteredShoe

    init(shoe: RegisteredShoe) {
        self.shoe = shoe
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func configHierarchy() {
        [shoeImageView, brandLabel, modelLabel, metaLabel, progressLabel, progressView].forEach { addSubview($0) }
    }

    override func configLayout() {
        shoeImageView.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(20)
            make.width.height.equalTo(116)
        }
        brandLabel.snp.makeConstraints { make in
            make.top.equalTo(shoeImageView)
            make.leading.equalTo(shoeImageView.snp.trailing).offset(16)
            make.trailing.equalToSuperview().inset(20)
        }
        modelLabel.snp.makeConstraints { make in
            make.top.equalTo(brandLabel.snp.bottom).offset(6)
            make.leading.trailing.equalTo(brandLabel)
        }
        metaLabel.snp.makeConstraints { make in
            make.top.equalTo(modelLabel.snp.bottom).offset(10)
            make.leading.trailing.equalTo(brandLabel)
        }
        progressLabel.snp.makeConstraints { make in
            make.top.equalTo(shoeImageView.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        progressView.snp.makeConstraints { make in
            make.top.equalTo(progressLabel.snp.bottom).offset(10)
            make.leading.trailing.bottom.equalToSuperview().inset(20)
            make.height.equalTo(10)
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

        brandLabel.font = AppFont.UI.labelLG
        brandLabel.textColor = AppColor.UI.textSecondary

        modelLabel.font = AppFont.UI.headlineSM
        modelLabel.textColor = AppColor.UI.textPrimary
        modelLabel.numberOfLines = 2

        metaLabel.font = AppFont.UI.bodySM
        metaLabel.textColor = AppColor.UI.textSecondary
        metaLabel.numberOfLines = 2

        progressLabel.font = AppFont.UI.bodyMD
        progressLabel.textColor = AppColor.UI.textPrimary

        progressView.trackTintColor = AppColor.UI.systemGray6
        progressView.progressTintColor = AppColor.UI.primary
        progressView.layer.cornerRadius = 5
        progressView.clipsToBounds = true
    }

    func configure(with shoe: RegisteredShoe, stats: ShoeAggregateStats) {
        brandLabel.text = shoe.brandName.uppercased()
        modelLabel.text = shoe.modelName
        metaLabel.text = [shoe.sku, shoe.colors.joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: "\n")
        if stats.overDistance > 0 {
            progressLabel.text = "\(AppFormatter.distance1f(stats.totalDistance)) / \(AppFormatter.distance1f(shoe.targetDistanceMeters)) · +\(AppFormatter.distance1f(stats.overDistance)) 초과"
        } else {
            progressLabel.text = "\(AppFormatter.distance1f(stats.totalDistance)) / \(AppFormatter.distance1f(shoe.targetDistanceMeters))"
        }
        progressView.progress = Float(stats.progress)
        imageTask?.cancel()
        imageTask = RemoteImageLoader.shared.loadImage(from: shoe.imageURL) { [weak self] image in
            self?.shoeImageView.image = image ?? UIImage(systemName: "shoeprints.fill")
            self?.shoeImageView.tintColor = AppColor.UI.textSecondary
        }
    }
}

private final class GearStatsCardView: HTView {
    private let distanceMetric = GearMetricView()
    private let durationMetric = GearMetricView()
    private let paceMetric = GearMetricView()

    override func configHierarchy() {
        [distanceMetric, durationMetric, paceMetric].forEach { addSubview($0) }
    }

    override func configLayout() {
        distanceMetric.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        durationMetric.snp.makeConstraints { make in
            make.top.equalTo(distanceMetric.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview()
        }
        paceMetric.snp.makeConstraints { make in
            make.top.equalTo(durationMetric.snp.bottom).offset(12)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    func configure(with stats: ShoeAggregateStats) {
        distanceMetric.configure(title: "총 거리", value: AppFormatter.distance1f(stats.totalDistance))
        durationMetric.configure(title: "총 시간", value: GearFormatters.duration(stats.totalDuration))
        paceMetric.configure(title: "평균 페이스", value: GearFormatters.pace(stats.averagePace))
    }
}

private final class GearMetricView: HTView {
    private let cardView = HTView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    override func configHierarchy() {
        addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(valueLabel)
    }

    override func configLayout() {
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        titleLabel.snp.makeConstraints { make in
            make.top.leading.bottom.equalToSuperview().inset(16)
        }
        valueLabel.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.trailing.equalToSuperview().inset(16)
        }
    }

    override func configView() {
        cardView.backgroundColor = AppColor.UI.cardBackground
        cardView.layer.cornerRadius = 18
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = AppColor.UI.border.cgColor

        titleLabel.font = AppFont.UI.bodyMD
        titleLabel.textColor = AppColor.UI.textSecondary

        valueLabel.font = AppFont.UI.metricLabel
        valueLabel.textColor = AppColor.UI.textPrimary
    }

    func configure(title: String, value: String) {
        titleLabel.text = title
        valueLabel.text = value
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
        button.addTarget(self, action: #selector(didTap), for: .touchUpInside)

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

    @objc private func didTap() {
        onTap?()
    }
}

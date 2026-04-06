//
//  RunDetailViewController.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import UIKit
import SwiftUI
import Combine
import SnapKit

final class RunDetailViewController: UIViewController {

    private let viewModel: RunDetailViewModel
    private let viewDidLoadSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    private let record: RunningRecord
    private var detailData: RunDetailViewModel.DetailData?

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let mapContainer = UIView()
    private var mapHeightConstraint: Constraint?
    private let contentStack = UIStackView()
    private let loadingView = UIView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    init(record: RunningRecord) {
        self.record = record
        self.viewModel = RunDetailViewModel(record: record)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bind()
        viewDidLoadSubject.send(())
    }

    // MARK: - Bind

    private func bind() {
        let input = RunDetailViewModel.Input(
            viewDidLoad: viewDidLoadSubject.eraseToAnyPublisher()
        )
        let output = viewModel.transform(input: input)

        output.isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                self?.loadingView.isHidden = !loading
                if loading {
                    self?.loadingIndicator.startAnimating()
                } else {
                    self?.loadingIndicator.stopAnimating()
                }
            }
            .store(in: &cancellables)

        output.data
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.detailData = data
                self?.buildContent(with: data)
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup UI

    private func setupUI() {
        title = "러닝 상세"
        view.backgroundColor = AppColor.UI.backgroundGrouped

        // Scroll View
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // 맵 컨테이너 (최상단, edge-to-edge)
        scrollView.addSubview(mapContainer)

        contentStack.axis = .vertical
        contentStack.spacing = RunDetailLayout.sectionSpacing
        scrollView.addSubview(contentStack)

        mapContainer.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.trailing.equalTo(view)
            self.mapHeightConstraint = make.height.equalTo(0).constraint
        }

        contentStack.snp.makeConstraints { make in
            make.top.equalTo(mapContainer.snp.bottom).offset(RunDetailLayout.horizontalInset)
            make.leading.trailing.equalTo(view).inset(RunDetailLayout.horizontalInset)
            make.bottom.equalToSuperview().offset(-(RunDetailLayout.bottomInset + 16))
        }

        // Loading
        loadingView.backgroundColor = AppColor.UI.backgroundGrouped.withAlphaComponent(0.7)
        view.addSubview(loadingView)
        loadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        loadingIndicator.color = RunningLevelManager.shared.accentUIColor
        loadingView.addSubview(loadingIndicator)
        loadingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        // 네비게이션 바
        navigationController?.navigationBar.barTintColor = AppColor.UI.backgroundGrouped
        navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: AppColor.UI.textPrimary,
            .font: AppFont.UI.titleMD
        ]

        // 사진 공유 버튼
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "photo.badge.plus"),
            style: .plain,
            target: self,
            action: #selector(shareTapped)
        )
        navigationItem.rightBarButtonItem?.tintColor = AppColor.UI.textSecondary
    }

    // MARK: - Build Content

    private func buildContent(with data: RunDetailViewModel.DetailData) {
        // 기존 맵 제거
        mapContainer.subviews.forEach { $0.removeFromSuperview() }
        children.filter { $0.view.superview == mapContainer }.forEach {
            $0.willMove(toParent: nil)
            $0.removeFromParent()
        }
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // 루트 맵 (최상단, edge-to-edge)
        if data.altPoints.count >= 2 {
            let mapView = RunDetailContentView.RouteMapSection(
                altPoints: data.altPoints,
                record: record
            )
            let hosting = UIHostingController(rootView: mapView)
            hosting.view.backgroundColor = .clear
            addChild(hosting)
            mapContainer.addSubview(hosting.view)
            hosting.view.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            hosting.didMove(toParent: self)
            mapHeightConstraint?.update(offset: 240)
        } else {
            mapHeightConstraint?.update(offset: 0)
        }

        // 요약 히어로
        embedSwiftUI(RunDetailContentView.SectionHeader(title: "OVERVIEW", icon: "figure.run"), height: 24)
        let summaryView = RunDetailContentView.SummaryHeroSection(
            record: record,
            heartRates: data.heartRates,
            data: data
        )
        embedSwiftUI(summaryView, height: nil)

        // 랩별 페이스
        if !data.lapRows.isEmpty {
            embedSwiftUI(RunDetailContentView.SectionHeader(title: "SPLITS", icon: "chart.bar"), height: 24)
            let splitChart = RunDetailContentView.SplitPaceSection(
                lapRows: data.lapRows,
                speedSamples: data.speedSamples
            )
            embedSwiftUI(splitChart, height: 320)
        }

        // 통합 차트
        let chartHelper = RunDetailContentView.ChartHelper(record: record, data: data)
        let combinedChart = RunDetailContentView.CombinedChartSection(
            paceData: chartHelper.timeSeries(for: .pace),
            hrData: chartHelper.timeSeries(for: .heartRate),
            altData: chartHelper.timeSeries(for: .altitude),
            selectedElapsed: .constant(nil)
        )
        embedSwiftUI(RunDetailContentView.SectionHeader(title: "TRACKING", icon: "map"), height: 24)
        embedSwiftUI(combinedChart, height: 320)

        // 개별 차트
        let combined: Set<String> = ["페이스", "심박수", "고도"]
        for metric in MetricType.allCases where !combined.contains(metric.title) {
            let ts = chartHelper.timeSeries(for: metric)
            if !ts.isEmpty {
                let card = RunDetailContentView.TimeSeriesSection(metric: metric, data: ts)
                embedSwiftUI(card, height: 260)
            }
        }
    }

    private func embedSwiftUI<V: View>(_ swiftUIView: V, height: CGFloat?) {
        let hosting = UIHostingController(rootView: swiftUIView)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        contentStack.addArrangedSubview(hosting.view)
        if let h = height {
            hosting.view.snp.makeConstraints { make in
                make.height.equalTo(h)
            }
        }
        hosting.didMove(toParent: self)
    }

    // MARK: - Share

    @objc private func shareTapped() {
        guard let data = detailData else { return }
        let chartHelper = RunDetailContentView.ChartHelper(record: record, data: data)
        let avgPace: TimeInterval = record.distance > 0
            ? record.duration / (record.distance / 1000) : 0
        let paceData = chartHelper.timeSeries(for: .pace)
        let rec = record

        let shareView = ChartPhotoShareView {
            RunDetailContentView.RunShareOverlay(
                record: rec,
                avgPace: avgPace,
                paceData: paceData
            )
        }
        let vc = UIHostingController(rootView: shareView)
        vc.view.backgroundColor = AppColor.UI.backgroundGrouped
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(vc, animated: true)
    }
}

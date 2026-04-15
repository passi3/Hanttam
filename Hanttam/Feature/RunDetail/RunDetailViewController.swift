//
//  RunDetailViewController.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import UIKit
import SwiftUI
import RxSwift
import RxCocoa
import SnapKit

final class RunDetailViewController: HTViewController {

    private let viewModel: RunDetailViewModel
    private let viewDidLoadSubject = PublishSubject<Void>()
    private let disposeBag = DisposeBag()

    private let record: RunningRecord
    private var detailData: RunDetailViewModel.DetailData?

    // MARK: - UI

    private let scrollView   = UIScrollView()
    private let mapContainer = UIView()
    private var mapHeightConstraint: Constraint?
    private let contentStack = UIStackView()
    private let loadingView  = UIView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    init(record: RunningRecord) {
        self.record    = record
        self.viewModel = RunDetailViewModel(record: record)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadSubject.onNext(())
    }

    override func configHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(mapContainer)
        scrollView.addSubview(contentStack)
        loadingView.addSubview(loadingIndicator)
        view.addSubview(loadingView)
    }

    override func configLayout() {
        scrollView.snp.makeConstraints { make in make.edges.equalToSuperview() }
        mapContainer.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.trailing.equalTo(view)
            mapHeightConstraint = make.height.equalTo(0).constraint
        }
        contentStack.snp.makeConstraints { make in
            make.top.equalTo(mapContainer.snp.bottom).offset(RunDetailLayout.horizontalInset)
            make.leading.trailing.equalTo(view).inset(RunDetailLayout.horizontalInset)
            make.bottom.equalToSuperview().offset(-(RunDetailLayout.bottomInset + 16))
        }
        loadingView.snp.makeConstraints { make in make.edges.equalToSuperview() }
        loadingIndicator.snp.makeConstraints { make in make.center.equalToSuperview() }
    }

    override func configView() {
        title = "러닝 상세"
        view.backgroundColor = AppColor.UI.backgroundGrouped
        contentStack.axis = .vertical
        contentStack.spacing = RunDetailLayout.sectionSpacing

        loadingView.backgroundColor = AppColor.UI.backgroundGrouped.withAlphaComponent(0.7)
        loadingIndicator.color = RunningLevelManager.shared.accentUIColor

        navigationController?.navigationBar.barTintColor = AppColor.UI.backgroundGrouped
        navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: AppColor.UI.textPrimary,
            .font: AppFont.UI.titleMD
        ]

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "photo.badge.plus"),
            style: .plain,
            target: self,
            action: #selector(shareTapped)
        )
        navigationItem.rightBarButtonItem?.tintColor = AppColor.UI.textSecondary
    }

    override func setupBindings() {
        let input = RunDetailViewModel.Input(viewDidLoad: viewDidLoadSubject.asObservable())
        let output = viewModel.transform(input: input)

        output.isLoading
            .drive(onNext: { [weak self] loading in
                self?.loadingView.isHidden = !loading
                loading ? self?.loadingIndicator.startAnimating() : self?.loadingIndicator.stopAnimating()
            })
            .disposed(by: disposeBag)

        output.data
            .drive(onNext: { [weak self] data in
                self?.detailData = data
                self?.buildContent(with: data)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Build Content

    private func buildContent(with data: RunDetailViewModel.DetailData) {
        mapContainer.subviews.forEach { $0.removeFromSuperview() }
        children.filter { $0.view.superview == mapContainer }.forEach {
            $0.willMove(toParent: nil); $0.removeFromParent()
        }
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if data.altPoints.count >= 2 {
            let mapView = RunDetailContentView.RouteMapSection(altPoints: data.altPoints, record: record)
            embedSwiftUI(mapView, in: mapContainer)
            mapHeightConstraint?.update(offset: 240)
        } else {
            mapHeightConstraint?.update(offset: 0)
        }

        embedSwiftUI(RunDetailContentView.SectionHeader(title: "OVERVIEW", icon: "figure.run"), height: 24)
        embedSwiftUI(RunDetailContentView.SummaryHeroSection(record: record, heartRates: data.heartRates, data: data))

        if !data.lapRows.isEmpty {
            embedSwiftUI(RunDetailContentView.SectionHeader(title: "SPLITS", icon: "chart.bar"), height: 24)
            embedSwiftUI(RunDetailContentView.SplitPaceSection(lapRows: data.lapRows, speedSamples: data.speedSamples), height: 320)
        }

        let chartHelper = RunDetailContentView.ChartHelper(record: record, data: data)
        embedSwiftUI(RunDetailContentView.SectionHeader(title: "TRACKING", icon: "map"), height: 24)
        embedSwiftUI(RunDetailContentView.CombinedChartSection(
            paceData: chartHelper.timeSeries(for: .pace),
            hrData: chartHelper.timeSeries(for: .heartRate),
            altData: chartHelper.timeSeries(for: .altitude),
            selectedElapsed: .constant(nil)
        ), height: 320)

        let combined: Set<String> = ["페이스", "심박수", "고도"]
        for metric in MetricType.allCases where !combined.contains(metric.title) {
            let ts = chartHelper.timeSeries(for: metric)
            if !ts.isEmpty { embedSwiftUI(RunDetailContentView.TimeSeriesSection(metric: metric, data: ts), height: 260) }
        }
    }

    private func embedSwiftUI<V: View>(_ view: V, height: CGFloat? = nil) {
        let hosting = UIHostingController(rootView: view)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        contentStack.addArrangedSubview(hosting.view)
        if let h = height { hosting.view.snp.makeConstraints { make in make.height.equalTo(h) } }
        hosting.didMove(toParent: self)
    }

    private func embedSwiftUI<V: View>(_ view: V, in container: UIView) {
        let hosting = UIHostingController(rootView: view)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        container.addSubview(hosting.view)
        hosting.view.snp.makeConstraints { make in make.edges.equalToSuperview() }
        hosting.didMove(toParent: self)
    }

    // MARK: - Share

    @objc private func shareTapped() {
        guard let data = detailData else { return }
        let chartHelper = RunDetailContentView.ChartHelper(record: record, data: data)
        let avgPace: TimeInterval = record.distance > 0 ? record.duration / (record.distance / 1000) : 0
        let shareView = ChartPhotoShareView {
            RunDetailContentView.RunShareOverlay(record: self.record, avgPace: avgPace, paceData: chartHelper.timeSeries(for: .pace))
        }
        let vc = UIHostingController(rootView: shareView)
        vc.modalPresentationStyle = .fullScreen
        vc.view.backgroundColor = AppColor.UI.backgroundGrouped
        present(vc, animated: true)
    }
}

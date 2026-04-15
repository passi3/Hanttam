//
//  RunDetailTrackingViewController.swift
//  Hanttam
//

import UIKit
import SwiftUI
import RxSwift
import RxCocoa
import SnapKit

class RunDetailTrackingViewController: UIViewController {
    private let record: RunningRecord
    private let viewModel: RunDetailViewModel
    private let disposeBag = DisposeBag()
    private let contentStack = UIStackView()

    init(record: RunningRecord, viewModel: RunDetailViewModel) {
        self.record = record
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bind()
    }

    private func setupUI() {
        view.backgroundColor = AppColor.UI.backgroundGrouped
        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in make.edges.equalToSuperview() }

        contentStack.axis = .vertical
        contentStack.spacing = RunDetailLayout.sectionSpacing
        scrollView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(RunDetailLayout.topInset)
            make.leading.trailing.equalTo(view).inset(RunDetailLayout.horizontalInset)
            make.bottom.equalToSuperview().offset(-RunDetailLayout.bottomInset)
        }
    }

    private func bind() {
        viewModel.dataDriver
            .drive(onNext: { [weak self] data in self?.buildContent(with: data) })
            .disposed(by: disposeBag)
    }

    private func buildContent(with data: RunDetailViewModel.DetailData) {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        children.forEach { if $0 !== self { $0.removeFromParent() } }
        let chartHelper = RunDetailContentView.ChartHelper(record: record, data: data)
        embedSwiftUI(RunDetailContentView.TrackingSection(
            altPoints: data.altPoints, record: record,
            paceData: chartHelper.timeSeries(for: .pace),
            hrData: chartHelper.timeSeries(for: .heartRate),
            altChartData: chartHelper.timeSeries(for: .altitude)
        ))
    }

    private func embedSwiftUI<V: View>(_ swiftUIView: V, height: CGFloat? = nil) {
        let hosting = UIHostingController(rootView: swiftUIView)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        contentStack.addArrangedSubview(hosting.view)
        if let h = height { hosting.view.snp.makeConstraints { make in make.height.equalTo(h) } }
        hosting.didMove(toParent: self)
    }
}

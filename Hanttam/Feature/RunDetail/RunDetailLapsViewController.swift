//
//  RunDetailLapsViewController.swift
//  Hanttam
//

import UIKit
import SwiftUI
import RxSwift
import RxCocoa
import SnapKit

class RunDetailLapsViewController: UIViewController {
    private let record: RunningRecord
    private let viewModel: RunDetailViewModel
    private let disposeBag = DisposeBag()

    init(record: RunningRecord, viewModel: RunDetailViewModel) {
        self.record = record
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.UI.backgroundGrouped
        bind()
    }

    private func bind() {
        viewModel.dataDriver
            .drive(onNext: { [weak self] data in self?.buildContent(with: data) })
            .disposed(by: disposeBag)
    }

    private func buildContent(with data: RunDetailViewModel.DetailData) {
        let sanitizedData = sanitizedRunDetailData(data)
        view.subviews.forEach { $0.removeFromSuperview() }
        children.forEach { $0.removeFromParent() }
        guard !sanitizedData.lapRows.isEmpty else { return }
        let chartHelper = RunDetailContentView.ChartHelper(record: record, data: sanitizedData)

        let lapsContent = RunDetailContentView.LapsFullSection(
            record: record,
            lapRows: sanitizedData.lapRows,
            heartRates: sanitizedData.heartRates,
            avgCadence: chartHelper.averageValue(for: .cadence),
            strideSamples: sanitizedData.strideSamples,
            voSamples: sanitizedData.voSamples,
            speedSamples: sanitizedData.speedSamples
        )

        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in make.edges.equalToSuperview() }

        let contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
        }

        let root = VStack(alignment: .leading, spacing: RunDetailLayout.sectionSpacing) {
            RunDetailContentView.SectionHeader(title: "LAPS", icon: "stopwatch")
            lapsContent
        }
        .padding(.top, RunDetailLayout.topInset)
        .padding(.horizontal, RunDetailLayout.horizontalInset)
        .padding(.bottom, RunDetailLayout.bottomInset)

        let hosting = UIHostingController(rootView: root)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        contentView.addSubview(hosting.view)
        hosting.view.snp.makeConstraints { make in make.edges.equalToSuperview() }
        hosting.didMove(toParent: self)
    }
}

//
//  RunDetailSummaryViewController.swift
//  Hanttam
//

import UIKit
import SwiftUI
import RxSwift
import RxCocoa
import SnapKit

class RunDetailSummaryViewController: UIViewController {
    private let record: RunningRecord
    private let viewModel: RunDetailViewModel
    private let disposeBag = DisposeBag()
    private let contentStack = UIStackView()
    private let gearCardView = RunDetailGearLinkCardView()

    init(record: RunningRecord, viewModel: RunDetailViewModel) {
        self.record = record
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGearCard()
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

        viewModel.linkedShoeDriver
            .drive(onNext: { [weak self] shoe in self?.gearCardView.configure(with: shoe) })
            .disposed(by: disposeBag)
    }

    private func buildContent(with data: RunDetailViewModel.DetailData) {
        let sanitizedData = sanitizedRunDetailData(data)
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        children.forEach { if $0 !== self { $0.removeFromParent() } }

        embedSwiftUI(RunDetailContentView.SummaryHeroSection(
            record: record, heartRates: sanitizedData.heartRates, data: sanitizedData
        ))
        contentStack.addArrangedSubview(gearCardView)
    }

    private func setupGearCard() {
        gearCardView.configure(with: nil)
        gearCardView.onPrimaryTap   = { [weak self] in self?.presentGearSelection() }
        gearCardView.onSecondaryTap = { [weak self] in self?.viewModel.unlinkCurrentSession() }
    }

    private func presentGearSelection() {
        let shoes = viewModel.fetchRegisteredShoes()
        guard !shoes.isEmpty else { presentRegisterFlow(); return }

        let alert = UIAlertController(title: "운동화 선택", message: nil, preferredStyle: .actionSheet)
        shoes.forEach { shoe in
            alert.addAction(UIAlertAction(title: "\(shoe.brandName.uppercased()) \(shoe.displaySummary)", style: .default) { [weak self] _ in
                self?.viewModel.linkCurrentSession(to: shoe)
            })
        }
        alert.addAction(UIAlertAction(title: "새 운동화 등록", style: .default) { [weak self] _ in self?.presentRegisterFlow() })
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = gearCardView
            popover.sourceRect = gearCardView.bounds
        }
        present(alert, animated: true)
    }

    private func presentRegisterFlow() {
        let vc = ShoeSearchViewController { [weak self] shoe in self?.viewModel.linkCurrentSession(to: shoe) }
        present(UINavigationController(rootViewController: vc), animated: true)
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

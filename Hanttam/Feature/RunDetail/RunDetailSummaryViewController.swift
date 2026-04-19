//
//  RunDetailSummaryViewController.swift
//  Hanttam
//

import UIKit
import SwiftUI
import RxSwift
import RxCocoa
import SnapKit

/// UIHostingController의 intrinsicContentSize 변동이 UIStackView 레이아웃 사이클을
/// 유발하지 않도록 차단하는 래퍼 뷰. 높이가 고정되면 이후 intrinsicContentSize를 무시한다.
private final class HostingWrapperView: UIView {
    var pinnedHeight: CGFloat?
    override var intrinsicContentSize: CGSize {
        guard let h = pinnedHeight else { return super.intrinsicContentSize }
        return CGSize(width: UIView.noIntrinsicMetric, height: h)
    }
    override func invalidateIntrinsicContentSize() {
        // 높이가 고정된 후에는 intrinsicContentSize 무효화를 무시
        guard pinnedHeight == nil else { return }
        super.invalidateIntrinsicContentSize()
    }
}

class RunDetailSummaryViewController: UIViewController {
    private let record: RunningRecord
    private let viewModel: RunDetailViewModel
    private let disposeBag = DisposeBag()
    private let gearCardView = RunDetailGearLinkCardView()
    private let scrollView = UIScrollView()
    private let containerStack = UIStackView()

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
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in make.edges.equalToSuperview() }

        containerStack.axis = .vertical
        containerStack.spacing = RunDetailLayout.sectionSpacing
        scrollView.addSubview(containerStack)
        containerStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(RunDetailLayout.topInset)
            make.leading.trailing.equalTo(view).inset(RunDetailLayout.horizontalInset)
            make.bottom.equalToSuperview().offset(-RunDetailLayout.bottomInset)
        }

        containerStack.addArrangedSubview(gearCardView)
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
        // gearCardView는 유지, 나머지 arrangedSubview만 제거
        containerStack.arrangedSubviews.filter { $0 !== gearCardView }.forEach { $0.removeFromSuperview() }
        children.forEach { if $0 !== self { $0.removeFromParent() } }
        hostingWrapper = nil

        embedSwiftUI(RunDetailContentView.SummaryHeroSection(
            record: record, heartRates: sanitizedData.heartRates, data: sanitizedData
        ))
        // gearCardView를 항상 맨 아래로 이동
        containerStack.addArrangedSubview(gearCardView)
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

    private var hostingWrapper: HostingWrapperView?

    private func embedSwiftUI<V: View>(_ swiftUIView: V) {
        let hosting = UIHostingController(rootView: swiftUIView)
        hosting.view.backgroundColor = .clear
        addChild(hosting)

        // 래퍼 뷰로 감싸서 UIHostingController의 intrinsicContentSize 변동이
        // UIStackView 레이아웃 사이클을 유발하지 않도록 차단
        let wrapper = HostingWrapperView()
        wrapper.addSubview(hosting.view)
        hosting.view.snp.makeConstraints { make in make.edges.equalToSuperview() }
        containerStack.addArrangedSubview(wrapper)
        hostingWrapper = wrapper

        hosting.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let wrapper = hostingWrapper,
              wrapper.bounds.width > 0,
              wrapper.pinnedHeight == nil else { return }

        // 레이아웃 완료 후 높이를 한 번만 고정
        let hostingView = wrapper.subviews.first!
        let fittingSize = hostingView.systemLayoutSizeFitting(
            CGSize(width: wrapper.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        wrapper.pinnedHeight = fittingSize.height
        wrapper.snp.makeConstraints { make in make.height.equalTo(fittingSize.height) }
    }
}

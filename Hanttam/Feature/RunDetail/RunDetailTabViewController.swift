//
//  RunDetailTabViewController.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import UIKit
import SwiftUI
import Combine
import SnapKit
internal import HealthKit

class RunDetailTabViewController: UIViewController {
    
    private let record: RunningRecord
    private let viewModel: RunDetailViewModel
    private let viewDidLoadSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    private let pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private var viewControllers: [UIViewController] = []
    private let edgePanGesture = UIScreenEdgePanGestureRecognizer()
    private var interactiveDismiss: UIPercentDrivenInteractiveTransition?
    
    private let tabBar = UITabBar()
    
    private var currentIndex: Int = 0
    private let dismissTabTag = -1
    private let dismissEdgeWidth: CGFloat = 24
    
    init(record: RunningRecord, intervalRecord: IntervalRecord? = nil) {
        self.record = record
        self.viewModel = RunDetailViewModel(record: record, intervalRecord: intervalRecord)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.UI.backgroundGrouped
        setupViewControllers()
        setupPageViewController()
        setupTabBar()
        setupEdgePanGesture()
        bind()
        viewDidLoadSubject.send(())
    }
    
    private func setupViewControllers() {
        let summaryVC = RunDetailSummaryViewController(record: record, viewModel: viewModel)
        let lapsVC = RunDetailLapsViewController(record: record, viewModel: viewModel)
        let chartsVC = RunDetailChartsViewController(record: record, viewModel: viewModel)
        // let sourceVC = RunDetailSourceViewController(record: record)

        if record.isIndoor {
            viewControllers = [summaryVC, lapsVC, chartsVC]
        } else {
            let trackingVC = RunDetailTrackingViewController(record: record, viewModel: viewModel)
            viewControllers = [summaryVC, trackingVC, lapsVC, chartsVC]
        }
    }
    
    private func setupPageViewController() {
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.dataSource = self
        pageViewController.delegate = self
        
        pageViewController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        if let firstVC = viewControllers.first {
            pageViewController.setViewControllers([firstVC], direction: .forward, animated: false)
        }
        pageViewController.didMove(toParent: self)
    }
    
    private func setupTabBar() {
        let dismissItem = UITabBarItem(title: nil, image: UIImage(systemName: "chevron.left.circle"), tag: dismissTabTag)

        // UITabBar items — 실내 운동이면 경로 탭 제외
        var items = [dismissItem]
        items.append(UITabBarItem(title: "요약", image: UIImage(systemName: "list.bullet.rectangle"), tag: 0))
        if !record.isIndoor {
            items.append(UITabBarItem(title: "경로", image: UIImage(systemName: "map"), tag: 1))
        }
        items.append(contentsOf: [
            UITabBarItem(title: "랩",  image: UIImage(systemName: "stopwatch"),              tag: 2),
            UITabBarItem(title: "차트", image: UIImage(systemName: "chart.line.uptrend.xyaxis"), tag: 3),
            // UITabBarItem(title: "정보", image: UIImage(systemName: "info.circle"),           tag: 4),
        ])
        tabBar.setItems(items, animated: false)
        tabBar.selectedItem = tabItem(forContentIndex: currentIndex)
        tabBar.tintColor = RunningLevelManager.shared.accentUIColor
        tabBar.delegate = self
        view.addSubview(tabBar)

        let safeArea = view.safeAreaLayoutGuide
        tabBar.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(safeArea.snp.bottom).offset(-49)
        }
    }
    
    private func setupEdgePanGesture() {
        edgePanGesture.edges = .left
        edgePanGesture.addTarget(self, action: #selector(handleEdgePan(_:)))
        edgePanGesture.delegate = self
        view.addGestureRecognizer(edgePanGesture)
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        let progress = min(max(gesture.translation(in: view).x / view.bounds.width, 0), 1)

        switch gesture.state {
        case .began:
            interactiveDismiss = UIPercentDrivenInteractiveTransition()
            interactiveDismiss?.completionSpeed = 0.9
            dismiss(animated: true)
        case .changed:
            interactiveDismiss?.update(progress)
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).x
            if progress > 0.4 || velocity > 400 {
                interactiveDismiss?.finish()
            } else {
                interactiveDismiss?.cancel()
            }
            interactiveDismiss = nil
        default:
            break
        }
    }
    
    private func selectTab(_ index: Int) {
        guard index != currentIndex else { return }
        let direction: UIPageViewController.NavigationDirection = index > currentIndex ? .forward : .reverse
        currentIndex = index
        tabBar.selectedItem = tabItem(forContentIndex: index)
        pageViewController.setViewControllers([viewControllers[index]], direction: direction, animated: true)
    }

    private func tabItem(forContentIndex index: Int) -> UITabBarItem? {
        let tabBarIndex = index + 1
        guard let items = tabBar.items, items.indices.contains(tabBarIndex) else { return nil }
        return items[tabBarIndex]
    }

    private func restoreSelectedTabItem() {
        tabBar.selectedItem = tabItem(forContentIndex: currentIndex)
    }
    
    private func bind() {
        let input = RunDetailViewModel.Input(viewDidLoad: viewDidLoadSubject.eraseToAnyPublisher())
        _ = viewModel.transform(input: input)
    }
}

extension RunDetailTabViewController: UITabBarDelegate {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard let index = tabBar.items?.firstIndex(of: item) else { return }
        if item.tag == dismissTabTag {
            restoreSelectedTabItem()
            dismiss(animated: true)
            return
        }
        selectTab(index - 1)
    }
}

extension RunDetailTabViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === edgePanGesture else { return true }
        let location = gestureRecognizer.location(in: view)
        guard location.x <= dismissEdgeWidth else { return false }
        let velocity = edgePanGesture.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y) && velocity.x > 0
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === edgePanGesture
    }
}

extension RunDetailTabViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideHorizontalAnimator(isDismiss: false)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideHorizontalAnimator(isDismiss: true)
    }

    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        interactiveDismiss
    }
}

// MARK: - Slide Animator

private final class SlideHorizontalAnimator: NSObject, UIViewControllerAnimatedTransitioning {

    let isDismiss: Bool
    init(isDismiss: Bool) { self.isDismiss = isDismiss }

    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0.28 }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        let container = ctx.containerView
        let width = container.bounds.width

        if isDismiss {
            guard let from = ctx.view(forKey: .from) else { return }
            if let to = ctx.view(forKey: .to) {
                to.frame = container.bounds
                container.insertSubview(to, belowSubview: from)
            }
            UIView.animate(
                withDuration: transitionDuration(using: ctx),
                delay: 0,
                options: .curveEaseInOut
            ) {
                from.frame.origin.x = width
            } completion: { _ in
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        } else {
            guard let to = ctx.view(forKey: .to) else { return }
            to.frame = container.bounds.offsetBy(dx: width, dy: 0)
            container.addSubview(to)
            UIView.animate(
                withDuration: transitionDuration(using: ctx),
                delay: 0,
                options: .curveEaseInOut
            ) {
                to.frame.origin.x = 0
            } completion: { _ in
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        }
    }
}

extension RunDetailTabViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let index = viewControllers.firstIndex(of: viewController), index > 0 else { return nil }
        return viewControllers[index - 1]
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let index = viewControllers.firstIndex(of: viewController), index < viewControllers.count - 1 else { return nil }
        return viewControllers[index + 1]
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let visibleVC = pageViewController.viewControllers?.first, let index = viewControllers.firstIndex(of: visibleVC) {
            currentIndex = index
            restoreSelectedTabItem()
        }
    }
}

private func sanitizedRunDetailData(_ data: RunDetailViewModel.DetailData) -> RunDetailViewModel.DetailData {
    var sanitized = data

    sanitized.altPoints = data.altPoints.filter {
        $0.altitude.isFinite && $0.latitude.isFinite && $0.longitude.isFinite
    }

    sanitized.splits = data.splits.map { split in
        var sanitizedSplit = split
        if let elevationChange = sanitizedSplit.elevationChange, !elevationChange.isFinite {
            sanitizedSplit.elevationChange = nil
        }
        if let avgHeartRate = sanitizedSplit.avgHeartRate, !avgHeartRate.isFinite {
            sanitizedSplit.avgHeartRate = nil
        }
        if let avgCadence = sanitizedSplit.avgCadence, !avgCadence.isFinite {
            sanitizedSplit.avgCadence = nil
        }
        if let avgStrideLength = sanitizedSplit.avgStrideLength, !avgStrideLength.isFinite {
            sanitizedSplit.avgStrideLength = nil
        }
        if let avgVerticalOscillation = sanitizedSplit.avgVerticalOscillation, !avgVerticalOscillation.isFinite {
            sanitizedSplit.avgVerticalOscillation = nil
        }
        if let avgPower = sanitizedSplit.avgPower, !avgPower.isFinite {
            sanitizedSplit.avgPower = nil
        }
        if let avgSpeed = sanitizedSplit.avgSpeed, !avgSpeed.isFinite {
            sanitizedSplit.avgSpeed = nil
        }
        if let avgGroundContactTime = sanitizedSplit.avgGroundContactTime, !avgGroundContactTime.isFinite {
            sanitizedSplit.avgGroundContactTime = nil
        }
        return sanitizedSplit
    }

    sanitized.lapRows = data.lapRows.map { row in
        var sanitizedRow = row
        if let avgHeartRate = sanitizedRow.avgHeartRate, !avgHeartRate.isFinite {
            sanitizedRow.avgHeartRate = nil
        }
        if let elevationChange = sanitizedRow.elevationChange, !elevationChange.isFinite {
            sanitizedRow.elevationChange = nil
        }
        return sanitizedRow
    }

    return sanitized
}

// MARK: - Sub ViewControllers

class RunDetailSummaryViewController: UIViewController {
    private let record: RunningRecord
    private let viewModel: RunDetailViewModel
    private var cancellables = Set<AnyCancellable>()
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
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
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
        viewModel.data
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.buildContent(with: data)
            }
            .store(in: &cancellables)
    }
    
    private func buildContent(with data: RunDetailViewModel.DetailData) {
        let sanitizedData = sanitizedRunDetailData(data)
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        children.forEach { if $0 !== self { $0.removeFromParent() } }

        let summaryView = RunDetailContentView.SummaryHeroSection(
            record: record,
            heartRates: sanitizedData.heartRates,
            data: sanitizedData
        )
        embedSwiftUI(summaryView)
    }
    
    private func embedSwiftUI<V: View>(_ swiftUIView: V, height: CGFloat? = nil) {
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
}

class RunDetailTrackingViewController: UIViewController {
    private let record: RunningRecord
    private let viewModel: RunDetailViewModel
    private var cancellables = Set<AnyCancellable>()
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
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

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
        viewModel.data
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.buildContent(with: data)
            }
            .store(in: &cancellables)
    }

    private func buildContent(with data: RunDetailViewModel.DetailData) {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        children.forEach { if $0 !== self { $0.removeFromParent() } }

        let chartHelper = RunDetailContentView.ChartHelper(record: record, data: data)
        let trackingView = RunDetailContentView.TrackingSection(
            altPoints: data.altPoints,
            record: record,
            paceData: chartHelper.timeSeries(for: .pace),
            hrData: chartHelper.timeSeries(for: .heartRate),
            altChartData: chartHelper.timeSeries(for: .altitude)
        )
        embedSwiftUI(trackingView)
    }

    private func embedSwiftUI<V: View>(_ swiftUIView: V, height: CGFloat? = nil) {
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
}

class RunDetailChartsViewController: UIViewController {
    private let record: RunningRecord
    private let viewModel: RunDetailViewModel
    private var cancellables = Set<AnyCancellable>()
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
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

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
        viewModel.data
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.buildContent(with: data)
            }
            .store(in: &cancellables)
    }
    
    private func buildContent(with data: RunDetailViewModel.DetailData) {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        children.forEach { if $0 !== self { $0.removeFromParent() } }
        let chartHelper = RunDetailContentView.ChartHelper(record: record, data: data)
        let metrics = MetricType.allCases.compactMap { metric -> (MetricType, [TSPoint])? in
            let ts = chartHelper.timeSeries(for: metric)
            return ts.isEmpty ? nil : (metric, ts)
        }
        guard !metrics.isEmpty else { return }

        let metricsSection = RunDetailContentView.PerformanceMetricsSection(metrics: metrics)
        embedSwiftUI(metricsSection)
    }

    private func embedSwiftUI<V: View>(_ swiftUIView: V, height: CGFloat? = nil) {
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
}

// MARK: - Laps VC

class RunDetailLapsViewController: UIViewController {
    private let record: RunningRecord
    private let viewModel: RunDetailViewModel
    private var cancellables = Set<AnyCancellable>()

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
        viewModel.data
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.buildContent(with: data)
            }
            .store(in: &cancellables)
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
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

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
        hosting.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        hosting.didMove(toParent: self)
    }
}

// MARK: - Source VC

class RunDetailSourceViewController: UIViewController {
    private let record: RunningRecord
    
    init(record: RunningRecord) {
        self.record = record
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.UI.backgroundGrouped
        
        let sourceView = RunDetailSourceView(record: record)
        let hosting = UIHostingController(rootView: sourceView)
        hosting.view.backgroundColor = .clear
        
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        hosting.didMove(toParent: self)
    }
}

struct RunDetailSourceView: View {
    let record: RunningRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RunDetailContentView.SectionHeader(title: "WORKOUT INFO", icon: "info.circle")

                // 운동 정보
                infoCard(title: "운동 정보") {
                    InfoRow(label: "유형", value: record.isIndoor ? "실내 러닝" : "실외 러닝")
                }

                // 데이터 수집 앱
                infoCard(title: "데이터 수집 앱") {
                    InfoRow(label: "이름", value: record.sourceName)
                    if let bundleId = record.workout?.sourceRevision.source.bundleIdentifier {
                        Divider()
                        InfoRow(label: "Bundle ID", value: bundleId)
                    }
                    if let version = record.workout?.sourceRevision.version {
                        Divider()
                        InfoRow(label: "버전", value: version)
                    }
                }

                // 데이터 수집 기기
                if let device = record.workout?.device {
                    infoCard(title: "데이터 수집 기기") {
                        InfoRow(label: "이름", value: device.name ?? "알 수 없음")
                        Divider()
                        InfoRow(label: "모델", value: device.model ?? "알 수 없음")
                        Divider()
                        InfoRow(label: "제조사", value: device.manufacturer ?? "알 수 없음")
                        if let hardware = device.hardwareVersion {
                            Divider()
                            InfoRow(label: "하드웨어", value: hardware)
                        }
                        if let software = device.softwareVersion {
                            Divider()
                            InfoRow(label: "소프트웨어", value: software)
                        }
                    }
                }
            }
            .padding(.horizontal, RunDetailLayout.horizontalInset)
            .padding(.top, RunDetailLayout.topInset)
            .padding(.bottom, RunDetailLayout.bottomInset)
        }
    }

    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.captionMD.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RunDetailLayout.cardRadius))
    }

    struct InfoRow: View {
        let label: String
        let value: String
        var body: some View {
            HStack {
                Text(label)
                    .font(AppFont.bodySM)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Text(value)
                    .font(AppFont.bodySM.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .padding(.vertical, 8)
        }
    }
}

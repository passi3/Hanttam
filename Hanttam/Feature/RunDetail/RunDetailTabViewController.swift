//
//  RunDetailTabViewController.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import UIKit
import SwiftUI
import RxSwift
import RxCocoa
import SnapKit
internal import HealthKit

class RunDetailTabViewController: UIViewController {

    private let record: RunningRecord
    private let viewModel: RunDetailViewModel
    private let viewDidLoadSubject = PublishSubject<Void>()
    private let disposeBag = DisposeBag()
    
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
        viewDidLoadSubject.onNext(())
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
        if shouldUseNavigationPop {
            if gesture.state == .began {
                navigationController?.popViewController(animated: true)
            }
            return
        }

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

    private var shouldUseNavigationPop: Bool {
        guard let navigationController else { return false }
        return presentingViewController == nil && navigationController.viewControllers.count > 1
    }

    private func closeSelf(animated: Bool) {
        if shouldUseNavigationPop {
            navigationController?.popViewController(animated: animated)
        } else {
            dismiss(animated: animated)
        }
    }
    
    private func bind() {
        let input = RunDetailViewModel.Input(viewDidLoad: viewDidLoadSubject.asObservable())
        _ = viewModel.transform(input: input)
    }
}

extension RunDetailTabViewController: UITabBarDelegate {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard let index = tabBar.items?.firstIndex(of: item) else { return }
        if item.tag == dismissTabTag {
            restoreSelectedTabItem()
            closeSelf(animated: true)
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

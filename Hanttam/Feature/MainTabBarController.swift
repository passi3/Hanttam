//
//  MainTabBarController.swift
//  Hanttam
//
//  Created by passi on 3/25/26.
//

import UIKit
import SwiftUI
import RxSwift
import RxCocoa
internal import HealthKit

final class MainTabBarController: UITabBarController {

    private let disposeBag = DisposeBag()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
        bindNotifications()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateAppearance()
    }

    private func setupTabs() {
        let iconImg = HanttamBrandLogoView
            .image(size: CGSize(width: 40, height: 40))
            .withRenderingMode(.alwaysTemplate)

        let dashboardNav = UINavigationController(rootViewController: DashboardViewController())
        dashboardNav.tabBarItem = UITabBarItem(title: "한땀", image: iconImg, tag: 0)

        let workoutVC = UIHostingController(rootView: WorkoutView())
        workoutVC.tabBarItem = UITabBarItem(title: "운동", image: UIImage(systemName: "figure.run"), tag: 1)

        let recordsNav = UINavigationController(rootViewController: RecordsViewController())
        recordsNav.tabBarItem = UITabBarItem(title: "기록", image: UIImage(systemName: "list.bullet.rectangle.fill"), tag: 2)

        let gearNav = UINavigationController(rootViewController: GearListViewController())
        gearNav.tabBarItem = UITabBarItem(title: "장비", image: UIImage(systemName: "shoeprints.fill"), tag: 3)

        viewControllers = [dashboardNav, workoutVC, recordsNav, gearNav]
    }

    private func updateAppearance() {
        tabBar.tintColor = RunningLevelManager.shared.accentUIColor
    }

    private func bindNotifications() {
        NotificationCenter.default.rx
            .notification(RunningLevelManager.levelDidChangeNotification)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in self?.updateAppearance() })
            .disposed(by: disposeBag)

        NotificationCenter.default.rx
            .notification(WatchBridge.workoutStartedNotification)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in self?.selectedIndex = 1 })
            .disposed(by: disposeBag)

        NotificationCenter.default.rx
            .notification(WorkoutNotificationService.didTapWorkoutNotification)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] notification in
                guard let uuidString = notification.userInfo?[WorkoutNotificationService.workoutUUIDKey] as? String else { return }
                self?.navigateToWorkoutDetail(workoutUUID: uuidString)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Deep Link

    private func navigateToWorkoutDetail(workoutUUID: String) {
        // 기록 탭(index 2)으로 이동
        selectedIndex = 2

        // 현재 모달이 떠있으면 dismiss
        if let presented = viewControllers?[2].presentedViewController {
            presented.dismiss(animated: false)
        }

        HealthKitStore.shared.fetchRunningWorkouts { [weak self] records in
            guard let record = records.first(where: { $0.workout?.uuid.uuidString == workoutUUID }) else { return }
            guard let nav = self?.viewControllers?[2] as? UINavigationController else { return }
            nav.popToRootViewController(animated: false)
            let detailVC = RunDetailTabViewController(record: record)
            nav.pushViewController(detailVC, animated: true)
        }
    }
}

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

    /// Cold launch 시 아직 MainTabBarController가 없을 때
    /// AppDelegate가 UUID를 저장해 viewDidLoad에서 소비
    static var pendingWorkoutUUID: String?

    private let disposeBag = DisposeBag()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
        bindNotifications()
        consumePendingDeepLink()
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

    private func consumePendingDeepLink() {
        guard let uuid = MainTabBarController.pendingWorkoutUUID else { return }
        MainTabBarController.pendingWorkoutUUID = nil
        navigateToWorkoutDetail(workoutUUID: uuid)
    }

    private func navigateToWorkoutDetail(workoutUUID: String) {
        selectedIndex = 2

        HealthKitStore.shared.fetchRunningRecord(byUUID: workoutUUID) { [weak self] record in
            guard let self, let record else { return }
            // 기록 탭의 NavigationController 위에 디테일을 present
            let detailVC = RunDetailTabViewController(record: record)
            if let recordsNav = self.viewControllers?[2] {
                recordsNav.present(detailVC, animated: true)
            }
        }
    }
}

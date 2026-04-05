//
//  MainTabBarController.swift
//  Hanttam
//
//  Created by passi on 3/25/26.
//

import UIKit
import SwiftUI

final class MainTabBarController: UITabBarController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(levelDidChange),
            name: RunningLevelManager.levelDidChangeNotification,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(workoutStartedFromWatch),
            name: WatchBridge.workoutStartedNotification,
            object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateAppearance()
    }
    
    private func setupTabs() {
        let dashboardNav = UINavigationController(rootViewController: DashboardViewController())
        let iconImg = UIImage(named: "AppIcon")?.withRenderingMode(.alwaysTemplate)
        dashboardNav.tabBarItem = UITabBarItem(
            title: "한땀",
            image: iconImg,
            tag: 0
        )
        
        let workoutVC = UIHostingController(rootView: WorkoutView())
        workoutVC.tabBarItem = UITabBarItem(
            title: "운동",
            image: UIImage(systemName: "figure.run"),
            tag: 1
        )
        
        let recordsNav = UINavigationController(rootViewController: RecordsViewController())
        recordsNav.tabBarItem = UITabBarItem(
            title: "기록",
            image: UIImage(systemName: "list.bullet.rectangle.fill"),
            tag: 2
        )
        
        viewControllers = [dashboardNav, workoutVC, recordsNav]
    }
    
    private func updateAppearance() {
        tabBar.tintColor = RunningLevelManager.shared.accentUIColor
    }
    
    @objc private func levelDidChange() {
        DispatchQueue.main.async { self.updateAppearance() }
    }

    @objc private func workoutStartedFromWatch() {
        DispatchQueue.main.async {
            self.selectedIndex = 1  // 운동 탭으로 전환
        }
    }
    
}

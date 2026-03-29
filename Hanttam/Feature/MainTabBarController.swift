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
            name: RunningLevelManager.levelDidCahngeNotification,
            object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateAppearance()
    }
    
    private func setupTabs() {
        let dashboardNav = UINavigationController(rootViewController: DashboardViewController())
        dashboardNav.tabBarItem = UITabBarItem(
            title: "분석",
            image: UIImage(systemName: "chart.line.text.clipboard.fill"),
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
            image: UIImage(systemName: "list.bullet.rectangle"),
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
    
}

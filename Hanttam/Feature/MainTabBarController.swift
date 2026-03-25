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
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    private func setupTabs() {
        let dashboardNav = UINavigationController(rootViewController: DashboardViewController())
        dashboardNav.tabBarItem = UITabBarItem(
            title: "홈",
            image: UIImage(systemName: "person"),
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
}

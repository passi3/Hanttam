//
//  AppDelegate.swift
//  Hanttam
//
//  Created by passi on 12/11/25.
//

import UIKit
import FirebaseCore
import FirebaseAnalytics

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        FirebaseApp.configure()
        FirebaseConfiguration.shared.setLoggerLevel(.warning)
        Analytics.setAnalyticsCollectionEnabled(true)
        _ = WatchBridge.shared

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) { }


}

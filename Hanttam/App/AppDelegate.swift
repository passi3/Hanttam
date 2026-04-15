//
//  AppDelegate.swift
//  Hanttam
//
//  Created by passi on 12/11/25.
//

import UIKit
import UserNotifications
import FirebaseCore
import FirebaseAnalytics

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        FirebaseApp.configure()
        FirebaseConfiguration.shared.setLoggerLevel(.warning)
        Analytics.setAnalyticsCollectionEnabled(true)
        _ = GearLocalStore.shared
        _ = WatchBridge.shared

        UNUserNotificationCenter.current().delegate = self
        WorkoutNotificationService.shared.startMonitoring()

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) { }


}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let uuidString = userInfo[WorkoutNotificationService.workoutUUIDKey] as? String {
            NotificationCenter.default.post(
                name: WorkoutNotificationService.didTapWorkoutNotification,
                object: nil,
                userInfo: [WorkoutNotificationService.workoutUUIDKey: uuidString]
            )
        }
        completionHandler()
    }
}

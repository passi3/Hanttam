//
//  Hanttam_WatchApp.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/1/26.
//

import SwiftUI
internal import HealthKit

// MARK: - App Delegate

final class HanttamWatchAppDelegate: NSObject, WKApplicationDelegate {

    /// iOS 폰이 `HKHealthStore.startWatchApp(withWorkoutConfiguration:)` 을 호출하면
    /// 워치 앱이 포그라운드로 실행되면서 이 메서드가 호출된다.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        // 설정을 보관해 뒀다가 세션 시작 시 재사용
        WatchBridge.shared.pendingWorkoutConfiguration = workoutConfiguration

        let kind: WatchBridge.WorkoutKind = workoutConfiguration.locationType == .indoor
            ? .intervalRun
            : .freeRun

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: WatchBridge.workoutLaunchRequestedNotification,
                object: nil,
                userInfo: ["kind": kind.rawValue, "command": "startWorkout"]
            )
        }
    }
}

// MARK: - App

@main
struct Hanttam_Watch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(HanttamWatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { _ = WatchBridge.shared }
                // NSUserActivity 경로(이전 방식) — HK 미러링이 실패했을 때 폴백
                .onContinueUserActivity(WatchBridge.workoutActivityType) { activity in
                    let kind = (activity.userInfo?["kind"] as? String)
                        .flatMap(WatchBridge.WorkoutKind.init) ?? .freeRun
                    NotificationCenter.default.post(
                        name: WatchBridge.workoutLaunchRequestedNotification,
                        object: nil,
                        userInfo: ["kind": kind.rawValue, "command": "startWorkout"]
                    )
                }
        }
    }
}

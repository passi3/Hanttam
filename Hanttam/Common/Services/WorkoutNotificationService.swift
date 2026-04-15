//
//  WorkoutNotificationService.swift
//  Hanttam
//
//  Created by passi on 4/15/26.
//

import Foundation
internal import HealthKit
import UserNotifications

final class WorkoutNotificationService {
    static let shared = WorkoutNotificationService()

    private let healthStore = HKHealthStore()
    private let anchorKey = "WorkoutNotificationService.lastAnchor"

    private let ownBundleIDs: Set<String> = [
        "com.passi3.Hanttam",
        "com.passi3.Hanttam.watchkitapp"
    ]

    private init() {}

    // MARK: - Public

    func startMonitoring() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        requestNotificationPermission()
        setupObserver()
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("[WorkoutNotification] 알림 권한 요청 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - HealthKit Observer

    private func setupObserver() {
        let workoutType = HKObjectType.workoutType()
        
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)

        let query = HKObserverQuery(sampleType: workoutType, predicate: runningPredicate) { [weak self] _, completionHandler, error in
            if let error {
                print("[WorkoutNotification] Observer 에러: \(error.localizedDescription)")
                completionHandler()
                return
            }
            self?.checkForNewRunningWorkouts {
                completionHandler()
            }
        }

        healthStore.execute(query)

        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, error in
            if let error {
                print("[WorkoutNotification] Background delivery 등록 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Anchored Query

    private func checkForNewRunningWorkouts(completion: @escaping () -> Void) {
        let workoutType = HKObjectType.workoutType()
        let anchor = loadAnchor()
        
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)

        let query = HKAnchoredObjectQuery(
            type: workoutType,
            predicate: runningPredicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, addedObjects, _, newAnchor, error in
            guard let self else {
                completion()
                return
            }

            if let error {
                print("[WorkoutNotification] Anchored query 에러: \(error.localizedDescription)")
                completion()
                return
            }

            if let newAnchor {
                self.saveAnchor(newAnchor)
            }

            // 러닝 + 외부 앱 두 조건 모두 충족해야 알림 발송
            let newRuns = (addedObjects as? [HKWorkout])?.filter { self.isExternalRunning($0) } ?? []

            for workout in newRuns {
                self.sendCheckNotification(for: workout)
            }

            completion()
        }

        healthStore.execute(query)
    }

    // MARK: - Filter

    private func isExternalRunning(_ workout: HKWorkout) -> Bool {
        guard workout.workoutActivityType == .running else { return false }
        let bundleID = workout.sourceRevision.source.bundleIdentifier
        return !ownBundleIDs.contains(bundleID)
    }

    // MARK: - Notification Name

    static let didTapWorkoutNotification = Notification.Name("WorkoutNotificationService.didTapWorkout")
    static let workoutUUIDKey = "workoutUUID"

    // MARK: - Local Notification

    private func sendCheckNotification(for workout: HKWorkout) {
        let hasGear = !GearLocalStore.shared.fetchRegisteredShoes().isEmpty

        let content = UNMutableNotificationContent()
        content.title = "운동 완료! 💪"
        content.body = hasGear
            ? "마무리로 러닝화 마일리지를 체크해보세요!"
            : "방금 운동한 기록을 사진으로 남겨보세요!"
        content.sound = .default
        content.userInfo = [WorkoutNotificationService.workoutUUIDKey: workout.uuid.uuidString]

        let request = UNNotificationRequest(
            identifier: "workout-photo-\(workout.uuid.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[WorkoutNotification] 알림 발송 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Anchor Persistence

    private func saveAnchor(_ anchor: HKQueryAnchor) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: anchorKey)
        } catch {
            print("[WorkoutNotification] 앵커 저장 실패: \(error.localizedDescription)")
        }
    }

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
}

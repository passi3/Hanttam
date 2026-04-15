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

        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error {
                print("[WorkoutNotification] Observer 에러: \(error.localizedDescription)")
                completionHandler()
                return
            }
            self?.checkForNewExternalWorkouts {
                completionHandler()
            }
        }

        healthStore.execute(query)

        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { success, error in
            if let error {
                print("[WorkoutNotification] Background delivery 등록 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Anchored Query

    private func checkForNewExternalWorkouts(completion: @escaping () -> Void) {
        let workoutType = HKObjectType.workoutType()
        let anchor = loadAnchor()

        let query = HKAnchoredObjectQuery(
            type: workoutType,
            predicate: nil,
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

            let externalWorkouts = (addedObjects as? [HKWorkout])?.filter { self.isExternalWorkout($0) } ?? []

            for workout in externalWorkouts {
                self.sendPhotoNotification(for: workout)
            }

            completion()
        }

        healthStore.execute(query)
    }

    // MARK: - Filter

    private func isExternalWorkout(_ workout: HKWorkout) -> Bool {
        let bundleID = workout.sourceRevision.source.bundleIdentifier
        return !ownBundleIDs.contains(bundleID)
    }

    // MARK: - Local Notification

    private func sendPhotoNotification(for workout: HKWorkout) {
        let content = UNMutableNotificationContent()
        content.title = "운동 완료! 💪"
        content.body = "방금 운동한 기록을 사진으로 남겨보세요!"
        content.sound = .default

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

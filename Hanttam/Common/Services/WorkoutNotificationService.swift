//
//  WorkoutNotificationService.swift
//  Hanttam
//
//  Created by passi on 4/15/26.
//

import Foundation
internal import HealthKit
import UserNotifications

// MARK: - Notification Scheduling Protocol (테스트 주입용)

protocol NotificationScheduling {
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?)
}

extension UNUserNotificationCenter: NotificationScheduling {}

// MARK: - WorkoutNotificationService

final class WorkoutNotificationService {

    // MARK: Singleton (프로덕션)
    static let shared = WorkoutNotificationService()

    // MARK: Notification constants
    static let didTapWorkoutNotification = Notification.Name("WorkoutNotificationService.didTapWorkout")
    static let workoutUUIDKey = "workoutUUID"

    // MARK: Dependencies (주입 가능 — 테스트에서 mock 으로 교체)
    private let healthStore = HKHealthStore()
    private let notificationCenter: NotificationScheduling
    private let gearStore: GearLocalStoring
    /// 자체 앱 번들 ID 목록. 테스트에서는 빈 세트 또는 임의 값으로 교체해 필터 동작을 제어.
    let ownBundleIDs: Set<String>

    private let anchorKey = "WorkoutNotificationService.lastAnchor"

    // 프로덕션용
    private init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        self.gearStore = GearLocalStore.shared
        self.ownBundleIDs = ["com.passi3.Hanttam", "com.passi3.Hanttam.watchkitapp"]
    }

    /// 테스트 전용 이니셜라이저
    init(
        notificationCenter: NotificationScheduling,
        gearStore: GearLocalStoring,
        ownBundleIDs: Set<String> = []
    ) {
        self.notificationCenter = notificationCenter
        self.gearStore = gearStore
        self.ownBundleIDs = ownBundleIDs
    }

    // MARK: - Public

    func startMonitoring() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        requestNotificationPermission()
        setupObserver()
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
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
        let existingAnchor = loadAnchor()
        let isFirstRun = existingAnchor == nil
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)

        let query = HKAnchoredObjectQuery(
            type: workoutType,
            predicate: runningPredicate,
            anchor: existingAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, addedObjects, _, newAnchor, error in
            guard let self else { completion(); return }

            if let error {
                print("[WorkoutNotification] Anchored query 에러: \(error.localizedDescription)")
                completion()
                return
            }

            if let newAnchor { self.saveAnchor(newAnchor) }

            // 첫 실행이면 기존 기록 전체가 반환되므로 알림 없이 anchor 위치만 확보
            guard !isFirstRun else {
                completion()
                return
            }

            let newRuns = (addedObjects as? [HKWorkout])?.filter { self.isExternalRunning($0) } ?? []
            for workout in newRuns { self.sendPhotoNotification(for: workout) }

            completion()
        }

        healthStore.execute(query)
    }

    // MARK: - Filter (internal for testing)

    func isExternalRunning(_ workout: HKWorkout) -> Bool {
        guard workout.workoutActivityType == .running else { return false }
        let bundleID = workout.sourceRevision.source.bundleIdentifier
        return !ownBundleIDs.contains(bundleID)
    }

    // MARK: - Local Notification (internal for testing)

    func sendPhotoNotification(for workout: HKWorkout) {
        let hasGear = !gearStore.fetchRegisteredShoes().isEmpty

        let content = UNMutableNotificationContent()
        content.title = "운동 완료! 💪"
        content.body = hasGear
            ? "어떤 신발로 뛰었는지 기록해보세요!"
            : "방금 운동한 기록을 사진으로 남겨보세요!"
        content.sound = .default
        content.userInfo = [WorkoutNotificationService.workoutUUIDKey: workout.uuid.uuidString]

        let request = UNNotificationRequest(
            identifier: "workout-photo-\(workout.uuid.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        notificationCenter.add(request) { error in
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

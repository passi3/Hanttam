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
        fetchWorkoutStats(relativeTo: workout) { [weak self] weeklyCount, streak in
            guard let self else { return }

            let hasGear = !self.gearStore.fetchRegisteredShoes().isEmpty
            let gearBody = hasGear ? "어떤 신발로 뛰었는지 기록해보세요!" : "방금 운동한 기록을 사진으로 남겨보세요!"

            let title: String
            switch (weeklyCount, streak) {
            case (1, 1):
                // 이번 주 첫 운동이자 연속 1주 — 첫 시작
                title = "시작이 반!"
            case (1, let s):
                // 이번 주 첫 운동, 연속 s주
                title = "연속 \(s)주 운동 완료!"
            case (let n, _):
                // 이번 주 n번째 운동
                title = "이번주 \(n)번째 운동 완료!"
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = gearBody
            content.sound = .default
            content.userInfo = [WorkoutNotificationService.workoutUUIDKey: workout.uuid.uuidString]

            let request = UNNotificationRequest(
                identifier: "workout-photo-\(workout.uuid.uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )

            self.notificationCenter.add(request) { error in
                if let error {
                    print("[WorkoutNotification] 알림 발송 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Workout Stats

    private func fetchWorkoutStats(relativeTo workout: HKWorkout, completion: @escaping (_ weeklyCount: Int, _ streak: Int) -> Void) {
        let calendar = Calendar.current
        let referenceDate = workout.endDate

        guard let startOfCurrentWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start,
              let twoYearsAgo = calendar.date(byAdding: .year, value: -2, to: referenceDate) else {
            completion(1, 1)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: twoYearsAgo, end: referenceDate, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            guard let self else { completion(1, 1); return }

            let runs = (samples as? [HKWorkout])?.filter { self.isExternalRunning($0) } ?? []

            // 이번 주 운동 횟수
            let weeklyCount = runs.filter { $0.endDate >= startOfCurrentWeek }.count

            // 연속 주 streak: 현재 주부터 역순으로 운동이 있는 주를 카운트
            var streak = 0
            var weekStart = startOfCurrentWeek
            while let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) {
                let hasRun = runs.contains { $0.endDate >= weekStart && $0.endDate < weekEnd }
                guard hasRun else { break }
                streak += 1
                guard let prevWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) else { break }
                weekStart = prevWeek
            }

            completion(max(weeklyCount, 1), max(streak, 1))
        }

        healthStore.execute(query)
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

//
//  HealthKitStore.swift
//  Hanttam
//
//  Created by passi on 3/25/26.
//

import Foundation
internal import HealthKit
import CoreLocation

final class HealthKitStore: NSObject {
    enum PhoneWorkoutKind {
        case freeRun
        case intervalRun(settings: IntervalSettings)
    }

    struct PhoneWorkoutMetrics {
        var heartRate: Double?
        var avgHeartRate: Double?
        var heartRateSamples: [HeartRateSample]

        static let empty = PhoneWorkoutMetrics(
            heartRate: nil,
            avgHeartRate: nil,
            heartRateSamples: []
        )
    }
    
    static let shared = HealthKitStore()
    static let phoneWorkoutMetricsDidUpdate = Notification.Name("HealthKitStorePhoneWorkoutMetricsDidUpdate")
    
    private var store              : HKHealthStore?
    private let routeQueryLock     = NSLock()
    private var activeRouteQueries = Set<HKWorkoutRouteQuery>()
    private var phoneWorkoutSession: HKWorkoutSession?
    private var phoneWorkoutBuilder: HKWorkoutBuilder?
    private var phoneWorkoutKind: PhoneWorkoutKind?
    private var phoneWorkoutStartDate: Date?
    private var phoneWorkoutIsIndoor = false
    private var lastSavedWorkout: HKWorkout?
    private(set) var currentPhoneWorkoutMetrics: PhoneWorkoutMetrics = .empty
    
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var currentPhoneWorkoutStartDate: Date? { phoneWorkoutStartDate }
    
    private override init() {
        super.init()
        if isAvailable {
            store = HKHealthStore()
        }
    }
    
    //MARK: - 권한 요청
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard let store, isAvailable else { completion(false); return }
        
        let routeType = HKSeriesType.workoutRoute()
        
        var readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            routeType
        ]
        
        let runningTypes: [HKQuantityTypeIdentifier] = [
            .runningGroundContactTime,
            .runningPower,
            .runningSpeed,
            .runningStrideLength,
            .runningVerticalOscillation,
        ]
        
        for id in runningTypes {
            if let type = HKObjectType.quantityType(forIdentifier: id) {
                readTypes.insert(type)
            }
        }
        
        let shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKSeriesType.workoutRoute()
        ]
        
        store.requestAuthorization(toShare: shareTypes, read: readTypes) { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func startPhoneWorkout(
        kind: PhoneWorkoutKind,
        isIndoor: Bool,
        start: Date = Date(),
        completion: @escaping (Bool, Error?) -> Void
    ) {
        guard let store else {
            completion(false, nil)
            return
        }

        guard phoneWorkoutSession == nil, phoneWorkoutBuilder == nil else {
            completion(false, NSError(domain: "HealthKitStore", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "이미 진행 중인 운동 세션이 있습니다."
            ]))
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = isIndoor ? .indoor : .outdoor

        if #available(iOS 26.0, *) {
            do {
                let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
                let builder = session.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
                if #available(iOS 26.0, *) {
                    builder.delegate = self
                }

                session.startActivity(with: start)
                builder.beginCollection(withStart: start) { [weak self] ok, error in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        guard ok else {
                            session.end()
                            completion(false, error)
                            return
                        }

                        self.phoneWorkoutSession = session
                        self.phoneWorkoutBuilder = builder
                        self.phoneWorkoutKind = kind
                        self.phoneWorkoutStartDate = start
                        self.phoneWorkoutIsIndoor = isIndoor
                        self.resetPhoneWorkoutMetrics()
                        completion(true, nil)
                    }
                }
            } catch {
                completion(false, error)
            }
        } else {
            phoneWorkoutKind = kind
            phoneWorkoutStartDate = start
            phoneWorkoutIsIndoor = isIndoor
            resetPhoneWorkoutMetrics()
            completion(true, nil)
        }
    }

    func pausePhoneWorkout() {
        phoneWorkoutSession?.pause()
    }

    func resumePhoneWorkout() {
        phoneWorkoutSession?.resume()
    }

    func finishPhoneWorkout(
        end: Date,
        distance: Double,
        calories: Double?,
        routeLocations: [CLLocation],
        laps: [IntervalLap] = [],
        completion: @escaping (Bool, HKWorkout?, Error?) -> Void
    ) {
        guard let store,
              let start = phoneWorkoutStartDate else {
            completion(false, nil, NSError(domain: "HealthKitStore", code: 1002, userInfo: [
                NSLocalizedDescriptionKey: "진행 중인 운동 세션이 없습니다."
            ]))
            return
        }

        if #available(iOS 26.0, *),
           let builder = phoneWorkoutBuilder,
           let session = phoneWorkoutSession {
            session.end()

            addWorkoutSamples(
                builder: builder,
                start: start,
                end: end,
                distance: distance,
                calories: calories
            ) { [weak self] ok, error in
                guard let self else { return }
                guard ok else {
                    self.clearActivePhoneWorkout()
                    DispatchQueue.main.async { completion(false, nil, error) }
                    return
                }

                self.addPhoneWorkoutDetails(builder: builder, laps: laps) { ok, error in
                    guard ok else {
                        self.clearActivePhoneWorkout()
                        DispatchQueue.main.async { completion(false, nil, error) }
                        return
                    }

                    builder.endCollection(withEnd: end) { ok, error in
                        guard ok else {
                            self.clearActivePhoneWorkout()
                            DispatchQueue.main.async { completion(false, nil, error) }
                            return
                        }

                        builder.finishWorkout { workout, error in
                            guard let workout else {
                                self.clearActivePhoneWorkout()
                                DispatchQueue.main.async { completion(false, nil, error) }
                                return
                            }

                            self.lastSavedWorkout = workout
                            self.attachRouteIfNeeded(store: store, workout: workout, locations: routeLocations) { routeError in
                                self.clearActivePhoneWorkout()
                                DispatchQueue.main.async {
                                    completion(true, workout, routeError)
                                }
                            }
                        }
                    }
                }
            }
            return
        }

        finishFallbackPhoneWorkout(
            store: store,
            start: start,
            end: end,
            distance: distance,
            calories: calories,
            routeLocations: routeLocations,
            laps: laps,
            completion: completion
        )
    }

    func discardCurrentWorkout(completion: @escaping (Bool, Error?) -> Void) {
        guard let workout = lastSavedWorkout else {
            completion(false, nil)
            return
        }

        deleteWorkout(workout) { [weak self] success, error in
            if success {
                self?.lastSavedWorkout = nil
            }
            completion(success, error)
        }
    }
    
    // MARK: - Write
    //자유 러닝
    func saveRunningWorkout(
        start: Date,
        end: Date,
        distance: Double,
        calories: Double?,
        routeLocations: [CLLocation],
        isIndoor: Bool = false,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        guard let store else { completion(false, nil); return }

        let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distance)
        let caloriesQuantity = calories.map { HKQuantity(unit: .kilocalorie(), doubleValue: $0) }

        // 거리 샘플
        let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let distSample = HKQuantitySample(type: distType, quantity: distanceQuantity, start: start, end: end)

        // 워크아웃 빌더 사용
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = isIndoor ? .indoor : .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        builder.beginCollection(withStart: start) { ok, error in
            guard ok else { completion(false, error); return }

            var samples: [HKSample] = [distSample]

            if let cal = calories, cal > 0 {
                let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
                let calSample = HKQuantitySample(
                    type: calType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: cal),
                    start: start, end: end
                )
                samples.append(calSample)
            }

            builder.add(samples) { ok, error in
                guard ok else { completion(false, error); return }

                builder.endCollection(withEnd: end) { ok, error in
                    guard ok else { completion(false, error); return }

                    builder.finishWorkout { workout, error in
                        guard let workout else { completion(false, error); return }

                        // 경로 저장
                        if !routeLocations.isEmpty {
                            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
                            routeBuilder.insertRouteData(routeLocations) { ok, error in
                                guard ok else {
                                    print("[HealthKit] Route insert failed: \(error?.localizedDescription ?? "")")
                                    completion(true, nil) // 워크아웃은 저장됨
                                    return
                                }
                                routeBuilder.finishRoute(with: workout, metadata: nil) { _, error in
                                    if let error {
                                        print("[HealthKit] Route finish failed: \(error.localizedDescription)")
                                    }
                                    DispatchQueue.main.async { completion(true, nil) }
                                }
                            }
                        } else {
                            DispatchQueue.main.async { completion(true, nil) }
                        }
                    }
                }
            }
        }
    }
    
    //인터벌 운동
    func saveIntervalWorkout(
        start: Date,
        end: Date,
        distance: Double,
        calories: Double?,
        laps: [IntervalLap],
        settings: IntervalSettings,
        routeLocations: [CLLocation],
        isIndoor: Bool = false,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        guard let store else { completion(false, nil); return }

        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = isIndoor ? .indoor : .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        builder.beginCollection(withStart: start) { ok, error in
            guard ok else { completion(false, error); return }

            // 거리 + 칼로리 샘플
            let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
            let distSample = HKQuantitySample(
                type: distType,
                quantity: HKQuantity(unit: .meter(), doubleValue: distance),
                start: start, end: end
            )
            var samples: [HKSample] = [distSample]

            if let cal = calories, cal > 0 {
                let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
                samples.append(HKQuantitySample(
                    type: calType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: cal),
                    start: start, end: end
                ))
            }

            builder.add(samples) { ok, error in
                guard ok else { completion(false, error); return }

                // 각 랩을 HKWorkoutActivity로 추가
                let group = DispatchGroup()
                for lap in laps {
                    group.enter()
                    let activityConfig = HKWorkoutConfiguration()
                    activityConfig.activityType = .running
                    activityConfig.locationType = isIndoor ? .indoor : .outdoor

                    let metadata: [String: Any] = [
                        "intervalLapType": lap.type.rawValue,
                        "intervalLapNumber": lap.id,
                        "intervalLapDistance": lap.distance
                    ]
                    let activity = HKWorkoutActivity(
                        workoutConfiguration: activityConfig,
                        start: lap.startDate,
                        end: lap.endDate,
                        metadata: metadata
                    )
                    builder.addWorkoutActivity(activity) { _, _ in group.leave() }
                }

                group.notify(queue: .global()) {
                    // 메타데이터에 인터벌 설정 저장
                    let workoutMeta: [String: Any] = [
                        "isInterval": true,
                        "intervalSets": settings.sets,
                        "intervalLapDistance": settings.lapDistance,
                        "intervalRestDuration": settings.restDuration
                    ]
                    builder.addMetadata(workoutMeta) { _, _ in
                        builder.endCollection(withEnd: end) { ok, error in
                            guard ok else { completion(false, error); return }

                            builder.finishWorkout { workout, error in
                                guard let workout else { completion(false, error); return }

                                if !routeLocations.isEmpty {
                                    let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
                                    routeBuilder.insertRouteData(routeLocations) { ok, _ in
                                        guard ok else {
                                            DispatchQueue.main.async { completion(true, nil) }
                                            return
                                        }
                                        routeBuilder.finishRoute(with: workout, metadata: nil) { _, _ in
                                            DispatchQueue.main.async { completion(true, nil) }
                                        }
                                    }
                                } else {
                                    DispatchQueue.main.async { completion(true, nil) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func addWorkoutSamples(
        builder: HKWorkoutBuilder,
        start: Date,
        end: Date,
        distance: Double,
        calories: Double?,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let distanceSample = HKQuantitySample(
            type: distanceType,
            quantity: HKQuantity(unit: .meter(), doubleValue: distance),
            start: start,
            end: end
        )

        var samples: [HKSample] = [distanceSample]
        if let calories, calories > 0 {
            let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
            samples.append(HKQuantitySample(
                type: calorieType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                start: start,
                end: end
            ))
        }

        builder.add(samples) { ok, error in
            DispatchQueue.main.async { completion(ok, error) }
        }
    }

    private func addPhoneWorkoutDetails(
        builder: HKWorkoutBuilder,
        laps: [IntervalLap],
        completion: @escaping (Bool, Error?) -> Void
    ) {
        guard let kind = phoneWorkoutKind else {
            completion(true, nil)
            return
        }

        switch kind {
        case .freeRun:
            completion(true, nil)

        case .intervalRun(let settings):
            let group = DispatchGroup()
            var activityError: Error?

            for lap in laps {
                group.enter()

                let activityConfig = HKWorkoutConfiguration()
                activityConfig.activityType = .running
                activityConfig.locationType = phoneWorkoutIsIndoor ? .indoor : .outdoor

                let activity = HKWorkoutActivity(
                    workoutConfiguration: activityConfig,
                    start: lap.startDate,
                    end: lap.endDate,
                    metadata: [
                        "intervalLapType": lap.type.rawValue,
                        "intervalLapNumber": lap.id,
                        "intervalLapDistance": lap.distance
                    ]
                )

                builder.addWorkoutActivity(activity) { ok, error in
                    if !ok, activityError == nil {
                        activityError = error
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                if let activityError {
                    completion(false, activityError)
                    return
                }

                builder.addMetadata([
                    "isInterval": true,
                    "intervalSets": settings.sets,
                    "intervalLapDistance": settings.lapDistance,
                    "intervalRestDuration": settings.restDuration
                ]) { ok, error in
                    DispatchQueue.main.async { completion(ok, error) }
                }
            }
        }
    }

    private func attachRouteIfNeeded(
        store: HKHealthStore,
        workout: HKWorkout,
        locations: [CLLocation],
        completion: @escaping (Error?) -> Void
    ) {
        guard !locations.isEmpty else {
            completion(nil)
            return
        }

        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        routeBuilder.insertRouteData(locations) { ok, error in
            guard ok else {
                print("[HealthKit] Route insert failed: \(error?.localizedDescription ?? "")")
                DispatchQueue.main.async { completion(error) }
                return
            }

            routeBuilder.finishRoute(with: workout, metadata: nil) { _, error in
                if let error {
                    print("[HealthKit] Route finish failed: \(error.localizedDescription)")
                }
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    private func clearActivePhoneWorkout() {
        phoneWorkoutSession = nil
        phoneWorkoutBuilder = nil
        phoneWorkoutKind = nil
        phoneWorkoutStartDate = nil
        phoneWorkoutIsIndoor = false
        resetPhoneWorkoutMetrics()
    }

    private func resetPhoneWorkoutMetrics() {
        currentPhoneWorkoutMetrics = .empty
        NotificationCenter.default.post(
            name: Self.phoneWorkoutMetricsDidUpdate,
            object: self,
            userInfo: ["metrics": currentPhoneWorkoutMetrics]
        )
    }

    private func updatePhoneWorkoutHeartRateMetrics(
        heartRate: Double?,
        avgHeartRate: Double?,
        timestamp: Date = Date()
    ) {
        var samples = currentPhoneWorkoutMetrics.heartRateSamples
        if let heartRate {
            samples.append(HeartRateSample(date: timestamp, bpm: heartRate))
        }
        currentPhoneWorkoutMetrics = PhoneWorkoutMetrics(
            heartRate: heartRate ?? currentPhoneWorkoutMetrics.heartRate,
            avgHeartRate: avgHeartRate ?? currentPhoneWorkoutMetrics.avgHeartRate,
            heartRateSamples: samples
        )
        NotificationCenter.default.post(
            name: Self.phoneWorkoutMetricsDidUpdate,
            object: self,
            userInfo: ["metrics": currentPhoneWorkoutMetrics]
        )
    }

    private func finishFallbackPhoneWorkout(
        store: HKHealthStore,
        start: Date,
        end: Date,
        distance: Double,
        calories: Double?,
        routeLocations: [CLLocation],
        laps: [IntervalLap],
        completion: @escaping (Bool, HKWorkout?, Error?) -> Void
    ) {
        switch phoneWorkoutKind {
        case .freeRun:
            saveRunningWorkout(
                start: start,
                end: end,
                distance: distance,
                calories: calories,
                routeLocations: routeLocations,
                isIndoor: phoneWorkoutIsIndoor
            ) { [weak self] success, error in
                guard let self else { return }
                if !success {
                    self.clearActivePhoneWorkout()
                    completion(false, nil, error)
                    return
                }
                self.fetchMostRecentWorkout(from: store, start: start, end: end) { workout in
                    self.lastSavedWorkout = workout
                    self.clearActivePhoneWorkout()
                    completion(true, workout, error)
                }
            }

        case .intervalRun(let settings):
            saveIntervalWorkout(
                start: start,
                end: end,
                distance: distance,
                calories: calories,
                laps: laps,
                settings: settings,
                routeLocations: routeLocations,
                isIndoor: phoneWorkoutIsIndoor
            ) { [weak self] success, error in
                guard let self else { return }
                if !success {
                    self.clearActivePhoneWorkout()
                    completion(false, nil, error)
                    return
                }
                self.fetchMostRecentWorkout(from: store, start: start, end: end) { workout in
                    self.lastSavedWorkout = workout
                    self.clearActivePhoneWorkout()
                    completion(true, workout, error)
                }
            }

        case .none:
            clearActivePhoneWorkout()
            completion(false, nil, NSError(domain: "HealthKitStore", code: 1003, userInfo: [
                NSLocalizedDescriptionKey: "운동 종류를 확인할 수 없습니다."
            ]))
        }
    }

    private func fetchMostRecentWorkout(
        from store: HKHealthStore,
        start: Date,
        end: Date,
        completion: @escaping (HKWorkout?) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-5), end: end.addingTimeInterval(5))
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            DispatchQueue.main.async {
                completion(samples?.first as? HKWorkout)
            }
        }
        store.execute(query)
    }
    
    //MARK: - Delete
    
    func deleteWorkout(_ workout: HKWorkout, completion: @escaping (Bool, Error?) -> Void) {
        guard let store else {
            completion(false, nil)
            return
        }
        store.delete(workout) { success, error in
            if success, self.lastSavedWorkout?.uuid == workout.uuid {
                self.lastSavedWorkout = nil
            }
            DispatchQueue.main.async { completion(success, error) }
        }
    }
    
    //MARK: - Read
    //러닝 기록 조회
    func fetchRunningWorkouts(completion: @escaping ([RunningRecord]) -> Void
    ) {
        guard let store else { completion([]); return}
        
        let workoutType = HKObjectType.workoutType()
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .running)
        
        //사용자가 직접 입력한 데이터 필터 생성 후 반전시킴
        let isManualPredicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyWasUserEntered,
            operatorType: .equalTo,
            value: true)
        let notManualPredicate = NSCompoundPredicate(notPredicateWithSubpredicate: isManualPredicate)
        
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [workoutPredicate, notManualPredicate])
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false)
        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            let workouts = samples as? [HKWorkout] ?? []
            let records: [RunningRecord] = workouts.map { (w: HKWorkout) -> RunningRecord in
                // 1. 소스(앱) 이름 추출
                let source = w.sourceRevision.source.name
                let isManual = w.metadata?[HKMetadataKeyWasUserEntered] as? Bool ?? false
                let appName = isManual ? "\(source) (수동)" : source

                // 2. 디바이스 이름 추출 (Apple Watch, iPhone 등)
                let device = w.device?.name ?? w.device?.model

                // 3. 실내 운동 판별
                let indoor = w.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false

                return RunningRecord(
                    date: w.startDate,
                    endDate: w.endDate,
                    duration: w.duration,
                    distance: w.totalDistance?.doubleValue(for: .meter()) ?? 0,
                    calories: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                    workout: w,
                    sourceName: appName,
                    deviceName: device,
                    isIndoor: indoor
                )
            }
            DispatchQueue.main.async { completion(records) }
        }

        store.execute(query)
    }
    
    //인터벌 러닝 조회
    func fetchIntervalWorkouts(completion: @escaping ([IntervalRecord]) -> Void) {
        guard let store else { completion([]); return }

        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: runningPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            let workouts = samples as? [HKWorkout] ?? []
            let intervalWorkouts = workouts.filter { w in
                w.metadata?["isInterval"] as? Bool == true
            }

            let records: [IntervalRecord] = intervalWorkouts.compactMap { w in
                guard let sets = w.metadata?["intervalSets"] as? Int,
                      let lapDist = w.metadata?["intervalLapDistance"] as? Double,
                      let restDur = w.metadata?["intervalRestDuration"] as? Double
                else { return nil }

                let settings = IntervalSettings(sets: sets, lapDistance: lapDist, restDuration: restDur)

                let laps: [IntervalLap] = w.workoutActivities.compactMap { activity in
                    guard let typeRaw = activity.metadata?["intervalLapType"] as? String,
                          let type = IntervalLap.LapType(rawValue: typeRaw),
                          let lapNum = activity.metadata?["intervalLapNumber"] as? Int,
                          let lapEndDate = activity.endDate
                    else { return nil }
                    let dist = activity.metadata?["intervalLapDistance"] as? Double ?? 0
                    let duration = lapEndDate.timeIntervalSince(activity.startDate)
                    let pace: TimeInterval? = (type == .run && dist > 0)
                        ? duration / (dist / 1000)
                        : nil
                    return IntervalLap(
                        id: lapNum, type: type, duration: duration,
                        distance: dist, startDate: activity.startDate,
                        endDate: lapEndDate, avgPace: pace
                    )
                }.sorted { $0.id < $1.id }

                let totalDist = laps.filter { $0.type == .run }.reduce(0) { $0 + $1.distance }
                return IntervalRecord(
                    id: UUID(),
                    date: w.startDate,
                    settings: settings,
                    laps: laps,
                    totalDistance: totalDist,
                    totalDuration: w.duration,
                    routeLatitudes: [],
                    routeLongitudes: [],
                    workout: w
                )
            }
            DispatchQueue.main.async { completion(records) }
        }
        store.execute(query)
    }
    
    //인터벌용 거리 샘플 조회
    func fetchDistanceSamples(for workout: HKWorkout?, from start: Date, to end: Date, completion: @escaping ([DistanceSample]) -> Void) {
        guard let store else { completion([]); return }

        let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let timePredicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let predicate: NSPredicate
        if let workout {
            let workoutPredicate = HKQuery.predicateForObjects(from: workout)
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [timePredicate, workoutPredicate])
        } else {
            predicate = timePredicate
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let query = HKSampleQuery(
            sampleType: distType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            let results = (samples as? [HKQuantitySample])?.map { s in
                DistanceSample(
                    startDate: s.startDate,
                    endDate: s.endDate,
                    distance: s.quantity.doubleValue(for: .meter())
                )
            } ?? []
            DispatchQueue.main.async { completion(results) }
        }

        store.execute(query)
    }
    
    //심박수 조회
    func fetchHeartRateSamples(from start: Date, to end: Date, completion: @escaping ([HeartRateSample]) -> Void
    ) {
        guard let store else { completion([]); return }
        
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKSampleQuery(
            sampleType: hrType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            let results = (samples as? [HKQuantitySample])?.map { s in
                HeartRateSample(
                    date: s.startDate,
                    bpm: s.quantity.doubleValue(for: .init(from: "count/min"))
                )
            } ?? []
            DispatchQueue.main.async { completion(results)}
        }
        store.execute(query)
    }
    
    //범용 샘플 조회
    func fetchQuantitySamples(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date,
        completion: @escaping ([QuantitySamplePoint]) -> Void
    ) {
        guard let store,
              let type = HKQuantityType.quantityType(forIdentifier: identifier)
        else { completion([]); return }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                    ascending: true)
        
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            let result = (samples as? [HKQuantitySample])?.map { s in
                QuantitySamplePoint(
                    startDate: s.startDate,
                    endDate: s.endDate,
                    value: s.quantity.doubleValue(for: unit))
            } ?? []
            DispatchQueue.main.async { completion(result) }
        }
        store.execute(query)
    }
    
    //고도 조회
    func fetchAltitudeData(for workout: HKWorkout, completion : @escaping ([AltitudePoint]) -> Void) {
            guard let store else { completion([]); return }
            
            let routeStatus   = store.authorizationStatus(for: HKSeriesType.workoutRoute())
            let workoutStatus = store.authorizationStatus(for: HKObjectType.workoutType())
            
            fetchRouteLocations(for: workout, completion: completion)
        }
    
    //경로 조회
    private func fetchRouteLocations(for workout: HKWorkout, completion: @escaping ([AltitudePoint]) -> Void) {
            guard let store else { completion([]); return }
            
            let routeType = HKSeriesType.workoutRoute()
            let predicate = HKQuery.predicateForObjects(from: workout)
            
            let query = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { [weak self] _, samples, error in
                if let error { print("[Route] 쿼리 실패: \(error.localizedDescription)") }
                
                if let route = (samples as? [HKWorkoutRoute])?.first {
                    self?.fetchLocations(from: route, completion: completion)
                } else {
                    DispatchQueue.main.async { completion([]) }
                }
            }
            store.execute(query)
        }
    
    private func fetchRouteByDate(for workout: HKWorkout, completion: @escaping ([AltitudePoint]) -> Void) {
            guard let store else { completion([]); return }
            
            let routeType = HKSeriesType.workoutRoute()
            let datePredicate = HKQuery.predicateForSamples(
                withStart: workout.startDate.addingTimeInterval(-60),
                end: workout.endDate.addingTimeInterval(-60),
                options: .strictStartDate
            )
            
            let query = HKSampleQuery(
                sampleType: routeType,
                predicate: datePredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(
                    key: HKSampleSortIdentifierStartDate,
                    ascending: true)]
            ) { [weak self] _, samples, error in
                if let error { print("[Route] date-based 루트 쿼리 오류 \(error)") }
                if let route = (samples as? [HKWorkoutRoute])?.first {
                    self?.fetchLocations(
                        from: route,
                        completion: completion)
                } else {
                    DispatchQueue.main.async { completion([]) }
                }
            }
            store.execute(query)
        }
    
    private func fetchLocations(from route: HKWorkoutRoute, completion: @escaping ([AltitudePoint]) -> Void) {
            var allPoints: [AltitudePoint] = []
            
            let query = HKWorkoutRouteQuery(route: route) { [weak self] q, locations, done, error in
                if let error { print("[Route] 위치 데이터 실패: \(error.localizedDescription)") }
                if let locations {
                    allPoints.append(contentsOf: locations.map {
                        AltitudePoint(
                            date: $0.timestamp,
                            altitude: $0.altitude,
                            latitude: $0.coordinate.latitude,
                            longitude: $0.coordinate.longitude)
                    })
                }
                if done {
                    print("[Route] Total points: \(allPoints.count)")
                    self?.routeQueryLock.lock()
                    self?.activeRouteQueries.remove(q)
                    self?.routeQueryLock.unlock()
                    DispatchQueue.main.async {
                        completion(allPoints)
                    }
                }
            }
            routeQueryLock.lock()
            activeRouteQueries.insert(query)
            routeQueryLock.unlock()
            store?.execute(query)
        }
    
    //MARK: - 스플릿 계산
    func calculateSplits(from samples: [DistanceSample]) -> [DistSplit] {
        guard !samples.isEmpty else { return [] }
        
        var splits: [DistSplit] = []
        var accumulated = 0.0
        var kmStart = samples[0].startDate
        var currentKm = 1
        
        for sample in samples {
            let prevAccumulated = accumulated
            accumulated += sample.distance
            
            while accumulated >= Double(currentKm) * 1000 {
                let distIntoSample = Double(currentKm) * 1000 - prevAccumulated
                let fraction = sample.distance > 0 ? distIntoSample / sample.distance : 1.0
                let sampleDuration = sample.endDate.timeIntervalSince(sample.startDate)
                let crossingTime = sample.startDate.addingTimeInterval(sampleDuration * fraction)
                
                let pace = crossingTime.timeIntervalSince(kmStart)
                splits.append(DistSplit(
                    id: currentKm,
                    pace: pace,
                    distance: 1000,
                    startDate: kmStart,
                    endDate: crossingTime
                ))
                kmStart = crossingTime
                currentKm += 1
            }
        }
        
        // 마지막 불완전 km
        if let last = samples.last {
            let remaining = accumulated - Double(currentKm - 1) * 1000
            if remaining > 100 {
                let elapsed = last.endDate.timeIntervalSince(kmStart)
                let actualPace = elapsed / (remaining / 1000)
                splits.append(DistSplit(
                    id: currentKm,
                    pace: actualPace,
                    distance: remaining,
                    startDate: kmStart,
                    endDate: last.endDate))
            }
        }
        return splits
    }
    
    //스플릿 보강
    func enrichSplits(
        _ splits: inout [DistSplit],
        heartRates: [HeartRateSample],
        steps: [QuantitySamplePoint],
        strideLengths: [QuantitySamplePoint],
        verticalOscillations: [QuantitySamplePoint],
        powers: [QuantitySamplePoint],
        speeds: [QuantitySamplePoint],
        groundContactTimes: [QuantitySamplePoint],
        altitudes: [AltitudePoint]
    ) {
        for i in splits.indices {
            let start = splits[i].startDate
            let end = splits[i].endDate
            
            //심박수
            let hrInRange = heartRates.filter { $0.date >= start && $0.date < end }
            if !hrInRange.isEmpty {
                splits[i].avgHeartRate = hrInRange.reduce(0) { $0 + $1.bpm } / Double(hrInRange.count)
            }
            
            //케이던스
            let stepsInRange = steps.filter { $0.startDate >= start && $0.startDate < end }
            if !stepsInRange.isEmpty {
                let totalSteps = stepsInRange.reduce(0) { $0 + $1.value }
                let durationMin = end.timeIntervalSince(start) / 60
                if durationMin > 0 {
                    splits[i].avgCadence = totalSteps / durationMin
                }
            }
            
            //보폭
            splits[i].avgStrideLength = averageValue(
                of: strideLengths, from: start, to: end)
            //수직진폭
            splits[i].avgVerticalOscillation = averageValue(
                of: verticalOscillations, from: start, to: end)
            //파워
            splits[i].avgPower = averageValue(
                of: powers, from: start, to: end)
            //속도
            splits[i].avgSpeed = averageValue(
                of: speeds, from: start, to: end)
            //지면 접촉 시간
            splits[i].avgGroundContactTime = averageValue(
                of: groundContactTimes, from: start, to: end)
            
            //고도
            let altsInRange = altitudes.filter { $0.date >= start && $0.date <= end }
            if altsInRange.count >= 2 {
                splits[i].elevationChange = (altsInRange.last!.altitude) - (altsInRange.first!.altitude)
            }
        }
    }

    private func averageValue(of samples: [QuantitySamplePoint], from start: Date, to end: Date) -> Double? {
            let inRange = samples.filter { $0.startDate >= start && $0.startDate < end }
            guard !inRange.isEmpty else { return nil }
            return inRange.reduce(0) { $0 + $1.value } / Double(inRange.count)
        }
    
    //루트 디버깅
    func debugAllRoutes() {
        guard let store else { return }
        let routeType = HKSeriesType.workoutRoute()
        let query = HKSampleQuery(
            sampleType: routeType,
            predicate: nil,
            limit: 5,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        ) { _, samples, error in
            if let error { print("[Route Debug] ❌ 전체 루트 조회 실패: \(error)") }
            let count = samples?.count ?? 0
            samples?.forEach { print("[Route Debug] 📍 루트 발견: \($0.startDate) ~ \($0.endDate)") }
        }
        store.execute(query)
    }
}

@available(iOS 26.0, *)
extension HealthKitStore: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for sampleType in collectedTypes {
            guard let quantityType = sampleType as? HKQuantityType,
                  quantityType == HKQuantityType.quantityType(forIdentifier: .heartRate),
                  let statistics = workoutBuilder.statistics(for: quantityType)
            else { continue }

            let unit = HKUnit.count().unitDivided(by: .minute())
            let mostRecent = statistics.mostRecentQuantity()?.doubleValue(for: unit)
            let average = statistics.averageQuantity()?.doubleValue(for: unit)

            DispatchQueue.main.async { [weak self] in
                self?.updatePhoneWorkoutHeartRateMetrics(
                    heartRate: mostRecent,
                    avgHeartRate: average
                )
            }
        }
    }
}

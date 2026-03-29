//
//  HealthKitStore.swift
//  Hanttam
//
//  Created by passi on 3/25/26.
//

import Foundation
import HealthKit
import CoreLocation

final class HealthKitStore {
    
    static let shared = HealthKitStore()
    
    private var store              : HKHealthStore?
    private let routeQueryLock     = NSLock()
    private var activeRouteQueries = Set<HKWorkoutRouteQuery>()
    
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    
    private init() {
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
        
        store.requestAuthorization(toShare: nil, read: readTypes) { ok, _ in
            DispatchQueue.main.async {
                completion(ok)
            }
        }
    }
    
    //MARK: - 데이터 조회
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
            let records = (samples as? [HKWorkout])?.map { w in
                RunningRecord(
                    date    : w.startDate,
                    endDate : w.endDate,
                    duration: w.duration,
                    distance: w.totalDistance?.doubleValue(for: .meter()) ?? 0,
                    calories: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                    workout : w)
            } ?? []
            DispatchQueue.main.async {
                completion(records)
            }
        }
        store.execute(query)
    }
    
    //심박수 조회
    func fetchHeartRateSamples(
        from start: Date,
        to   end  : Date,
        completion: @escaping ([HeartRateSample]) -> Void
    ) {
        guard let store else { completion([]); return }
        
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true)
        
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
        identifider: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date,
        completion: @escaping ([QuantitySamplePoint]) -> Void
    ) {
        guard let store,
              let type = HKQuantityType.quantityType(forIdentifier: identifider)
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
    func fetchAltitudeData(
        for workout: HKWorkout,
        completion : @escaping ([AltitudePoint]) -> Void) {
            guard let store else { completion([]); return }
            
            let routeStatus   = store.authorizationStatus(for: HKSeriesType.workoutRoute())
            let workoutStatus = store.authorizationStatus(for: HKObjectType.workoutType())
            
            fetchRouteLocations(for: workout, completion: completion)
        }
    
    private func fetchRouteLocations(
        for workout: HKWorkout,
        completion: @escaping ([AltitudePoint]) -> Void) {
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
                    
                }
            }
            store.execute(query)
        }
    
    private func fetchRouteByDate(
        for workout: HKWorkout,
        completion: @escaping ([AltitudePoint]) -> Void) {
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
    
    private func fetchLocations(
        from route: HKWorkoutRoute,
        completion: @escaping ([AltitudePoint]) -> Void) {
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
            
            //heartRate
            let hrInRange = heartRates.filter { $0.date >= start && $0.date < end }
            if !hrInRange.isEmpty {
                splits[i].avgHeartRate = hrInRange.reduce(0) { $0 + $1.bpm } / Double(hrInRange.count)
            }
            
            //cadence
            let stepsInRange = steps.filter { $0.startDate >= start && $0.startDate < end }
            if !stepsInRange.isEmpty {
                let totalSteps = stepsInRange.reduce(0) { $0 + $1.value }
                let durationMin = end.timeIntervalSince(start) / 60
                if durationMin > 0 {
                    splits[i].avgCadence = totalSteps / durationMin
                }
            }
            
            //strideLength
            splits[i].avgStrideLength = averageValue(
                of: strideLengths, from: start, to: end)
            //verticalOscillation
            splits[i].avgVerticalOscillation = averageValue(
                of: verticalOscillations, from: start, to: end)
            //power
            splits[i].avgPower = averageValue(
                of: powers, from: start, to: end)
            //speed
            splits[i].avgSpeed = averageValue(
                of: speeds, from: start, to: end)
            //groundContactTime
            splits[i].avgGroundContactTime = averageValue(
                of: groundContactTimes, from: start, to: end)
            
            // altitude
            let altsInRange = altitudes.filter { $0.date >= start && $0.date <= end }
            if altsInRange.count >= 2 {
                splits[i].elevationChange = (altsInRange.last!.altitude) - (altsInRange.first!.altitude)
            }
        }
    }

    private func averageValue(
        of samples: [QuantitySamplePoint],
        from start: Date,
        to end: Date) -> Double? {
            let inRange = samples.filter { $0.startDate >= start && $0.startDate < end }
            guard !inRange.isEmpty else { return nil }
            return inRange.reduce(0) { $0 + $1.value } / Double(inRange.count)
        }
    
}

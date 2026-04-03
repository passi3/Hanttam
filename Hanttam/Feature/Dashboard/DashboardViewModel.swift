//
//  DashboardViewModel.swift
//  Hanttam
//
//  Created by passi on 3/27/26.
//

import UIKit
import HealthKit
import RxCocoa
import RxSwift
import WidgetKit

final class DashboardViewModel: HTReusableVMProtocol {
    
    struct Input {
        let viewDidLoad: Observable<Void>
    }
    
    struct Output {
        let level         : Driver<UserRunningLevel>
        let totalDistance : Driver<Double>
        let progress      : Driver<Double>
        let remainingDist : Driver<Double>
        let thisMonthDaily: Driver<[DailyCumulativeDistance]>
        let lastMonthDaily: Driver<[DailyCumulativeDistance]>
        let thisMonthTotal: Driver<Double>
        let lastMonthTotal: Driver<Double>
        let calendarData  : Driver<[Date: DailyWorkoutInfo]>
        let isLoading     : Driver<Bool>
    }
    
    private let levelRelay          = BehaviorRelay<UserRunningLevel>(value: .yellow)
    private let totalDistanceRelay  = BehaviorRelay<Double>(value: 0)
    private let progressRelay       = BehaviorRelay<Double>(value: 0)
    private let remainingRelay      = BehaviorRelay<Double>(value: 0)
    private let thisMonthDailyRelay = BehaviorRelay<[DailyCumulativeDistance]>(value: [])
    private let lastMonthDailyRelay = BehaviorRelay<[DailyCumulativeDistance]>(value: [])
    private let thisMonthTotalRelay = BehaviorRelay<Double>(value: 0)
    private let lastMonthTotalRelay = BehaviorRelay<Double>(value: 0)
    private let calendarDateRelay   = BehaviorRelay<[Date: DailyWorkoutInfo]>(value: [:])
    private let isLoadingRelay      = BehaviorRelay<Bool>(value: false)
    
    private let store        = HealthKitStore.shared
    private let levelManager = RunningLevelManager.shared
    private let disposeBag   = DisposeBag()
    
    func transform(input: Input) -> Output {
        input.viewDidLoad
            .subscribe(onNext: { [weak self] in self?.fetchData()})
            .disposed(by: disposeBag)
        
        return Output(
            level         : levelRelay.asDriver(),
            totalDistance : totalDistanceRelay.asDriver(),
            progress      : progressRelay.asDriver(),
            remainingDist : remainingRelay.asDriver(),
            thisMonthDaily: thisMonthDailyRelay.asDriver(),
            lastMonthDaily: lastMonthDailyRelay.asDriver(),
            thisMonthTotal: thisMonthTotalRelay.asDriver(),
            lastMonthTotal: lastMonthTotalRelay.asDriver(),
            calendarData  : calendarDateRelay.asDriver(),
            isLoading     : isLoadingRelay.asDriver())
    }
    
    private func fetchData() {
        isLoadingRelay.accept(true)
        store.requestAuthorization { [weak self] ok in
            guard ok else {
                self?.isLoadingRelay.accept(false)
                return
            }
            self?.store.fetchRunningWorkouts { [weak self] (records: [RunningRecord]) in
                guard let self else { return }
                let (thisMonth, lastMonth) = self.buildCumulativeData(from: records)
                self.thisMonthDailyRelay.accept(thisMonth)
                self.lastMonthDailyRelay.accept(lastMonth)
                let thisTotal = thisMonth.last?.cumulativeDistance ?? 0
                let lastTotal = lastMonth.last?.cumulativeDistance ?? 0
                self.thisMonthTotalRelay.accept(thisTotal)
                self.lastMonthTotalRelay.accept(lastTotal)
                self.calendarDateRelay.accept(self.buildCalendarData(from: records))
                
                RunningLevelManager.shared.update(with: records) {
                    self.levelRelay.accept(self.levelManager.level)
                    self.totalDistanceRelay.accept(self.levelManager.totalDistance)
                    self.progressRelay.accept(self.levelManager.progress)
                    self.remainingRelay.accept(self.levelManager.remainingDist)
                    self.isLoadingRelay.accept(false)
                }
            }
        }
    }
    
    private func buildCumulativeData(from records: [RunningRecord]) -> ([DailyCumulativeDistance], [DailyCumulativeDistance]) {
        let cal = Calendar.current
        let now = Date()
        
        guard let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let lastMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonthStart) else {
            return ([], [])
        }
        
        let thisMonthRecords = records.filter { $0.date >= thisMonthStart }
        let lastMonthRecords = records.filter { $0.date >= lastMonthStart && $0.date < thisMonthStart }
        
        let daysInThisMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let daysInLastMonth = cal.range(of: .day, in: .month, for: lastMonthStart)?.count ?? 30
        
        let thisMonthDaily = buildDaily(records: thisMonthRecords,
                                        monthStart: thisMonthStart,
                                        dayCount: daysInThisMonth)
        let lastMonthDaily = buildDaily(records: lastMonthRecords,
                                        monthStart: lastMonthStart,
                                        dayCount: daysInLastMonth)
        
        return (thisMonthDaily, lastMonthDaily)
    }
    
    private func buildDaily(records: [RunningRecord], monthStart: Date, dayCount: Int) -> [DailyCumulativeDistance] {
        let cal            = Calendar.current
        var dailyDistances = [Int: Double]()
        
        for record in records {
            let day = cal.component(.day, from: record.date)
            dailyDistances[day, default: 0] += record.distance
        }
        
        var cumulative = 0.0
        var result     = [DailyCumulativeDistance]()
        for day in 1...dayCount {
            cumulative += (dailyDistances[day] ?? 0) / 1000
            result.append(DailyCumulativeDistance(day: day, cumulativeDistance: cumulative))
        }
        return result
    }
    
    private func buildCalendarData(from records: [RunningRecord]) -> [Date: DailyWorkoutInfo] {
        let cal = Calendar.current
        var grouped = [Date: (distance: Double, duration: TimeInterval, count: Int)]()
        
        for record in records {
            let dayStart = cal.startOfDay(for: record.date)
            var entry = grouped[dayStart] ?? (0, 0, 0)
            entry.distance    += record.distance
            entry.duration    += record.duration
            entry.count       += 1
            grouped[dayStart] = entry
        }
        
        var result = [Date: DailyWorkoutInfo]()
        for (date, data) in grouped {
            result[date] = DailyWorkoutInfo(
                id: date,
                date: date,
                totalDistance: data.distance,
                totalDuration: data.duration,
                workoutCount : data.count
            )
        }
        return result
    }
    
}

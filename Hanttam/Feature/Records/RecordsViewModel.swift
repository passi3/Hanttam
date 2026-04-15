//
//  RecordsViewModel.swift
//  Hanttam
//
//  Created by passi on 3/31/26.
//

import Foundation
import Combine
import RxCocoa
import RxSwift
internal import HealthKit

final class RecordsViewModel: HTReusableVMProtocol, ObservableObject {

    struct Input {
        let viewDidLoad : Observable<Void>
        let refresh     : Observable<Void>
        let selectRecord: Observable<Int>
    }

    struct Output {
        let records        : Driver<[RunningRecord]>
        let filteredRecords: Driver<[RunningRecord]>
        let isLoading      : Driver<Bool>
        let selectedRecord : Driver<RunningRecord>
    }

    // MARK: - ObservableObject state (SwiftUI interop via RunningChartView)

    @Published var period: ChartPeriod = .monthly {
        didSet { periodRelay.accept(period) }
    }
    @Published var offset: Int = 0 {
        didSet { offsetRelay.accept(offset) }
    }
    @Published private(set) var records: [RunningRecord] = []

    // MARK: - Rx relays

    private let recordsRelay         = BehaviorRelay<[RunningRecord]>(value: [])
    private let filteredRecordsRelay = BehaviorRelay<[RunningRecord]>(value: [])
    private let periodRelay          = BehaviorRelay<ChartPeriod>(value: .monthly)
    private let offsetRelay          = BehaviorRelay<Int>(value: 0)
    private let isLoadingRelay       = BehaviorRelay<Bool>(value: false)
    private let selectedRecordRelay  = PublishRelay<RunningRecord>()
    private let disposeBag           = DisposeBag()

    private let store = HealthKitStore.shared

    init() {
        recordsRelay
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] in self?.records = $0 })
            .disposed(by: disposeBag)

        Observable.combineLatest(recordsRelay, periodRelay, offsetRelay)
            .map { Self.filterRecords($0, period: $1, offset: $2) }
            .bind(to: filteredRecordsRelay)
            .disposed(by: disposeBag)
    }

    // MARK: - Transform

    func transform(input: Input) -> Output {
        Observable.merge(input.viewDidLoad, input.refresh)
            .subscribe(onNext: { [weak self] in self?.fetchRecords() })
            .disposed(by: disposeBag)

        input.selectRecord
            .withLatestFrom(filteredRecordsRelay) { index, list -> RunningRecord? in
                guard index < list.count else { return nil }
                return list[index]
            }
            .compactMap { $0 }
            .bind(to: selectedRecordRelay)
            .disposed(by: disposeBag)

        return Output(
            records        : recordsRelay.asDriver(),
            filteredRecords: filteredRecordsRelay.asDriver(),
            isLoading      : isLoadingRelay.asDriver(),
            selectedRecord : selectedRecordRelay.asDriver(onErrorDriveWith: .empty())
        )
    }

    // MARK: - Delete

    func deleteRecord(_ record: RunningRecord, completion: @escaping (Bool, Error?) -> Void) {
        guard let workout = record.workout else { completion(false, nil); return }
        store.deleteWorkout(workout) { [weak self] success, error in
            if success {
                var current = self?.recordsRelay.value ?? []
                current.removeAll { $0 == record }
                self?.recordsRelay.accept(current)
                RunningLevelManager.shared.update(with: current)
            }
            completion(success, error)
        }
    }

    // MARK: - Private

    private func fetchRecords() {
        isLoadingRelay.accept(true)
        store.requestAuthorization { [weak self] ok in
            guard ok else { self?.isLoadingRelay.accept(false); return }
            self?.store.debugAllRoutes()
            self?.store.fetchRunningWorkouts { [weak self] (items: [RunningRecord]) in
                self?.recordsRelay.accept(items)
                RunningLevelManager.shared.update(with: items)
                self?.isLoadingRelay.accept(false)
            }
        }
    }

    private static func filterRecords(_ records: [RunningRecord], period: ChartPeriod, offset: Int) -> [RunningRecord] {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .weekly:
            let today          = cal.startOfDay(for: now)
            let weekday        = cal.component(.weekday, from: today)
            let daysFromMonday = (weekday + 5) % 7
            let currentMonday  = cal.date(byAdding: .day, value: -daysFromMonday, to: today)!
            let monday         = cal.date(byAdding: .weekOfYear, value: offset, to: currentMonday)!
            let sunday         = cal.date(byAdding: .day, value: 7, to: monday)!
            return records.filter { $0.date >= monday && $0.date < sunday }
        case .monthly:
            let comps       = cal.dateComponents([.year, .month], from: now)
            let baseMonth   = cal.date(from: comps)!
            let targetMonth = cal.date(byAdding: .month, value: offset, to: baseMonth)!
            let nextMonth   = cal.date(byAdding: .month, value: 1, to: targetMonth)!
            return records.filter { $0.date >= targetMonth && $0.date < nextMonth }
        case .yearly:
            let targetYear = cal.component(.year, from: now) + offset
            return records.filter { cal.component(.year, from: $0.date) == targetYear }
        case .all:
            return records
        }
    }
}

//
//  ShoeDetailViewModel.swift
//  Hanttam
//
//  Created by passi on 4/8/26.
//

import Foundation
import RxCocoa
import RxSwift

enum GearSessionNavigationTarget {
    case freeRun(RunningRecord)
    case interval(record: RunningRecord, intervalRecord: IntervalRecord)
}

final class ShoeDetailViewModel: HTReusableVMProtocol {
    struct ViewData: Hashable {
        let shoe: RegisteredShoe
        let stats: ShoeAggregateStats
        let sessions: [GearLinkedSessionItem]
    }

    struct Input {
        let viewDidLoad: Observable<Void>
        let selectSession: Observable<Int>
    }

    struct Output {
        let viewData: Driver<ViewData>
        let isLoading: Driver<Bool>
        let showErrorMessage: Signal<String>
        let showSessionDetail: Signal<GearSessionNavigationTarget>
    }

    private let shoe: RegisteredShoe
    private let viewDataRelay: BehaviorRelay<ViewData>
    private let isLoadingRelay = BehaviorRelay<Bool>(value: false)
    private let errorRelay = PublishRelay<String>()
    private let sessionDetailRelay = PublishRelay<GearSessionNavigationTarget>()
    private let disposeBag = DisposeBag()

    private let store: GearLocalStoring
    private let healthStore: HealthKitStore

    init(
        shoe: RegisteredShoe,
        store: GearLocalStoring = GearLocalStore.shared,
        healthStore: HealthKitStore = .shared
    ) {
        self.shoe = shoe
        self.store = store
        self.healthStore = healthStore
        self.viewDataRelay = BehaviorRelay(
            value: ViewData(
                shoe: shoe,
                stats: ShoeAggregateStats(
                    totalDistance: shoe.initialDistanceMeters,
                    totalDuration: 0,
                    targetDistanceMeters: shoe.targetDistanceMeters,
                    paceDistanceMeters: 0
                ),
                sessions: []
            )
        )
    }

    func transform(input: Input) -> Output {
        Observable.merge(
            input.viewDidLoad,
            NotificationCenter.default.rx.notification(GearLocalStore.didChangeNotification).map { _ in () }
        )
        .subscribe(onNext: { [weak self] in
            self?.loadData()
        })
        .disposed(by: disposeBag)

        input.selectSession
            .withLatestFrom(viewDataRelay) { index, data -> GearLinkedSessionItem? in
                guard data.sessions.indices.contains(index) else { return nil }
                return data.sessions[index]
            }
            .compactMap { $0 }
            .subscribe(onNext: { [weak self] session in
                self?.route(to: session)
            })
            .disposed(by: disposeBag)

        return Output(
            viewData: viewDataRelay.asDriver(),
            isLoading: isLoadingRelay.asDriver(),
            showErrorMessage: errorRelay.asSignal(),
            showSessionDetail: sessionDetailRelay.asSignal()
        )
    }

    private func loadData() {
        isLoadingRelay.accept(true)
        healthStore.requestAuthorization { [weak self] authorized in
            guard let self else { return }
            guard authorized else {
                self.viewDataRelay.accept(
                    ViewData(
                        shoe: self.shoe,
                        stats: ShoeAggregateStats(
                            totalDistance: self.shoe.initialDistanceMeters,
                            totalDuration: 0,
                            targetDistanceMeters: self.shoe.targetDistanceMeters,
                            paceDistanceMeters: 0
                        ),
                        sessions: []
                    )
                )
                self.errorRelay.accept("HealthKit 권한이 없어 세션 통계를 불러오지 못했습니다.")
                self.isLoadingRelay.accept(false)
                return
            }

            let group = DispatchGroup()
            var runningRecords: [RunningRecord] = []
            var intervalRecords: [IntervalRecord] = []

            group.enter()
            self.healthStore.fetchRunningWorkouts { records in
                runningRecords = records
                group.leave()
            }

            group.enter()
            self.healthStore.fetchIntervalWorkouts { intervals in
                intervalRecords = intervals
                group.leave()
            }

            group.notify(queue: .main) {
                let links = self.store.fetchSessionLinks()
                let sessions = GearSessionResolver.linkedSessions(
                    for: self.shoe,
                    links: links,
                    runningRecords: runningRecords,
                    intervalRecords: intervalRecords
                )
                let sessionDistance = sessions.reduce(0) { $0 + $1.distance }
                let totalDuration = sessions.reduce(0) { $0 + $1.duration }
                let totalDistance = self.shoe.initialDistanceMeters + sessionDistance
                self.viewDataRelay.accept(
                    ViewData(
                        shoe: self.shoe,
                        stats: ShoeAggregateStats(
                            totalDistance: totalDistance,
                            totalDuration: totalDuration,
                            targetDistanceMeters: self.shoe.targetDistanceMeters,
                            paceDistanceMeters: sessionDistance
                        ),
                        sessions: sessions
                    )
                )
                self.isLoadingRelay.accept(false)
            }
        }
    }

    private func route(to session: GearLinkedSessionItem) {
        switch session.sessionKind {
        case .freeRun:
            if let record = session.runningRecord {
                sessionDetailRelay.accept(.freeRun(record))
            }
        case .interval:
            if let record = session.runningRecord, let intervalRecord = session.intervalRecord {
                sessionDetailRelay.accept(.interval(record: record, intervalRecord: intervalRecord))
            }
        }
    }
}

//
//  ShoeDetailViewModel.swift
//  Hanttam
//
//  Created by passi on 4/8/26.
//

import Foundation
import RxCocoa
import RxSwift

final class ShoeDetailViewModel: HTReusableVMProtocol {
    struct ViewData: Hashable {
        let shoe: RegisteredShoe
        let stats: ShoeAggregateStats
        let sessions: [GearLinkedSessionItem]
    }

    struct Input {
        let viewDidLoad: Observable<Void>
    }

    struct Output {
        let viewData: Driver<ViewData>
        let isLoading: Driver<Bool>
        let showErrorMessage: Signal<String>
    }

    private let shoeID: UUID
    private let fallbackShoe: RegisteredShoe
    private let viewDataRelay: BehaviorRelay<ViewData>
    private let isLoadingRelay = BehaviorRelay<Bool>(value: false)
    private let errorRelay = PublishRelay<String>()
    private let disposeBag = DisposeBag()

    private let store: GearLocalStoring
    private let healthStore: HealthKitStore

    init(
        shoe: RegisteredShoe,
        store: GearLocalStoring = GearLocalStore.shared,
        healthStore: HealthKitStore = .shared
    ) {
        self.shoeID = shoe.id
        self.fallbackShoe = shoe
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

        return Output(
            viewData: viewDataRelay.asDriver(),
            isLoading: isLoadingRelay.asDriver(),
            showErrorMessage: errorRelay.asSignal()
        )
    }

    private func loadData() {
        let resolvedShoe = store.fetchRegisteredShoes().first(where: { $0.id == shoeID }) ?? fallbackShoe
        isLoadingRelay.accept(true)
        healthStore.requestAuthorization { [weak self] authorized in
            guard let self else { return }
            guard authorized else {
                self.viewDataRelay.accept(
                    ViewData(
                        shoe: resolvedShoe,
                        stats: ShoeAggregateStats(
                            totalDistance: resolvedShoe.initialDistanceMeters,
                            totalDuration: 0,
                            targetDistanceMeters: resolvedShoe.targetDistanceMeters,
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
                    for: resolvedShoe,
                    links: links,
                    runningRecords: runningRecords,
                    intervalRecords: intervalRecords
                )
                let sessionDistance = sessions.reduce(0) { $0 + $1.distance }
                let totalDuration = sessions.reduce(0) { $0 + $1.duration }
                let totalDistance = resolvedShoe.initialDistanceMeters + sessionDistance
                self.viewDataRelay.accept(
                    ViewData(
                        shoe: resolvedShoe,
                        stats: ShoeAggregateStats(
                            totalDistance: totalDistance,
                            totalDuration: totalDuration,
                            targetDistanceMeters: resolvedShoe.targetDistanceMeters,
                            paceDistanceMeters: sessionDistance
                        ),
                        sessions: sessions
                    )
                )
                self.isLoadingRelay.accept(false)
            }
        }
    }
}

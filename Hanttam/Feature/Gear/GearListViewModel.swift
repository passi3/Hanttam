//
//  GearListViewModel.swift
//  Hanttam
//
//  Created by Codex on 4/8/26.
//

import Foundation
import RxCocoa
import RxSwift

final class GearListViewModel: HTReusableVMProtocol {
    struct Item: Hashable {
        let shoe: RegisteredShoe
        let stats: ShoeAggregateStats
        let linkedSessionsCount: Int
    }

    struct Input {
        let viewDidLoad: Observable<Void>
        let refresh: Observable<Void>
        let addTap: Observable<Void>
        let selectItem: Observable<Int>
    }

    struct Output {
        let items: Driver<[Item]>
        let isLoading: Driver<Bool>
        let isEmpty: Driver<Bool>
        let showErrorMessage: Signal<String>
        let showSearch: Signal<Void>
        let showDetail: Signal<RegisteredShoe>
    }

    private let itemsRelay = BehaviorRelay<[Item]>(value: [])
    private let isLoadingRelay = BehaviorRelay<Bool>(value: false)
    private let errorRelay = PublishRelay<String>()
    private let showSearchRelay = PublishRelay<Void>()
    private let showDetailRelay = PublishRelay<RegisteredShoe>()
    private let disposeBag = DisposeBag()

    private let store: GearLocalStoring
    private let healthStore: HealthKitStore

    init(
        store: GearLocalStoring = GearLocalStore.shared,
        healthStore: HealthKitStore = .shared
    ) {
        self.store = store
        self.healthStore = healthStore
    }

    func transform(input: Input) -> Output {
        Observable.merge(
            input.viewDidLoad,
            input.refresh,
            NotificationCenter.default.rx.notification(GearLocalStore.didChangeNotification).map { _ in () }
        )
        .subscribe(onNext: { [weak self] in
            self?.loadItems()
        })
        .disposed(by: disposeBag)

        input.addTap
            .bind(to: showSearchRelay)
            .disposed(by: disposeBag)

        input.selectItem
            .withLatestFrom(itemsRelay) { index, items -> RegisteredShoe? in
                guard items.indices.contains(index) else { return nil }
                return items[index].shoe
            }
            .compactMap { $0 }
            .bind(to: showDetailRelay)
            .disposed(by: disposeBag)

        return Output(
            items: itemsRelay.asDriver(),
            isLoading: isLoadingRelay.asDriver(),
            isEmpty: itemsRelay.map(\.isEmpty).asDriver(onErrorJustReturn: true),
            showErrorMessage: errorRelay.asSignal(),
            showSearch: showSearchRelay.asSignal(),
            showDetail: showDetailRelay.asSignal()
        )
    }

    private func loadItems() {
        isLoadingRelay.accept(true)
        let shoes = store.fetchRegisteredShoes()
        guard !shoes.isEmpty else {
            itemsRelay.accept([])
            isLoadingRelay.accept(false)
            return
        }

        healthStore.requestAuthorization { [weak self] authorized in
            guard let self else { return }
            guard authorized else {
                let zeroItems = shoes.map {
                    Item(
                        shoe: $0,
                        stats: ShoeAggregateStats(totalDistance: 0, totalDuration: 0, targetDistanceMeters: $0.targetDistanceMeters),
                        linkedSessionsCount: 0
                    )
                }
                self.itemsRelay.accept(zeroItems)
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
                let items = shoes.map { shoe -> Item in
                    let sessions = GearSessionResolver.linkedSessions(
                        for: shoe,
                        links: links,
                        runningRecords: runningRecords,
                        intervalRecords: intervalRecords
                    )
                    let totalDistance = sessions.reduce(0) { $0 + $1.distance }
                    let totalDuration = sessions.reduce(0) { $0 + $1.duration }
                    return Item(
                        shoe: shoe,
                        stats: ShoeAggregateStats(
                            totalDistance: totalDistance,
                            totalDuration: totalDuration,
                            targetDistanceMeters: shoe.targetDistanceMeters
                        ),
                        linkedSessionsCount: sessions.count
                    )
                }
                self.itemsRelay.accept(items)
                self.isLoadingRelay.accept(false)
            }
        }
    }
}

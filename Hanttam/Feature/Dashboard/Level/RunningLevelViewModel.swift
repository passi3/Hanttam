//
//  RunningLevelViewModel.swift
//  Hanttam
//
//  Created by passi on 3/30/26.
//

import UIKit
import Combine
import RxCocoa
import RxSwift

final class RunningLevelViewModel: HTReusableVMProtocol {
    
    struct LevelItem {
        let level     : UserRunningLevel
        let isCurrent : Bool
        let isAchieved: Bool
    }
    
    struct Input {
        let viewDidLoad: Observable<Void>
    }
    struct Output {
        let level          : Driver<UserRunningLevel>
        let totalDistanceKm: Driver<Double>
        let progress       : Driver<Double>
        let remainingKm    : Driver<Double>
        let levelItems     : Driver<[LevelItem]>
    }
    
    private let manager    = RunningLevelManager.shared
    private let disposeBag = DisposeBag()
    
    func transform(input: Input) -> Output {
        let level = Observable<UserRunningLevel>.create { [weak manager] observer in
            let cancellable = manager?.$level.sink { observer.onNext($0) }
            return Disposables.create { cancellable?.cancel() }
        }
        .asDriver(onErrorDriveWith: .empty())

        let totalDistance = Observable<Double>.create { [weak manager] observer in
            let cancellable = manager?.$totalDistance.sink { observer.onNext($0) }
            return Disposables.create { cancellable?.cancel() }
        }
        .asDriver(onErrorDriveWith: .empty())

        let progress = Driver.combineLatest(level, totalDistance)
            .map { level, total -> Double in
                guard let next = level.nextThreshold else { return 1.0 }
                let base = level.threshold
                let range = next - base
                guard range > 0 else { return 1.0 }
                return min((total - base) / range, 1.0)
            }

        let remainingKm = Driver.combineLatest(level, totalDistance)
            .map { level, total -> Double in
                guard let next = level.nextThreshold else { return 0 }
                return max(next - total, 0)
            }

        let levelItems = Driver.combineLatest(level, totalDistance)
            .map { currentLevel, total -> [LevelItem] in
                UserRunningLevel.allCases.map { lvl in
                    LevelItem(
                        level: lvl,
                        isCurrent: lvl == currentLevel,
                        isAchieved: total >= lvl.threshold
                    )
                }
            }

        return Output(
            level: level,
            totalDistanceKm: totalDistance,
            progress: progress,
            remainingKm: remainingKm,
            levelItems: levelItems
        )
    }
}

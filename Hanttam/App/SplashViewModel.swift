//
//  SplashViewModel.swift
//  Hanttam
//

import Foundation
import RxSwift
import RxCocoa

final class SplashViewModel: HTReusableVMProtocol {

    struct Input {
        let viewDidAppear: Observable<Void>
    }

    struct Output {
        let transitionToMain: Signal<Void>
    }

    private let splashDuration: RxTimeInterval = .milliseconds(1400)
    private let disposeBag = DisposeBag()

    func transform(input: Input) -> Output {
        let transition = input.viewDidAppear
            .take(1)
            .delay(splashDuration, scheduler: MainScheduler.instance)
            .map { _ in () }
            .asSignal(onErrorSignalWith: .empty())

        return Output(transitionToMain: transition)
    }
}

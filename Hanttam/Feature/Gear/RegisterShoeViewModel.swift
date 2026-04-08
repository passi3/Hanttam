//
//  RegisterShoeViewModel.swift
//  Hanttam
//
//  Created by Codex on 4/8/26.
//

import Foundation
import RxCocoa
import RxSwift

final class RegisterShoeViewModel: HTReusableVMProtocol {
    struct Input {
        let targetDistanceText: Observable<String>
        let saveTap: Observable<Void>
    }

    struct Output {
        let item: Driver<ShoeCatalogItem>
        let isSaving: Driver<Bool>
        let errorMessage: Signal<String>
        let registeredShoe: Signal<RegisteredShoe>
    }

    let item: ShoeCatalogItem

    private let isSavingRelay = BehaviorRelay<Bool>(value: false)
    private let errorRelay = PublishRelay<String>()
    private let registeredRelay = PublishRelay<RegisteredShoe>()
    private let disposeBag = DisposeBag()

    private let store: GearLocalStoring

    init(item: ShoeCatalogItem, store: GearLocalStoring = GearLocalStore.shared) {
        self.item = item
        self.store = store
    }

    func transform(input: Input) -> Output {
        input.saveTap
            .withLatestFrom(input.targetDistanceText)
            .subscribe(onNext: { [weak self] text in
                self?.save(targetDistanceText: text)
            })
            .disposed(by: disposeBag)

        return Output(
            item: Driver.just(item),
            isSaving: isSavingRelay.asDriver(),
            errorMessage: errorRelay.asSignal(),
            registeredShoe: registeredRelay.asSignal()
        )
    }

    private func save(targetDistanceText: String) {
        let normalized = targetDistanceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard let kilometers = Double(normalized), kilometers > 0 else {
            errorRelay.accept("목표 거리를 km 단위로 입력해주세요.")
            return
        }

        isSavingRelay.accept(true)
        let shoe = RegisteredShoe(item: item, targetDistanceMeters: kilometers * 1000.0)
        store.saveRegisteredShoe(shoe)
        isSavingRelay.accept(false)
        registeredRelay.accept(shoe)
    }
}

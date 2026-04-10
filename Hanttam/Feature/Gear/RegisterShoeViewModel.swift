//
//  RegisterShoeViewModel.swift
//  Hanttam
//
//  Created by passi on 4/8/26.
//

import Foundation
import RxCocoa
import RxSwift

final class RegisterShoeViewModel: HTReusableVMProtocol {
    enum Mode {
        case catalog(ShoeCatalogItem)
        case manual

        var catalogItem: ShoeCatalogItem? {
            if case .catalog(let item) = self { return item }
            return nil
        }

        var isManual: Bool {
            if case .manual = self { return true }
            return false
        }
    }

    struct Input {
        let nicknameText: Observable<String>
        let selectedTargetDistance: Observable<Double?>
        let previousDistanceText: Observable<String>
        let saveTap: Observable<Void>
    }

    struct Output {
        let item: Driver<ShoeCatalogItem?>
        let isManual: Driver<Bool>
        let isSaving: Driver<Bool>
        let targetDistanceText: Driver<String?>
        let isRegisterEnabled: Driver<Bool>
        let errorMessage: Signal<String>
        let registeredShoe: Signal<RegisteredShoe>
    }

    let mode: Mode

    private let isSavingRelay = BehaviorRelay<Bool>(value: false)
    private let nicknameRelay = BehaviorRelay<String>(value: "")
    private let targetDistanceRelay = BehaviorRelay<Double?>(value: nil)
    private let previousDistanceRelay = BehaviorRelay<String>(value: "")
    private let errorRelay = PublishRelay<String>()
    private let registeredRelay = PublishRelay<RegisteredShoe>()
    private let disposeBag = DisposeBag()

    private let store: GearLocalStoring

    init(mode: Mode, store: GearLocalStoring = GearLocalStore.shared) {
        self.mode = mode
        self.store = store
    }

    convenience init(item: ShoeCatalogItem, store: GearLocalStoring = GearLocalStore.shared) {
        self.init(mode: .catalog(item), store: store)
    }

    func transform(input: Input) -> Output {
        input.nicknameText
            .bind(to: nicknameRelay)
            .disposed(by: disposeBag)

        input.selectedTargetDistance
            .bind(to: targetDistanceRelay)
            .disposed(by: disposeBag)

        input.previousDistanceText
            .bind(to: previousDistanceRelay)
            .disposed(by: disposeBag)

        input.saveTap
            .withLatestFrom(Observable.combineLatest(
                nicknameRelay.asObservable(),
                targetDistanceRelay.asObservable(),
                previousDistanceRelay.asObservable()
            ))
            .subscribe(onNext: { [weak self] nickname, targetDistance, previousDistance in
                self?.save(nicknameText: nickname, targetDistanceMeters: targetDistance, previousDistanceText: previousDistance)
            })
            .disposed(by: disposeBag)

        return Output(
            item: Driver.just(mode.catalogItem),
            isManual: Driver.just(mode.isManual),
            isSaving: isSavingRelay.asDriver(),
            targetDistanceText: targetDistanceRelay
                .map(Self.formatDistance(meters:))
                .asDriver(onErrorJustReturn: nil),
            isRegisterEnabled: Observable
                .combineLatest(
                    nicknameRelay.asObservable(),
                    targetDistanceRelay.asObservable(),
                    previousDistanceRelay.asObservable()
                )
                .map { [weak self] nickname, targetDistance, previousDistanceText in
                    guard let self, let targetDistance else { return false }
                    if self.mode.isManual {
                        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedNickname.isEmpty { return false }
                    }
                    let trimmedPreviousDistance = previousDistanceText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedPreviousDistance.isEmpty else { return true }
                    return self.validatePreviousDistance(trimmedPreviousDistance, targetDistanceMeters: targetDistance)
                }
                .asDriver(onErrorJustReturn: false),
            errorMessage: errorRelay.asSignal(),
            registeredShoe: registeredRelay.asSignal()
        )
    }

    func validatePreviousDistance(_ text: String, targetDistanceMeters: Double) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        guard let previousDistanceMeters = Self.parseDistanceMeters(from: normalized) else { return false }
        return previousDistanceMeters >= 0 && previousDistanceMeters <= targetDistanceMeters
    }

    private func save(nicknameText: String, targetDistanceMeters: Double?, previousDistanceText: String) {
        guard let targetDistanceMeters, targetDistanceMeters > 0 else {
            errorRelay.accept("목표 거리를 선택해주세요.")
            return
        }

        let previousDistanceMeters: Double
        let normalizedPreviousDistance = previousDistanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedPreviousDistance.isEmpty {
            previousDistanceMeters = 0
        } else if let value = Self.parseDistanceMeters(from: normalizedPreviousDistance),
                  value >= 0,
                  value <= targetDistanceMeters {
            previousDistanceMeters = value
        } else {
            errorRelay.accept("현재 거리는 0km 이상, 목표 거리 이하로 입력해주세요.")
            return
        }

        isSavingRelay.accept(true)
        let trimmedNickname = nicknameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNickname = trimmedNickname.isEmpty ? nil : trimmedNickname
        let shoe: RegisteredShoe
        switch mode {
        case .catalog(let item):
            shoe = RegisteredShoe(
                item: item,
                nickname: resolvedNickname,
                targetDistanceMeters: targetDistanceMeters,
                initialDistanceMeters: previousDistanceMeters
            )
        case .manual:
            guard let nickname = resolvedNickname else {
                isSavingRelay.accept(false)
                errorRelay.accept("별칭을 입력해주세요.")
                return
            }
            shoe = RegisteredShoe(
                catalogID: "manual-\(UUID().uuidString)",
                nickname: nickname,
                brandName: "",
                modelName: nickname,
                sku: "",
                colors: [],
                imageURL: nil,
                createdAt: Date(),
                targetDistanceMeters: targetDistanceMeters,
                initialDistanceMeters: previousDistanceMeters
            )
        }
        store.saveRegisteredShoe(shoe)
        isSavingRelay.accept(false)
        registeredRelay.accept(shoe)
    }

    private static func parseDistanceMeters(from text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let kilometers = Double(normalized) else { return nil }
        return kilometers * 1000.0
    }

    private static func formatDistance(meters: Double?) -> String? {
        guard let meters else { return nil }
        let kilometers = Int((meters / 1000.0).rounded())
        return "\(kilometers) km"
    }
}

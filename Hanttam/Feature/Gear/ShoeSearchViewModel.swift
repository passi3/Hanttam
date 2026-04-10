//
//  ShoeSearchViewModel.swift
//  Hanttam
//
//  Created by Codex on 4/8/26.
//

import Foundation
import RxCocoa
import RxSwift

final class ShoeSearchViewModel: HTReusableVMProtocol {
    struct Input {
        let viewDidLoad: Observable<Void>
        let query: Observable<String>
        let selectItem: Observable<Int>
    }

    struct Output {
        let results: Driver<[ShoeCatalogItem]>
        let isLoading: Driver<Bool>
        let statusText: Driver<String?>
        let selectedItem: Signal<ShoeCatalogItem>
    }

    private let resultsRelay = BehaviorRelay<[ShoeCatalogItem]>(value: [])
    private let isLoadingRelay = BehaviorRelay<Bool>(value: false)
    private let statusTextRelay = BehaviorRelay<String?>(value: "운동화를 선택하거나 모델명을 검색하세요.")
    private let selectedItemRelay = PublishRelay<ShoeCatalogItem>()
    private let disposeBag = DisposeBag()

    private let service: ShoeSearchServicing
    private let initialLimit = 20
    private let brand: ShoeBrand?

    init(brand: ShoeBrand? = nil, service: ShoeSearchServicing = SupabaseShoeSearchService()) {
        self.brand = brand
        self.service = service
    }

    func transform(input: Input) -> Output {
        input.viewDidLoad
            .subscribe(onNext: { [weak self] in
                self?.loadInitialCatalog()
            })
            .disposed(by: disposeBag)

        input.query
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .subscribe(onNext: { [weak self] query in
                self?.search(keyword: query)
            })
            .disposed(by: disposeBag)

        input.selectItem
            .withLatestFrom(resultsRelay) { index, items -> ShoeCatalogItem? in
                guard items.indices.contains(index) else { return nil }
                return items[index]
            }
            .compactMap { $0 }
            .bind(to: selectedItemRelay)
            .disposed(by: disposeBag)

        return Output(
            results: resultsRelay.asDriver(),
            isLoading: isLoadingRelay.asDriver(),
            statusText: statusTextRelay.asDriver(),
            selectedItem: selectedItemRelay.asSignal()
        )
    }

    private func loadInitialCatalog() {
        isLoadingRelay.accept(true)
        service.fetchInitialShoes(limit: initialLimit, brand: brand?.searchKeyword) { [weak self] result in
            guard let self else { return }
            self.isLoadingRelay.accept(false)
            switch result {
            case .success(let items):
                self.resultsRelay.accept(items)
                self.statusTextRelay.accept(items.isEmpty ? "등록 가능한 운동화가 없습니다." : nil)
            case .failure(let error):
                self.resultsRelay.accept([])
                self.statusTextRelay.accept(error.localizedDescription)
            }
        }
    }

    private func search(keyword: String) {
        isLoadingRelay.accept(true)
        service.searchShoes(keyword: keyword, brand: brand?.searchKeyword) { [weak self] result in
            guard let self else { return }
            self.isLoadingRelay.accept(false)
            switch result {
            case .success(let items):
                self.resultsRelay.accept(items)
                if keyword.isEmpty {
                    self.statusTextRelay.accept(items.isEmpty ? "등록 가능한 운동화가 없습니다." : nil)
                } else {
                    self.statusTextRelay.accept(items.isEmpty ? "검색 결과가 없습니다." : nil)
                }
            case .failure(let error):
                self.resultsRelay.accept([])
                self.statusTextRelay.accept(error.localizedDescription)
            }
        }
    }
}

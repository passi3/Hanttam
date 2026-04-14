//
//  ShoeBrandSelectViewModel.swift
//  Hanttam
//

import Foundation
import RxSwift
import RxCocoa

final class ShoeBrandSelectViewModel: HTReusableVMProtocol {

    struct Input {
        let viewDidLoad: Observable<Void>
        let searchText : Observable<String>
        let selectItem : Observable<Int>
    }

    struct Output {
        let filteredBrands: Driver<[BrandSummary]>
        let isLoading     : Driver<Bool>
        let statusText    : Driver<String?>
        let selectedBrand : Signal<BrandSummary>
    }

    private let service: BrandServicing
    private let allBrandsRelay    = BehaviorRelay<[BrandSummary]>(value: [])
    private let filteredRelay     = BehaviorRelay<[BrandSummary]>(value: [])
    private let isLoadingRelay    = BehaviorRelay<Bool>(value: false)
    private let statusRelay       = BehaviorRelay<String?>(value: nil)
    private let selectedRelay     = PublishRelay<BrandSummary>()
    private let disposeBag        = DisposeBag()

    init(service: BrandServicing = SupabaseShoeSearchService()) {
        self.service = service
    }

    func transform(input: Input) -> Output {
        input.viewDidLoad
            .take(1)
            .subscribe(onNext: { [weak self] in self?.fetchBrands() })
            .disposed(by: disposeBag)

        Observable.combineLatest(allBrandsRelay, input.searchText.startWith(""))
            .map { brands, query -> [BrandSummary] in
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? brands : brands.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            }
            .do(onNext: { [weak self] filtered in
                guard let self else { return }
                let all = self.allBrandsRelay.value
                if all.isEmpty {
                    self.statusRelay.accept("브랜드를 불러오는 중입니다.")
                } else if filtered.isEmpty {
                    self.statusRelay.accept("검색 결과가 없습니다.")
                } else {
                    self.statusRelay.accept(nil)
                }
            })
            .bind(to: filteredRelay)
            .disposed(by: disposeBag)

        input.selectItem
            .withLatestFrom(filteredRelay) { index, brands -> BrandSummary? in
                brands.indices.contains(index) ? brands[index] : nil
            }
            .compactMap { $0 }
            .bind(to: selectedRelay)
            .disposed(by: disposeBag)

        return Output(
            filteredBrands: filteredRelay.asDriver(),
            isLoading     : isLoadingRelay.asDriver(),
            statusText    : statusRelay.asDriver(),
            selectedBrand : selectedRelay.asSignal()
        )
    }

    private func fetchBrands() {
        isLoadingRelay.accept(true)
        statusRelay.accept("브랜드를 불러오는 중입니다.")
        service.fetchBrands { [weak self] result in
            guard let self else { return }
            self.isLoadingRelay.accept(false)
            switch result {
            case .success(let brands):
                self.allBrandsRelay.accept(brands)
                if brands.isEmpty { self.statusRelay.accept("등록 가능한 브랜드가 없습니다.") }
            case .failure(let error):
                self.allBrandsRelay.accept([])
                self.statusRelay.accept(error.localizedDescription)
            }
        }
    }
}

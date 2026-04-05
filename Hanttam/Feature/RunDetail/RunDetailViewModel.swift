//
//  RunDetailViewModel.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import Foundation
import Combine
internal import HealthKit

final class RunDetailViewModel {

    // MARK: - Detail Data

    struct DetailData {
        var heartRates: [HeartRateSample] = []
        var speedSamples: [QuantitySamplePoint] = []
        var stepSamples: [QuantitySamplePoint] = []
        var strideSamples: [QuantitySamplePoint] = []
        var voSamples: [QuantitySamplePoint] = []
        var powerSamples: [QuantitySamplePoint] = []
        var gctSamples: [QuantitySamplePoint] = []
        var altPoints: [AltitudePoint] = []
        var splits: [DistSplit] = []
    }

    // MARK: - Input

    struct Input {
        let viewDidLoad: AnyPublisher<Void, Never>
    }

    // MARK: - Output

    struct Output {
        let isLoading: AnyPublisher<Bool, Never>
        let data: AnyPublisher<DetailData, Never>
    }

    let record: RunningRecord

    private let isLoadingSubject = CurrentValueSubject<Bool, Never>(true)
    private let dataSubject = CurrentValueSubject<DetailData, Never>(DetailData())

    var data: AnyPublisher<DetailData, Never> { dataSubject.eraseToAnyPublisher() }
    private var cancellables = Set<AnyCancellable>()
    private let store = HealthKitStore.shared

    init(record: RunningRecord) {
        self.record = record
    }

    // MARK: - Transform

    func transform(input: Input) -> Output {
        input.viewDidLoad
            .sink { [weak self] in self?.loadDetails() }
            .store(in: &cancellables)

        return Output(
            isLoading: isLoadingSubject.eraseToAnyPublisher(),
            data: dataSubject.eraseToAnyPublisher()
        )
    }

    // MARK: - Private

    private func loadDetails() {
        isLoadingSubject.send(true)
        let group = DispatchGroup()
        let start = record.date
        let end = record.endDate
        var result = DetailData()

        group.enter()
        store.fetchHeartRateSamples(from: start, to: end) { s in
            result.heartRates = s; group.leave()
        }

        group.enter()
        store.fetchQuantitySamples(
            identifier: .runningSpeed,
            unit: .meter().unitDivided(by: .second()),
            from: start, to: end
        ) { s in result.speedSamples = s; group.leave() }

        group.enter()
        store.fetchQuantitySamples(
            identifier: .stepCount, unit: .count(),
            from: start, to: end
        ) { s in result.stepSamples = s; group.leave() }

        group.enter()
        store.fetchQuantitySamples(
            identifier: .runningStrideLength, unit: .meter(),
            from: start, to: end
        ) { s in result.strideSamples = s; group.leave() }

        group.enter()
        store.fetchQuantitySamples(
            identifier: .runningVerticalOscillation,
            unit: .meterUnit(with: .centi),
            from: start, to: end
        ) { s in result.voSamples = s; group.leave() }

        group.enter()
        store.fetchQuantitySamples(
            identifier: .runningPower, unit: .watt(),
            from: start, to: end
        ) { s in result.powerSamples = s; group.leave() }

        group.enter()
        store.fetchQuantitySamples(
            identifier: .runningGroundContactTime,
            unit: .secondUnit(with: .milli),
            from: start, to: end
        ) { s in result.gctSamples = s; group.leave() }

        group.enter()
        if let workout = record.workout {
            store.fetchAltitudeData(for: workout) { pts in
                result.altPoints = pts; group.leave()
            }
        } else {
            group.leave()
        }

        group.enter()
        store.fetchDistanceSamples(for: record.workout, from: start, to: end) { [weak self] samples in
            guard let self else { group.leave(); return }
            result.splits = self.store.calculateSplits(from: samples)
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            // 스플릿 보강 (심박수, 케이던스 등)
            if !result.splits.isEmpty {
                self.store.enrichSplits(
                    &result.splits,
                    heartRates: result.heartRates,
                    steps: result.stepSamples,
                    strideLengths: result.strideSamples,
                    verticalOscillations: result.voSamples,
                    powers: result.powerSamples,
                    speeds: result.speedSamples,
                    groundContactTimes: result.gctSamples,
                    altitudes: result.altPoints
                )
            }
            self.dataSubject.send(result)
            self.isLoadingSubject.send(false)
        }
    }
}

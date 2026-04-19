//
//  RunDetailViewModel.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import Foundation
import RxSwift
import RxCocoa
internal import HealthKit

final class RunDetailViewModel: HTReusableVMProtocol {

    // MARK: - Detail Data

    struct DetailData {
        var heartRates   : [HeartRateSample]       = []
        var speedSamples : [QuantitySamplePoint]   = []
        var stepSamples  : [QuantitySamplePoint]   = []
        var strideSamples: [QuantitySamplePoint]   = []
        var voSamples    : [QuantitySamplePoint]   = []
        var powerSamples : [QuantitySamplePoint]   = []
        var gctSamples   : [QuantitySamplePoint]   = []
        var altPoints    : [AltitudePoint]         = []
        var splits       : [DistSplit]             = []
        var lapRows      : [RunDetailLapRow]       = []
    }

    // MARK: - Input / Output

    struct Input {
        let viewDidLoad: Observable<Void>
    }

    struct Output {
        let isLoading: Driver<Bool>
        let data     : Driver<DetailData>
    }

    // MARK: - Public

    let record       : RunningRecord
    let intervalRecord: IntervalRecord?

    var dataDriver      : Driver<DetailData>    { dataRelay.asDriver() }
    var linkedShoeDriver: Driver<RegisteredShoe?> { linkedShoeRelay.asDriver() }

    // MARK: - Private

    private let isLoadingRelay  = BehaviorRelay<Bool>(value: true)
    private let dataRelay       = BehaviorRelay<DetailData>(value: DetailData())
    private let linkedShoeRelay = BehaviorRelay<RegisteredShoe?>(value: nil)
    private let disposeBag      = DisposeBag()

    private let store    : HealthKitStore
    private let gearStore: GearLocalStoring

    init(
        record: RunningRecord,
        intervalRecord: IntervalRecord? = nil,
        store: HealthKitStore = .shared,
        gearStore: GearLocalStoring = GearLocalStore.shared
    ) {
        self.record         = record
        self.intervalRecord = intervalRecord
        self.store          = store
        self.gearStore      = gearStore
    }

    // MARK: - Transform

    func transform(input: Input) -> Output {
        input.viewDidLoad
            .take(1)
            .subscribe(onNext: { [weak self] in
                self?.loadDetails()
                self?.refreshLinkedShoe()
            })
            .disposed(by: disposeBag)

        NotificationCenter.default.rx
            .notification(GearLocalStore.didChangeNotification)
            .subscribe(onNext: { [weak self] _ in self?.refreshLinkedShoe() })
            .disposed(by: disposeBag)

        return Output(
            isLoading: isLoadingRelay.asDriver(),
            data     : dataRelay.asDriver()
        )
    }

    // MARK: - Gear linking

    func fetchRegisteredShoes() -> [RegisteredShoe] {
        gearStore.fetchRegisteredShoes()
    }

    func refreshLinkedShoe() {
        linkedShoeRelay.accept(
            gearStore.linkedShoe(for: currentSessionIdentifier, kind: currentSessionKind)
        )
    }

    func linkCurrentSession(to shoe: RegisteredShoe) {
        let link = ShoeSessionLink(
            shoeID: shoe.id,
            sessionKind: currentSessionKind,
            sessionIdentifier: currentSessionIdentifier,
            workoutStartDate: currentSessionStartDate,
            workoutEndDate: currentSessionEndDate
        )
        gearStore.upsertSessionLink(link)
        refreshLinkedShoe()
    }

    func unlinkCurrentSession() {
        gearStore.removeSessionLink(sessionIdentifier: currentSessionIdentifier, kind: currentSessionKind)
        refreshLinkedShoe()
    }

    // MARK: - Private helpers

    private var currentSessionKind: GearSessionKind { intervalRecord == nil ? .freeRun : .interval }

    private var currentSessionIdentifier: String {
        intervalRecord?.gearSessionIdentifier ?? record.gearSessionIdentifier
    }

    private var currentSessionStartDate: Date { intervalRecord?.date ?? record.date }
    private var currentSessionEndDate: Date   { intervalRecord?.workout?.endDate ?? record.endDate }

    // MARK: - Data loading

    private func loadDetails() {
        isLoadingRelay.accept(true)
        let group = DispatchGroup()
        let start = record.date
        let end   = record.endDate
        var result = DetailData()

        group.enter()
        store.fetchHeartRateSamples(from: start, to: end) { s in result.heartRates = s; group.leave() }

        group.enter()
        store.fetchQuantitySamples(identifier: .runningSpeed, unit: .meter().unitDivided(by: .second()), from: start, to: end) { s in result.speedSamples = s; group.leave() }

        group.enter()
        store.fetchQuantitySamples(identifier: .stepCount, unit: .count(), from: start, to: end) { s in result.stepSamples = s; group.leave() }

        group.enter()
        store.fetchQuantitySamples(identifier: .runningStrideLength, unit: .meter(), from: start, to: end) { s in result.strideSamples = s; group.leave() }

        group.enter()
        store.fetchQuantitySamples(identifier: .runningVerticalOscillation, unit: .meterUnit(with: .centi), from: start, to: end) { s in result.voSamples = s; group.leave() }

        group.enter()
        store.fetchQuantitySamples(identifier: .runningPower, unit: .watt(), from: start, to: end) { s in result.powerSamples = s; group.leave() }

        group.enter()
        store.fetchQuantitySamples(identifier: .runningGroundContactTime, unit: .secondUnit(with: .milli), from: start, to: end) { s in result.gctSamples = s; group.leave() }

        group.enter()
        if let workout = record.workout {
            store.fetchAltitudeData(for: workout) { pts in result.altPoints = pts; group.leave() }
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
            if !result.splits.isEmpty {
                self.store.enrichSplits(
                    &result.splits,
                    heartRates:            result.heartRates,
                    steps:                 result.stepSamples,
                    strideLengths:         result.strideSamples,
                    verticalOscillations:  result.voSamples,
                    powers:                result.powerSamples,
                    speeds:                result.speedSamples,
                    groundContactTimes:    result.gctSamples,
                    altitudes:             result.altPoints
                )
            }
            result.lapRows = self.makeLapRows(from: result)
            self.dataRelay.accept(result)
            self.isLoadingRelay.accept(false)
        }
    }

    private func makeLapRows(from data: DetailData) -> [RunDetailLapRow] {
        if let intervalRecord {
            return makeIntervalLapRows(intervalRecord, heartRates: data.heartRates, altitudes: data.altPoints)
        }
        return data.splits.map { split in
            RunDetailLapRow(
                id: split.id,
                label: freeRunLabel(for: split),
                pace: split.pace,
                distance: split.distance,
                startDate: split.startDate,
                endDate: split.endDate,
                avgHeartRate: split.avgHeartRate,
                elevationChange: split.elevationChange
            )
        }
    }

    private func makeIntervalLapRows(
        _ intervalRecord: IntervalRecord,
        heartRates: [HeartRateSample],
        altitudes: [AltitudePoint]
    ) -> [RunDetailLapRow] {
        var cumulativeDistance = 0.0
        var rowID = 1
        return intervalRecord.laps.compactMap { lap in
            guard lap.type == .run else { return nil }
            cumulativeDistance += lap.distance
            let avgHR: Double? = {
                let vals = heartRates.filter { $0.date >= lap.startDate && $0.date < lap.endDate }.map(\.bpm)
                return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
            }()
            let elevChange: Double? = {
                let vals = altitudes.filter { $0.date >= lap.startDate && $0.date <= lap.endDate }
                guard let first = vals.first, let last = vals.last else { return nil }
                return last.altitude - first.altitude
            }()
            let pace = lap.avgPace ?? (lap.distance > 0 ? lap.duration / (lap.distance / 1000.0) : 0)
            let row = RunDetailLapRow(id: rowID, label: String(format: "%.0fm", cumulativeDistance.rounded()), pace: pace, distance: lap.distance, startDate: lap.startDate, endDate: lap.endDate, avgHeartRate: avgHR, elevationChange: elevChange)
            rowID += 1
            return row
        }
    }

    private func freeRunLabel(for split: DistSplit) -> String {
        split.distance < 1000
            ? String(format: "%.1f", Double(split.id - 1) + split.distance / 1000)
            : "\(split.id)"
    }
}

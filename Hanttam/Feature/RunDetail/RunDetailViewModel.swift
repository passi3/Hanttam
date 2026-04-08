//
//  RunDetailViewModel.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import Foundation
import Combine
internal import HealthKit

struct RunDetailLapRow: Identifiable {
    let id: Int
    let label: String
    let pace: TimeInterval
    let distance: Double
    let startDate: Date
    let endDate: Date
    var avgHeartRate: Double?
    var elevationChange: Double?
}

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
        var lapRows: [RunDetailLapRow] = []
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
    let intervalRecord: IntervalRecord?

    private let isLoadingSubject = CurrentValueSubject<Bool, Never>(true)
    private let dataSubject = CurrentValueSubject<DetailData, Never>(DetailData())
    private let linkedShoeSubject = CurrentValueSubject<RegisteredShoe?, Never>(nil)

    var data: AnyPublisher<DetailData, Never> { dataSubject.eraseToAnyPublisher() }
    var linkedShoe: AnyPublisher<RegisteredShoe?, Never> { linkedShoeSubject.eraseToAnyPublisher() }
    private var cancellables = Set<AnyCancellable>()
    private let store = HealthKitStore.shared
    private let gearStore: GearLocalStoring

    init(
        record: RunningRecord,
        intervalRecord: IntervalRecord? = nil,
        gearStore: GearLocalStoring = GearLocalStore.shared
    ) {
        self.record = record
        self.intervalRecord = intervalRecord
        self.gearStore = gearStore
    }

    // MARK: - Transform

    func transform(input: Input) -> Output {
        input.viewDidLoad
            .sink { [weak self] in
                self?.loadDetails()
                self?.refreshLinkedShoe()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: GearLocalStore.didChangeNotification)
            .sink { [weak self] _ in
                self?.refreshLinkedShoe()
            }
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
            result.lapRows = self.makeLapRows(from: result)
            self.dataSubject.send(result)
            self.isLoadingSubject.send(false)
        }
    }

    func fetchRegisteredShoes() -> [RegisteredShoe] {
        gearStore.fetchRegisteredShoes()
    }

    func refreshLinkedShoe() {
        linkedShoeSubject.send(
            gearStore.linkedShoe(
                for: currentSessionIdentifier,
                kind: currentSessionKind
            )
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

    private var currentSessionKind: GearSessionKind {
        intervalRecord == nil ? .freeRun : .interval
    }

    private var currentSessionIdentifier: String {
        if let intervalRecord {
            return intervalRecord.gearSessionIdentifier
        }
        return record.gearSessionIdentifier
    }

    private var currentSessionStartDate: Date {
        intervalRecord?.date ?? record.date
    }

    private var currentSessionEndDate: Date {
        intervalRecord?.workout?.endDate ?? record.endDate
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

            let avgHeartRate: Double? = {
                let values = heartRates
                    .filter { $0.date >= lap.startDate && $0.date < lap.endDate }
                    .map(\.bpm)
                guard !values.isEmpty else { return nil }
                return values.reduce(0, +) / Double(values.count)
            }()

            let elevationChange: Double? = {
                let values = altitudes.filter { $0.date >= lap.startDate && $0.date <= lap.endDate }
                guard let first = values.first, let last = values.last else { return nil }
                return last.altitude - first.altitude
            }()

            let pace = lap.avgPace ?? (lap.distance > 0 ? lap.duration / (lap.distance / 1000.0) : 0)
            let row = RunDetailLapRow(
                id: rowID,
                label: String(format: "%.0fm", cumulativeDistance.rounded()),
                pace: pace,
                distance: lap.distance,
                startDate: lap.startDate,
                endDate: lap.endDate,
                avgHeartRate: avgHeartRate,
                elevationChange: elevationChange
            )
            rowID += 1
            return row
        }
    }

    private func freeRunLabel(for split: DistSplit) -> String {
        if split.distance < 1000 {
            return String(format: "%.1f", Double(split.id - 1) + split.distance / 1000)
        }
        return "\(split.id)"
    }
}

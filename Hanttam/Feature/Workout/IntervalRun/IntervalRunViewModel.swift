//
//  IntervalRunViewModel.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import UIKit
import CoreLocation
import MapKit
import RxSwift
import RxCocoa
internal import HealthKit

final class IntervalRunViewModel: NSObject {

    // MARK: - Phase
    enum Phase {
        case preparing
        case runningLap
        case resting
        indirect case paused(prior: Phase)
        case finished
    }

    // MARK: - Input
    struct Input {
        let pauseTapped    : Observable<Void>
        let resumeTapped   : Observable<Void>
        let stopTapped     : Observable<Void>
        let manualLapTapped: Observable<Void>
    }

    // MARK: - Output
    struct Output {
        let phase           : Driver<Phase>
        let countdownText   : Driver<String>
        let durationText    : Driver<String>
        let lapDistanceText : Driver<String>
        let avgPaceText     : Driver<String>
        let lapPaceText     : Driver<String>
        let avgHRText       : Driver<String>
        let lapHRText       : Driver<String>
        let setCountText    : Driver<String>
        let restCountdown   : Driver<String>
        let routeUpdate     : Driver<WorkoutRouteUpdate>
        let sourceBadgeState: Driver<SourceBadgeState>
        let showResult      : Driver<WorkoutResultDataModel>
        let showAlert       : Driver<AlertInfo>
        let hapticFeedback  : Driver<UINotificationFeedbackGenerator.FeedbackType>
    }

    // MARK: - Supporting Types
    enum SourceBadgeState {
        case hidden
        case connected
        case disconnected
    }

    struct AlertInfo {
        let title    : String
        let message  : String
        let onConfirm: (() -> Void)?
    }

    // MARK: - Init Params
    private let totalSets   : Int
    private let lapDistance : Double
    private let restDuration: TimeInterval
    private let isIndoor    : Bool
    private var isWatchPrimary: Bool

    // MARK: - State
    private var phase           : Phase           = .preparing
    private var currentSet      : Int             = 1
    private var elapsed         : TimeInterval    = 0
    private var lapElapsed      : TimeInterval    = 0
    private var lapDistance_    : Double          = 0
    private var restRemaining   : TimeInterval    = 0
    private var timer           : Timer?
    private var snapshotObserver    : NSObjectProtocol?
    private var phoneMetricsObserver: NSObjectProtocol?
    private var lastSnapshotDate    : Date?
    private var disconnectTimer     : Timer?
    private var watchCountdownTimer : Timer?
    private var watchCountdownEndsAt: Date?
    private var hasShownResult      = false
    private var isFirstMapUpdate    = true
    private var workoutStartDate    : Date?
    private var watchAvgPace        : TimeInterval?
    private var watchLapPace        : TimeInterval?
    private var watchAvgHeartRate   : Double?
    private var watchLapAvgHeartRate: Double?
    private var lastRunLapPace      : TimeInterval?
    private var lastRunLapAvgHeartRate: Double?

    // Location
    private let locationManager = CLLocationManager()
    private var allLocations    : [CLLocation]               = []
    private var lapLocations    : [CLLocation]               = []
    private var routeCoordinates: [CLLocationCoordinate2D]   = []

    // Recording
    private var laps        : [IntervalLap] = []
    private var lapStartDate: Date          = Date()

    // MARK: - Relays
    private let phaseRelay           = BehaviorRelay<Phase>(value: .preparing)
    private let countdownRelay       = BehaviorRelay<String>(value: "1")
    private let durationRelay        = BehaviorRelay<String>(value: "00:00")
    private let lapDistanceRelay     = BehaviorRelay<String>(value: "0m / 0m")
    private let avgPaceRelay         = BehaviorRelay<String>(value: "--'--\"")
    private let lapPaceRelay         = BehaviorRelay<String>(value: "--'--\"")
    private let avgHRRelay           = BehaviorRelay<String>(value: "--")
    private let lapHRRelay           = BehaviorRelay<String>(value: "--")
    private let setCountRelay        = BehaviorRelay<String>(value: "1 / 1")
    private let restCountdownRelay   = BehaviorRelay<String>(value: "0")
    private let routeUpdateRelay     = PublishRelay<WorkoutRouteUpdate>()
    private let sourceBadgeRelay     = BehaviorRelay<SourceBadgeState>(value: .hidden)
    private let showResultRelay      = PublishRelay<WorkoutResultDataModel>()
    private let showAlertRelay       = PublishRelay<AlertInfo>()
    private let hapticRelay          = PublishRelay<UINotificationFeedbackGenerator.FeedbackType>()

    private let disposeBag = DisposeBag()

    // MARK: - Init
    init(sets: Int, lapDistance: Double, restDuration: TimeInterval, isIndoor: Bool = false, isWatchPrimary: Bool = false) {
        self.totalSets    = sets
        self.lapDistance  = lapDistance
        self.restDuration = restDuration
        self.isIndoor     = isIndoor
        self.isWatchPrimary = isWatchPrimary
        super.init()
        lapDistanceRelay.accept("0m / \(Int(lapDistance))m")
        setCountRelay.accept("1 / \(sets)")
    }

    // MARK: - Transform
    func transform(input: Input) -> Output {
        bindButtons(input: input)
        return Output(
            phase           : phaseRelay.asDriver(),
            countdownText   : countdownRelay.asDriver(),
            durationText    : durationRelay.asDriver(),
            lapDistanceText : lapDistanceRelay.asDriver(),
            avgPaceText     : avgPaceRelay.asDriver(),
            lapPaceText     : lapPaceRelay.asDriver(),
            avgHRText       : avgHRRelay.asDriver(),
            lapHRText       : lapHRRelay.asDriver(),
            setCountText    : setCountRelay.asDriver(),
            restCountdown   : restCountdownRelay.asDriver(),
            routeUpdate     : routeUpdateRelay.asDriver(onErrorDriveWith: .empty()),
            sourceBadgeState: sourceBadgeRelay.asDriver(),
            showResult      : showResultRelay.asDriver(onErrorDriveWith: .empty()),
            showAlert       : showAlertRelay.asDriver(onErrorDriveWith: .empty()),
            hapticFeedback  : hapticRelay.asDriver(onErrorDriveWith: .empty())
        )
    }

    // MARK: - Lifecycle Hooks
    func viewDidLoad() {
        if !isWatchPrimary {
            setupLocationManager()
        }
        setupPhoneMetricsObserver()
        if isWatchPrimary {
            enterWatchPreparingState()
            setupSnapshotObserver()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(fallbackToPhone),
                name: WatchBridge.watchFailedFallbackNotification,
                object: nil
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stopFromMirror),
            name: WatchBridge.workoutStoppedNotification,
            object: nil
        )
        if !isWatchPrimary {
            beginCountdown()
        }
    }

    func viewWillDisappear() {
        if case .finished = phase { return }
        finishWorkout(showResult: false)
    }

    deinit {
        if let snapshotObserver {
            NotificationCenter.default.removeObserver(snapshotObserver)
        }
        if let phoneMetricsObserver {
            NotificationCenter.default.removeObserver(phoneMetricsObserver)
        }
        watchCountdownTimer?.invalidate()
        timer?.invalidate()
    }

    // MARK: - Button Binding
    private func bindButtons(input: Input) {
        input.pauseTapped
            .subscribe(onNext: { [weak self] in self?.handlePause() })
            .disposed(by: disposeBag)

        input.resumeTapped
            .subscribe(onNext: { [weak self] in self?.handleResume() })
            .disposed(by: disposeBag)

        input.stopTapped
            .subscribe(onNext: { [weak self] in self?.handleStop() })
            .disposed(by: disposeBag)

        input.manualLapTapped
            .subscribe(onNext: { [weak self] in self?.handleManualLap() })
            .disposed(by: disposeBag)
    }

    // MARK: - Button Handlers
    private func handlePause() {
        if isWatchPrimary {
            guard WatchBridge.shared.sendWorkoutCommand(WorkoutStreamKey.commandPause) else {
                showAlertRelay.accept(AlertInfo(title: "워치 연결 필요", message: "워치 연결을 확인해주세요.", onConfirm: nil))
                return
            }
            return
        }
        switch phase {
        case .runningLap:
            phase = .paused(prior: .runningLap)
            phaseRelay.accept(phase)
            timer?.invalidate()
            locationManager.stopUpdatingLocation()
            HealthKitStore.shared.pausePhoneWorkout()
        case .resting:
            phase = .paused(prior: .resting)
            phaseRelay.accept(phase)
            timer?.invalidate()
            locationManager.stopUpdatingLocation()
        default:
            break
        }
    }

    private func handleResume() {
        if isWatchPrimary {
            guard WatchBridge.shared.sendWorkoutCommand(WorkoutStreamKey.commandResume) else {
                showAlertRelay.accept(AlertInfo(title: "워치 연결 필요", message: "워치 연결을 확인해주세요.", onConfirm: nil))
                return
            }
            return
        }
        guard case .paused(let prior) = phase else { return }
        switch prior {
        case .runningLap:
            phase = .runningLap
            phaseRelay.accept(phase)
            locationManager.startUpdatingLocation()
            HealthKitStore.shared.resumePhoneWorkout()
            startTimer()
        case .resting:
            phase = .resting
            phaseRelay.accept(phase)
            HealthKitStore.shared.resumePhoneWorkout()
            startTimer()
        default:
            break
        }
    }

    private func handleStop() {
        if isWatchPrimary {
            guard WatchBridge.shared.sendWorkoutCommand(WorkoutStreamKey.commandStop) else {
                showAlertRelay.accept(AlertInfo(title: "워치 연결 필요", message: "워치 연결을 확인해주세요.", onConfirm: nil))
                return
            }
            return
        }
        switch phase {
        case .runningLap:
            recordLap(type: .run)
        case .resting:
            recordLap(type: .rest)
        default:
            break
        }
        if case .paused(let prior) = phase {
            switch prior {
            case .runningLap: recordLap(type: .run)
            case .resting   : recordLap(type: .rest)
            default: break
            }
        }
        finishAndEmitResult()
    }

    private func handleManualLap() {
        guard case .runningLap = phase else { return }
        startResting()
    }

    // MARK: - Countdown
    private func beginCountdown() {
        phase = .preparing
        phaseRelay.accept(.preparing)
        var countdown = 1
        countdownRelay.accept("\(countdown)")

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            countdown -= 1
            if countdown > 0 {
                self.countdownRelay.accept("\(countdown)")
            } else {
                t.invalidate()
                self.countdownFinished()
            }
        }
    }

    private func countdownFinished() {
        if isWatchPrimary {
            startWorkoutFlow(startDate: Date())
            return
        }
        let startDate = Date()
        let settings = IntervalSettings(sets: totalSets, lapDistance: lapDistance, restDuration: restDuration)
        HealthKitStore.shared.startPhoneWorkout(
            kind: .intervalRun(settings: settings),
            isIndoor: isIndoor,
            start: startDate
        ) { [weak self] ok, error in
            guard let self else { return }
            guard ok else {
                self.showAlertRelay.accept(AlertInfo(
                    title: "운동 시작 실패",
                    message: error?.localizedDescription ?? "건강 권한 또는 세션 상태를 확인해주세요.",
                    onConfirm: { /* ViewController dismisses */ }
                ))
                return
            }
            self.startWorkoutFlow(startDate: startDate)
        }
    }

    private func startWorkoutFlow(startDate: Date) {
        workoutStartDate = startDate
        startRunningLap()
    }

    private func enterWatchPreparingState(countdownValue: Int? = nil, startsLocalTimer: Bool = true) {
        phase = .preparing
        phaseRelay.accept(.preparing)
        var countdown = countdownValue ?? 3
        countdownRelay.accept("\(max(countdown, 0))")

        guard startsLocalTimer, watchCountdownTimer == nil else { return }
        watchCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            countdown -= 1
            if countdown > 0 {
                self.countdownRelay.accept("\(countdown)")
            } else {
                t.invalidate()
                self.watchCountdownTimer = nil
                self.countdownFinished()
            }
        }
    }

    private func updateWatchPreparingCountdown(endsAt: Date?, countdownValue: Int?) {
        watchCountdownEndsAt = endsAt
        watchCountdownTimer?.invalidate()
        watchCountdownTimer = nil
        enterWatchPreparingState(countdownValue: countdownValue, startsLocalTimer: endsAt == nil)

        guard let endsAt else { return }
        watchCountdownTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let remaining = max(0, Int(ceil(endsAt.timeIntervalSinceNow)))
            self.countdownRelay.accept("\(remaining)")
            if remaining <= 0 {
                timer.invalidate()
                self.watchCountdownTimer = nil
                self.countdownFinished()
            }
        }
    }

    private func exitPreparingStateIfNeeded() {
        watchCountdownTimer?.invalidate()
        watchCountdownTimer = nil
        // Phase change signal drives ViewController to hide countdown
    }

    // MARK: - Phase Transitions
    private func startRunningLap() {
        phase        = .runningLap
        lapElapsed   = 0
        lapDistance_ = 0
        lapLocations = []
        lapStartDate = Date()

        if !isWatchPrimary {
            locationManager.startUpdatingLocation()
            startTimer()
        }
        phaseRelay.accept(.runningLap)
        hapticRelay.accept(.success)
        updateMetrics()
    }

    private func startResting() {
        recordLap(type: .run)

        phase         = .resting
        restRemaining = restDuration
        lapStartDate  = Date()

        locationManager.stopUpdatingLocation()
        restCountdownRelay.accept("\(Int(restRemaining))")
        phaseRelay.accept(.resting)
        hapticRelay.accept(.success)
        updateMetrics()
    }

    private func restFinished() {
        recordLap(type: .rest)
        currentSet += 1

        if currentSet > totalSets {
            finishAndEmitResult()
        } else {
            startRunningLap()
        }
    }

    // MARK: - Timer
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            switch self.phase {
            case .runningLap:
                self.elapsed    += 1
                self.lapElapsed += 1
                self.updateMetrics()

            case .resting:
                self.elapsed      += 1
                self.restRemaining -= 1
                if self.restRemaining <= 3 && self.restRemaining > 0 {
                    self.hapticRelay.accept(.warning)
                }
                if self.restRemaining <= 0 {
                    self.restFinished()
                } else {
                    self.restCountdownRelay.accept("\(Int(self.restRemaining))")
                }
                self.updateMetrics()

            default:
                break
            }
        }
    }

    // MARK: - Recording
    private func recordLap(type: IntervalLap.LapType) {
        let now       = Date()
        let lapNumber = laps.count + 1
        let dist      = type == .run ? lapDistance_ : 0
        let dur       = type == .run ? lapElapsed : (restDuration - restRemaining)
        let pace: TimeInterval? = (type == .run && dist > 10) ? (dur / (dist / 1000.0)) : nil

        let lap = IntervalLap(
            id: lapNumber,
            type: type,
            duration: dur,
            distance: dist,
            startDate: lapStartDate,
            endDate: now,
            avgPace: pace
        )
        laps.append(lap)
        if type == .run {
            lastRunLapPace = pace
            lastRunLapAvgHeartRate = calculateCurrentLapAverageHeartRate(from: HealthKitStore.shared.currentPhoneWorkoutMetrics)
        }
    }

    // MARK: - Finish
    private func finishWorkout(showResult: Bool, completion: ((HKWorkout?) -> Void)? = nil) {
        if case .finished = phase {
            completion?(nil)
            return
        }
        phase = .finished
        phaseRelay.accept(.finished)
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()

        guard !isWatchPrimary else {
            if showResult { emitResult(workout: nil) }
            completion?(nil)
            return
        }

        let totalDist = laps.filter { $0.type == .run }.reduce(0) { $0 + $1.distance }
        let endDate   = Date()
        let duration  = endDate.timeIntervalSince(workoutStartDate ?? endDate)

        guard HealthKitStore.shared.shouldSaveWorkout(duration: duration, distance: totalDist) else {
            HealthKitStore.shared.discardActivePhoneWorkout { [weak self] _, _ in
                guard let self else { return }
                completion?(nil)
                if showResult { self.emitResult(workout: nil) }
            }
            return
        }

        HealthKitStore.shared.finishPhoneWorkout(
            end: endDate,
            distance: totalDist,
            calories: nil,
            routeLocations: allLocations,
            laps: laps
        ) { [weak self] success, workout, error in
            guard let self else { return }
            let finish = {
                completion?(workout)
                if showResult { self.emitResult(workout: workout) }
            }
            if success {
                if let error {
                    self.showAlertRelay.accept(AlertInfo(
                        title: "운동 저장 완료",
                        message: "운동은 저장됐지만 경로 저장 중 일부 문제가 발생했습니다.\n\(error.localizedDescription)",
                        onConfirm: finish
                    ))
                } else {
                    finish()
                }
            } else {
                self.showAlertRelay.accept(AlertInfo(
                    title: "운동 저장 실패",
                    message: error?.localizedDescription ?? "운동을 저장하지 못했습니다.",
                    onConfirm: finish
                ))
            }
        }
    }

    private func finishAndEmitResult() {
        guard !hasShownResult else { return }
        finishWorkout(showResult: true)
    }

    private func emitResult(workout: HKWorkout?) {
        guard !hasShownResult else { return }
        hasShownResult = true
        let runLaps   = laps.filter { $0.type == .run }
        let totalDist = runLaps.reduce(0) { $0 + $1.distance }
        let avgPace: TimeInterval? = totalDist > 10 ? elapsed / (totalDist / 1000) : nil

        let splits: [WorkoutResultDataModel.SplitData] = runLaps.enumerated().map { i, lap in
            let pace = lap.avgPace ?? (lap.duration / max(0.001, lap.distance / 1000))
            return WorkoutResultDataModel.SplitData(km: i + 1, pace: pace, distance: lap.distance)
        }

        let coords    = routeCoordinates.map { (lat: $0.latitude, lng: $0.longitude) }
        let endDate   = Date()
        let startDate = workoutStartDate ?? endDate.addingTimeInterval(-elapsed)

        let resultData = WorkoutResultDataModel(
            startDate: startDate,
            endDate: endDate,
            totalDistance: totalDist,
            totalDuration: elapsed,
            avgPace: avgPace,
            calories: nil,
            splits: splits,
            routeCoordinates: coords,
            routeLocations: allLocations,
            workout: workout,
            isIndoor: isIndoor,
            alreadySaved: HealthKitStore.shouldSaveWorkout(duration: elapsed, distance: totalDist) && (isWatchPrimary || workout != nil)
        )
        showResultRelay.accept(resultData)
    }

    // MARK: - Metrics
    private func updateMetrics() {
        let h = Int(elapsed) / 3600
        let m = Int(elapsed) % 3600 / 60
        let s = Int(elapsed) % 60
        durationRelay.accept(h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s))

        if case .resting = phase {
            lapDistanceRelay.accept("REST \(Int(restRemaining))s")
        } else {
            lapDistanceRelay.accept("\(Int(lapDistance_))m / \(Int(lapDistance))m")
        }

        setCountRelay.accept("\(currentSet) / \(totalSets)")

        if isWatchPrimary {
            avgPaceRelay.accept(formatPace(watchAvgPace))
            lapPaceRelay.accept(formatPace(watchLapPace))
            avgHRRelay.accept(formatHeartRate(watchAvgHeartRate))
            lapHRRelay.accept(formatHeartRate(watchLapAvgHeartRate))
            return
        }

        let runDist = laps.filter { $0.type == .run }.reduce(0) { $0 + $1.distance } + lapDistance_
        let runTime = laps.filter { $0.type == .run }.reduce(0) { $0 + $1.duration } + lapElapsed
        avgPaceRelay.accept(runDist > 10 ? formatPace(runTime / (runDist / 1000.0)) : "--'--\"")

        let metrics = HealthKitStore.shared.currentPhoneWorkoutMetrics
        avgHRRelay.accept(formatHeartRate(metrics.avgHeartRate))
        lapHRRelay.accept(formatHeartRate(currentLapAverageHeartRate(from: metrics)))

        if case .resting = phase {
            lapPaceRelay.accept(formatPace(lastRunLapPace))
        } else {
            lapPaceRelay.accept(formatPace(calculateCurrentLapPace()))
        }
    }

    private func calculateCurrentLapPace() -> TimeInterval? {
        guard lapDistance_ > 10, lapElapsed > 0 else { return nil }
        return lapElapsed / (lapDistance_ / 1000.0)
    }

    private func currentLapAverageHeartRate(from metrics: HealthKitStore.PhoneWorkoutMetrics) -> Double? {
        if case .resting = phase { return lastRunLapAvgHeartRate }
        return calculateCurrentLapAverageHeartRate(from: metrics)
    }

    private func calculateCurrentLapAverageHeartRate(from metrics: HealthKitStore.PhoneWorkoutMetrics) -> Double? {
        let samples = metrics.heartRateSamples.filter { $0.date >= lapStartDate }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0) { $0 + $1.bpm } / Double(samples.count)
    }

    private func formatPace(_ secPerKm: TimeInterval?) -> String {
        guard let secPerKm, secPerKm.isFinite, secPerKm > 0, secPerKm < 3600 else { return "--'--\"" }
        return String(format: "%d'%02d\"", Int(secPerKm) / 60, Int(secPerKm) % 60)
    }

    private func formatHeartRate(_ bpm: Double?) -> String {
        guard let bpm, bpm.isFinite, bpm > 0 else { return "--" }
        return String(format: "%.0f", bpm)
    }

    // MARK: - Setup
    private func setupLocationManager() {
        locationManager.delegate        = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter  = 5
    }

    private func setupPhoneMetricsObserver() {
        phoneMetricsObserver = NotificationCenter.default.addObserver(
            forName: HealthKitStore.phoneWorkoutMetricsDidUpdate,
            object: HealthKitStore.shared,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isWatchPrimary else { return }
            self.updateMetrics()
        }
    }

    // MARK: - Watch Observer
    private func setupSnapshotObserver() {
        snapshotObserver = NotificationCenter.default.addObserver(
            forName: WatchBridge.workoutSnapshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let snapshot = note.userInfo?["snapshot"] as? WorkoutDataSnapshot else { return }
            self.lastSnapshotDate = Date()
            self.applySnapshot(snapshot)
        }

        disconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, self.isWatchPrimary else { return }
            if case .finished = self.phase { return }
            if let last = self.lastSnapshotDate, Date().timeIntervalSince(last) > 10 {
                self.sourceBadgeRelay.accept(.disconnected)
            } else {
                self.sourceBadgeRelay.accept(.connected)
            }
        }
    }

    private func applySnapshot(_ snapshot: WorkoutDataSnapshot) {
        if case .finished = phase { return }
        elapsed = snapshot.elapsed

        switch snapshot.phase {
        case "preparing":
            let endsAt = snapshot.countdownEndsAt.map(Date.init(timeIntervalSince1970:))
            updateWatchPreparingCountdown(endsAt: endsAt, countdownValue: snapshot.countdownValue)
            return
        case "paused":
            exitPreparingStateIfNeeded()
            if case .paused = phase {} else {
                phase = .paused(prior: .runningLap)
                phaseRelay.accept(phase)
            }
        case "running":
            exitPreparingStateIfNeeded()
            if snapshot.intervalPhase == "resting" {
                if case .resting = phase {} else {
                    phase = .resting
                    phaseRelay.accept(.resting)
                }
            } else {
                if case .runningLap = phase {} else {
                    phase = .runningLap
                    phaseRelay.accept(.runningLap)
                }
            }
        case "finished":
            exitPreparingStateIfNeeded()
            if case .finished = phase {} else {
                finishWorkout(showResult: false)
                finishAndEmitResult()
                return
            }
        default:
            break
        }

        // Duration
        let h = Int(elapsed) / 3600
        let m = Int(elapsed) % 3600 / 60
        let s = Int(elapsed) % 60
        durationRelay.accept(h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s))

        // Set
        if let cs = snapshot.currentSet, let ts = snapshot.totalSets {
            currentSet = cs
            setCountRelay.accept("\(cs) / \(ts)")
        }

        // Lap distance / rest
        if snapshot.intervalPhase == "resting", let rest = snapshot.restRemaining {
            restRemaining = rest
            lapDistanceRelay.accept("REST \(Int(rest))s")
            restCountdownRelay.accept("\(Int(rest))")
        } else if let ld = snapshot.lapDistanceCurrent {
            lapDistance_ = ld
            lapDistanceRelay.accept("\(Int(ld))m / \(Int(lapDistance))m")
        }

        // Pace & HR
        watchAvgPace         = snapshot.avgPace
        watchLapPace         = snapshot.segmentPace ?? snapshot.currentPace
        watchAvgHeartRate    = snapshot.avgHeartRate
        watchLapAvgHeartRate = snapshot.segmentAvgHeartRate ?? snapshot.heartRate
        avgPaceRelay.accept(formatPace(watchAvgPace))
        lapPaceRelay.accept(formatPace(watchLapPace))
        avgHRRelay.accept(formatHeartRate(watchAvgHeartRate))
        lapHRRelay.accept(formatHeartRate(watchLapAvgHeartRate))

        // Map
        if let lat = snapshot.currentLatitude, let lng = snapshot.currentLongitude {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            if routeCoordinates.last.map({ $0.latitude == coord.latitude && $0.longitude == coord.longitude }) != true {
                routeCoordinates.append(coord)
            }
            emitRouteUpdate(coordinate: coord)
        }
    }

    private func emitRouteUpdate(coordinate: CLLocationCoordinate2D) {
        routeUpdateRelay.accept(WorkoutRouteUpdate(
            coordinate: coordinate,
            allCoordinates: routeCoordinates,
            isFirstUpdate: isFirstMapUpdate
        ))
        isFirstMapUpdate = false
    }

    // MARK: - Notification Selectors
    @objc private func stopFromMirror() {
        finishAndEmitResult()
    }

    @objc private func fallbackToPhone() {
        guard isWatchPrimary else { return }
        isWatchPrimary = false
        if let obs = snapshotObserver {
            NotificationCenter.default.removeObserver(obs)
            snapshotObserver = nil
        }
        disconnectTimer?.invalidate()
        disconnectTimer = nil
        sourceBadgeRelay.accept(.hidden)

        setupLocationManager()
        locationManager.requestWhenInUseAuthorization()

        if case .preparing = phase {
            watchCountdownTimer?.invalidate()
            watchCountdownTimer = nil
            beginCountdown()
            return
        }

        guard case .runningLap = phase else { return }
        let settings  = IntervalSettings(sets: totalSets, lapDistance: lapDistance, restDuration: restDuration)
        let startDate = workoutStartDate ?? Date()
        HealthKitStore.shared.startPhoneWorkout(
            kind: .intervalRun(settings: settings),
            isIndoor: isIndoor,
            start: startDate
        ) { [weak self] ok, _ in
            guard let self, ok else { return }
            DispatchQueue.main.async {
                self.locationManager.startUpdatingLocation()
                self.startTimer()
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension IntervalRunViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        allLocations.append(loc)
        routeCoordinates.append(loc.coordinate)

        if let prev = lapLocations.last {
            lapDistance_ += loc.distance(from: prev)
        }
        lapLocations.append(loc)

        emitRouteUpdate(coordinate: loc.coordinate)
        updateMetrics()

        if case .runningLap = phase, lapDistance_ >= lapDistance {
            if currentSet >= totalSets {
                recordLap(type: .run)
                finishAndEmitResult()
            } else {
                startResting()
            }
        }
    }
}

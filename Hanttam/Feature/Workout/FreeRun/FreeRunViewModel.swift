//
//  FreeRunViewModel.swift
//  Hanttam
//
//  Created by passi on 3/31/26.
//

import UIKit
import CoreLocation
import MapKit
import RxSwift
import RxCocoa
internal import HealthKit

final class FreeRunViewModel: NSObject {

    // MARK: - Input
    struct Input {
        let pauseTapped : Observable<Void>
        let resumeTapped: Observable<Void>
        let stopTapped  : Observable<Void>
    }

    // MARK: - Output
    struct Output {
        let phase           : Driver<WorkoutPhase>
        let durationText    : Driver<String>
        let distanceText    : Driver<String>
        let avgPaceText     : Driver<String>
        let segmentPaceText : Driver<String>
        let avgHRText       : Driver<String>
        let segmentHRText   : Driver<String>
        let routeUpdate     : Driver<WorkoutRouteUpdate>
        let sourceBadgeState: Driver<SourceBadgeState>
        let countdownText   : Driver<String>
        let showResult      : Driver<WorkoutResultDataModel>
        let showAlert       : Driver<AlertInfo>
    }

    // MARK: - Supporting types
    enum SourceBadgeState {
        case hidden
        case connected
        case disconnected
    }

    struct AlertInfo {
        let title  : String
        let message: String
        let onConfirm: (() -> Void)?
    }

    // MARK: - Private state
    private let isIndoor: Bool
    private var isWatchPrimary: Bool

    private let locationManager = CLLocationManager()
    private var allLocations    : [CLLocation] = []
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var routeHeartRates : [Double?] = []

    private var elapsed              : TimeInterval = 0
    private var timer                : Timer?
    private var phase                : WorkoutPhase = .preparing
    private var snapshotObserver     : NSObjectProtocol?
    private var phoneMetricsObserver : NSObjectProtocol?
    private var lastSnapshotDate     : Date?
    private var disconnectTimer      : Timer?
    private var watchCountdownTimer  : Timer?
    private var watchCountdownEndsAt : Date?
    private var watchTotalDistance   : Double = 0
    private var watchAvgPace         : TimeInterval?
    private var watchSegmentPace     : TimeInterval?
    private var watchAvgHeartRate    : Double?
    private var watchSegmentAvgHR    : Double?
    private var hasShownResult       = false
    private var isFirstMapUpdate     = true
    private var workoutStartDate     : Date?
    private var isStoppingFromMirror = false
    private var nextSegmentBoundary  : Double = 1000
    private var segmentStartDistance : Double = 0
    private var segmentStartElapsed  : TimeInterval = 0
    private var segmentStartDate     : Date?

    // MARK: - Relays
    private let phaseRelay           = BehaviorRelay<WorkoutPhase>(value: .preparing)
    private let durationRelay        = BehaviorRelay<String>(value: "00:00")
    private let distanceRelay        = BehaviorRelay<String>(value: "0.00KM")
    private let avgPaceRelay         = BehaviorRelay<String>(value: "--'--\"")
    private let segmentPaceRelay     = BehaviorRelay<String>(value: "--'--\"")
    private let avgHRRelay           = BehaviorRelay<String>(value: "--")
    private let segmentHRRelay       = BehaviorRelay<String>(value: "--")
    private let routeUpdateRelay     = PublishRelay<WorkoutRouteUpdate>()
    private let sourceBadgeRelay     = BehaviorRelay<SourceBadgeState>(value: .hidden)
    private let countdownRelay       = BehaviorRelay<String>(value: "1")
    private let showResultRelay      = PublishRelay<WorkoutResultDataModel>()
    private let showAlertRelay       = PublishRelay<AlertInfo>()

    private let disposeBag = DisposeBag()

    // MARK: - Init
    init(isIndoor: Bool = false, isWatchPrimary: Bool = false) {
        self.isIndoor = isIndoor
        self.isWatchPrimary = isWatchPrimary
        super.init()
    }

    // MARK: - Transform
    func transform(input: Input) -> Output {
        bindButtons(input: input)
        return Output(
            phase          : phaseRelay.asDriver(),
            durationText   : durationRelay.asDriver(),
            distanceText   : distanceRelay.asDriver(),
            avgPaceText    : avgPaceRelay.asDriver(),
            segmentPaceText: segmentPaceRelay.asDriver(),
            avgHRText      : avgHRRelay.asDriver(),
            segmentHRText  : segmentHRRelay.asDriver(),
            routeUpdate    : routeUpdateRelay.asDriver(onErrorDriveWith: .empty()),
            sourceBadgeState: sourceBadgeRelay.asDriver(),
            countdownText  : countdownRelay.asDriver(),
            showResult     : showResultRelay.asDriver(onErrorDriveWith: .empty()),
            showAlert      : showAlertRelay.asDriver(onErrorDriveWith: .empty())
        )
    }

    // MARK: - Lifecycle hooks (called by ViewController)
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
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(stopFromMirror),
                name: WatchBridge.workoutStoppedNotification,
                object: nil
            )
        } else {
            beginCountdown()
        }
    }

    func viewWillDisappear() {
        guard phase != .finished else { return }
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

    // MARK: - Button binding
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
    }

    // MARK: - Button handlers
    private func handlePause() {
        if isWatchPrimary {
            guard WatchBridge.shared.sendWorkoutCommand(WorkoutStreamKey.commandPause) else {
                showAlertRelay.accept(AlertInfo(title: "워치 연결 필요", message: "워치 연결을 확인해주세요.", onConfirm: nil))
                return
            }
            phase = .paused
            phaseRelay.accept(.paused)
            return
        }
        phase = .paused
        phaseRelay.accept(.paused)
        locationManager.stopUpdatingLocation()
        HealthKitStore.shared.pausePhoneWorkout()
        AnalyticsEventLogger.logWorkoutPause(
            kind: "freeRun",
            source: .phone,
            elapsed: elapsed,
            totalDistance: calculateTotalDistance()
        )
    }

    private func handleResume() {
        if isWatchPrimary {
            guard WatchBridge.shared.sendWorkoutCommand(WorkoutStreamKey.commandResume) else {
                showAlertRelay.accept(AlertInfo(title: "워치 연결 필요", message: "워치 연결을 확인해주세요.", onConfirm: nil))
                return
            }
            phase = .running
            phaseRelay.accept(.running)
            return
        }
        phase = .running
        phaseRelay.accept(.running)
        locationManager.startUpdatingLocation()
        HealthKitStore.shared.resumePhoneWorkout()
    }

    private func handleStop() {
        if isWatchPrimary {
            guard !isStoppingFromMirror else { return }
            guard WatchBridge.shared.sendWorkoutCommand(WorkoutStreamKey.commandStop) else {
                showAlertRelay.accept(AlertInfo(title: "워치 연결 필요", message: "워치 연결을 확인해주세요.", onConfirm: nil))
                return
            }
            isStoppingFromMirror = true
            return
        }
        finishWorkout(showResult: true)
    }

    // MARK: - Phase Management
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
            startRunning(startDate: Date())
            return
        }
        let startDate = Date()
        HealthKitStore.shared.startPhoneWorkout(kind: .freeRun, isIndoor: isIndoor, start: startDate) { [weak self] ok, error in
            guard let self else { return }
            guard ok else {
                self.showAlertRelay.accept(AlertInfo(
                    title: "운동 시작 실패",
                    message: error?.localizedDescription ?? "건강 권한 또는 세션 상태를 확인해주세요.",
                    onConfirm: { /* ViewController dismisses */ }
                ))
                return
            }
            self.startRunning(startDate: startDate)
        }
    }

    private func startRunning(startDate: Date) {
        phase = .running
        phaseRelay.accept(.running)
        workoutStartDate = startDate
        resetSegmentState(startDate: startDate)
        if !isWatchPrimary {
            AnalyticsEventLogger.logWorkoutStart(
                kind: "freeRun",
                source: .phone,
                isIndoor: isIndoor
            )
        }
        if !isWatchPrimary {
            locationManager.startUpdatingLocation()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.phase == .running else { return }
            self.elapsed += 1
            self.updateMetrics()
        }
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
        // Signal VC to hide countdown container (phase change handles this)
    }

    // MARK: - Finish
    private func finishWorkout(showResult: Bool) {
        guard phase != .finished else {
            if showResult { emitResult(workout: nil) }
            return
        }
        phase = .finished
        phaseRelay.accept(.finished)
        isStoppingFromMirror = false
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil

        guard !isWatchPrimary else {
            if showResult { emitResult(workout: nil) }
            return
        }

        let totalDistance = calculateTotalDistance()
        let endDate = Date()
        let duration = endDate.timeIntervalSince(workoutStartDate ?? endDate)

        let shouldSave = HealthKitStore.shared.shouldSaveWorkout(duration: duration, distance: totalDistance)
        guard shouldSave else {
            logWorkoutEndIfNeeded(
                showResult: showResult,
                totalDistance: totalDistance,
                duration: duration,
                shouldSave: false,
                saveSucceeded: false
            )
            HealthKitStore.shared.discardActivePhoneWorkout { [weak self] _, _ in
                guard let self, showResult else { return }
                self.emitResult(workout: nil)
            }
            return
        }

        HealthKitStore.shared.finishPhoneWorkout(
            end: endDate,
            distance: totalDistance,
            calories: nil,
            routeLocations: allLocations
        ) { [weak self] success, workout, error in
            guard let self else { return }
            self.logWorkoutEndIfNeeded(
                showResult: showResult,
                totalDistance: totalDistance,
                duration: duration,
                shouldSave: true,
                saveSucceeded: success,
                error: error
            )
            if success {
                if let error {
                    self.showAlertRelay.accept(AlertInfo(
                        title: "운동 저장 완료",
                        message: "운동은 저장됐지만 경로 저장 중 일부 문제가 발생했습니다.\n\(error.localizedDescription)",
                        onConfirm: showResult ? { self.emitResult(workout: workout) } : nil
                    ))
                } else if showResult {
                    self.emitResult(workout: workout)
                }
            } else {
                self.showAlertRelay.accept(AlertInfo(
                    title: "운동 저장 실패",
                    message: error?.localizedDescription ?? "운동을 저장하지 못했습니다.",
                    onConfirm: showResult ? { self.emitResult(workout: nil) } : nil
                ))
            }
        }
    }

    private func logWorkoutEndIfNeeded(
        showResult: Bool,
        totalDistance: Double,
        duration: TimeInterval,
        shouldSave: Bool,
        saveSucceeded: Bool,
        error: Error? = nil
    ) {
        guard showResult else { return }
        AnalyticsEventLogger.logWorkoutEnd(
            kind: "freeRun",
            source: .phone,
            elapsed: duration,
            totalDistance: totalDistance,
            shouldSave: shouldSave,
            saveSucceeded: saveSucceeded,
            error: error
        )
    }

    private func emitResult(workout: HKWorkout?) {
        guard !hasShownResult else { return }
        hasShownResult = true
        let totalDist = isWatchPrimary ? watchTotalDistance : calculateTotalDistance()
        let avgPace: TimeInterval? = totalDist > 10 ? elapsed / (totalDist / 1000) : nil
        let splits = buildSplits()
        let coords = routeCoordinates.map { (lat: $0.latitude, lng: $0.longitude) }
        let endDate = Date()
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

        let totalDist = isWatchPrimary ? watchTotalDistance : calculateTotalDistance()
        distanceRelay.accept(String(format: "%.2fKM", totalDist / 1000.0))

        if isWatchPrimary {
            avgPaceRelay.accept(formatPace(watchAvgPace))
            segmentPaceRelay.accept(formatPace(watchSegmentPace))
            avgHRRelay.accept(formatHeartRate(watchAvgHeartRate))
            segmentHRRelay.accept(formatHeartRate(watchSegmentAvgHR))
            return
        }

        avgPaceRelay.accept(totalDist > 10 ? formatPace(elapsed / (totalDist / 1000.0)) : "--'--\"")
        segmentPaceRelay.accept(formatPace(calculateCurrentSegmentPace(totalDistance: totalDist)))

        let metrics = HealthKitStore.shared.currentPhoneWorkoutMetrics
        avgHRRelay.accept(formatHeartRate(metrics.avgHeartRate))
        segmentHRRelay.accept(formatHeartRate(calculateCurrentSegmentAverageHeartRate(from: metrics)))
    }

    // MARK: - Helpers
    private func calculateTotalDistance() -> CLLocationDistance {
        guard allLocations.count >= 2 else { return 0 }
        var dist: CLLocationDistance = 0
        for i in 0..<allLocations.count - 1 {
            dist += allLocations[i+1].distance(from: allLocations[i])
        }
        return dist
    }

    private func calculateCurrentSegmentPace(totalDistance: CLLocationDistance) -> TimeInterval? {
        let segDist = totalDistance - segmentStartDistance
        let segElapsed = elapsed - segmentStartElapsed
        guard segDist > 10, segElapsed > 0 else { return nil }
        return segElapsed / (segDist / 1000.0)
    }

    private func calculateCurrentSegmentAverageHeartRate(from metrics: HealthKitStore.PhoneWorkoutMetrics) -> Double? {
        guard let segmentStartDate else { return nil }
        let samples = metrics.heartRateSamples.filter { $0.date >= segmentStartDate }
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

    private func resetSegmentState(startDate: Date) {
        nextSegmentBoundary = 1000
        segmentStartDistance = 0
        segmentStartElapsed = 0
        segmentStartDate = startDate
    }

    private func advanceSegmentBoundaryIfNeeded(totalDistance: Double, at date: Date) {
        while totalDistance >= nextSegmentBoundary {
            nextSegmentBoundary += 1000
            segmentStartDistance = totalDistance
            segmentStartElapsed = elapsed
            segmentStartDate = date
        }
    }

    private func buildSplits() -> [WorkoutResultDataModel.SplitData] {
        guard allLocations.count >= 2 else { return [] }
        var splits: [WorkoutResultDataModel.SplitData] = []
        var accumulated: Double = 0
        var kmStartTime = allLocations[0].timestamp
        var currentKm = 1

        for i in 1..<allLocations.count {
            let segDist = allLocations[i].distance(from: allLocations[i - 1])
            accumulated += segDist
            while accumulated >= Double(currentKm) * 1000 {
                let dur = allLocations[i].timestamp.timeIntervalSince(kmStartTime)
                splits.append(WorkoutResultDataModel.SplitData(km: currentKm, pace: dur > 0 ? dur : 0, distance: 1000))
                kmStartTime = allLocations[i].timestamp
                currentKm += 1
            }
        }

        let remaining = accumulated - Double(currentKm - 1) * 1000
        if remaining > 100, let last = allLocations.last {
            let dur = last.timestamp.timeIntervalSince(kmStartTime)
            let pace = dur / (remaining / 1000)
            splits.append(WorkoutResultDataModel.SplitData(km: currentKm, pace: pace, distance: remaining))
        }
        return splits
    }

    // MARK: - Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
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

    private func setupSnapshotObserver() {
        snapshotObserver = NotificationCenter.default.addObserver(
            forName: WatchBridge.workoutSnapshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let snapshot = note.userInfo?["snapshot"] as? WorkoutDataSnapshot else { return }
            self.applySnapshot(snapshot)
        }

        disconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, self.isWatchPrimary, self.phase != .finished else { return }
            if let last = self.lastSnapshotDate, Date().timeIntervalSince(last) > 10 {
                self.sourceBadgeRelay.accept(.disconnected)
            } else {
                self.sourceBadgeRelay.accept(.connected)
            }
        }
    }

    private func applySnapshot(_ snapshot: WorkoutDataSnapshot) {
        lastSnapshotDate = Date()
        elapsed = snapshot.elapsed
        watchTotalDistance = snapshot.totalDistance
        watchAvgPace = snapshot.avgPace
        watchSegmentPace = snapshot.segmentPace ?? snapshot.currentPace
        watchAvgHeartRate = snapshot.avgHeartRate
        watchSegmentAvgHR = snapshot.segmentAvgHeartRate ?? snapshot.heartRate

        if let lat = snapshot.currentLatitude, let lng = snapshot.currentLongitude {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            if routeCoordinates.last.map({ $0.latitude == coord.latitude && $0.longitude == coord.longitude }) != true {
                routeCoordinates.append(coord)
                routeHeartRates.append(snapshot.heartRate)
            }
        }

        switch snapshot.phase {
        case "preparing":
            let endsAt = snapshot.countdownEndsAt.map(Date.init(timeIntervalSince1970:))
            updateWatchPreparingCountdown(endsAt: endsAt, countdownValue: snapshot.countdownValue)
            return
        case "paused":
            exitPreparingStateIfNeeded()
            phase = .paused
            phaseRelay.accept(.paused)
        case "running":
            exitPreparingStateIfNeeded()
            phase = .running
            phaseRelay.accept(.running)
        case "finished":
            exitPreparingStateIfNeeded()
            isStoppingFromMirror = false
            finishWorkout(showResult: true)
            return
        default:
            break
        }

        updateMetrics()

        if let lat = snapshot.currentLatitude, let lng = snapshot.currentLongitude {
            emitRouteUpdate(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
    }

    private func emitRouteUpdate(coordinate: CLLocationCoordinate2D) {
        routeUpdateRelay.accept(WorkoutRouteUpdate(
            coordinate    : coordinate,
            allCoordinates: routeCoordinates,
            allHeartRates : routeHeartRates,
            isFirstUpdate : isFirstMapUpdate
        ))
        isFirstMapUpdate = false
    }

    // MARK: - Notification selectors
    @objc private func stopFromMirror() {
        guard isWatchPrimary, !hasShownResult else { return }
        isStoppingFromMirror = false
        finishWorkout(showResult: true)
    }

    @objc private func fallbackToPhone() {
        guard isWatchPrimary else { return }
        isWatchPrimary = false
        isStoppingFromMirror = false
        if let obs = snapshotObserver {
            NotificationCenter.default.removeObserver(obs)
            snapshotObserver = nil
        }
        disconnectTimer?.invalidate()
        disconnectTimer = nil
        sourceBadgeRelay.accept(.hidden)

        setupLocationManager()
        locationManager.requestWhenInUseAuthorization()

        if phase == .preparing {
            watchCountdownTimer?.invalidate()
            watchCountdownTimer = nil
            beginCountdown()
            return
        }

        guard phase == .running || phase == .paused else { return }
        let startDate = workoutStartDate ?? Date()
        HealthKitStore.shared.startPhoneWorkout(kind: .freeRun, isIndoor: isIndoor, start: startDate) { [weak self] ok, _ in
            guard let self, ok, self.phase == .running else { return }
            DispatchQueue.main.async {
                self.locationManager.startUpdatingLocation()
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension FreeRunViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        allLocations.append(loc)
        routeCoordinates.append(loc.coordinate)
        routeHeartRates.append(HealthKitStore.shared.currentPhoneWorkoutMetrics.heartRate)

        advanceSegmentBoundaryIfNeeded(totalDistance: calculateTotalDistance(), at: loc.timestamp)

        emitRouteUpdate(coordinate: loc.coordinate)
        updateMetrics()
    }
}

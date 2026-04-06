//
//  FreeRunViewController.swift
//  Hanttam
//
//  Created by passi on 3/31/26.
//

import UIKit
import SwiftUI
import CoreLocation
import MapKit
import SnapKit
internal import HealthKit

final class FreeRunViewController: HTViewController, CLLocationManagerDelegate, MKMapViewDelegate {
    private let isIndoor: Bool
    private var isWatchPrimary: Bool
    
    // MARK: - Properties
    private let locationManager = CLLocationManager()
    private var allLocations    : [CLLocation] = []
    private var recentLocations : [CLLocation] = []
    private var routeCoordinates: [CLLocationCoordinate2D] = []

    private var elapsed: TimeInterval = 0
    private var timer  : Timer?
    private var phase: WorkoutPhase = .preparing
    private var countdown: Int = 3
    private var snapshotObserver: NSObjectProtocol?
    private var phoneMetricsObserver: NSObjectProtocol?
    private var lastSnapshotDate: Date?
    private var disconnectTimer: Timer?
    private var watchCountdownTimer: Timer?
    private var watchCountdownEndsAt: Date?
    private var watchTotalDistance: Double = 0
    private var watchAvgPace: TimeInterval?
    private var watchSegmentPace: TimeInterval?
    private var watchAvgHeartRate: Double?
    private var watchSegmentAvgHeartRate: Double?
    private var hasShownResult = false
    private var isFirstMapUpdate = true
    private var workoutStartDate: Date?
    private var isPresentingResult = false
    private var isStoppingFromMirror = false
    private var nextSegmentBoundary: Double = 1000
    private var segmentStartDistance: Double = 0
    private var segmentStartElapsed: TimeInterval = 0
    private var segmentStartDate: Date?
    
    // MARK: - UI Components
    private let mapView            = MKMapView()
    private let statsPanel         = UIStackView()
    private let countdownLabel     = UILabel()
    private let countdownSubLabel  = UILabel()
    private let countdownContainer = UIView()
    
    private let pauseButton     = UIButton()
    private let stopButton      = UIButton()
    private let resumeButton    = UIButton()
    private let buttonContainer = UIView()
    
    private let durationLabel      = UILabel()
    private let distanceLabel      = UILabel()
    private let avgPaceLabel       = UILabel()
    private let currPaceLabel      = UILabel()
    private let avgHeartRateLabel  = UILabel()
    private let currHeartRateLabel = UILabel()
    
    private let pausedOverlay = UIView()
    private let pausedLabel   = UILabel()
    private let sourceBadge = UILabel()
    
    // MARK: - Layout Helpers
    private let paceStack = UIStackView()
    private let hrStack   = UIStackView()
    private let d1        = UIView()
    private let d2        = UIView()
    
    init(isIndoor: Bool = false, isWatchPrimary: Bool = false) {
        self.isIndoor = isIndoor
        self.isWatchPrimary = isWatchPrimary
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    
    //MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        if !isWatchPrimary {
            setupLocationManager()
        }
        setupPhoneMetricsObserver()
        if isWatchPrimary {
            enterWatchPreparingState()
        } else {
            beginCountdown()
        }

        if isWatchPrimary {
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
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if phase != .finished && !isPresentingResult {
            finishWorkout(showResult: false)
        }
    }

    deinit {
        if let snapshotObserver {
            NotificationCenter.default.removeObserver(snapshotObserver)
        }
        if let phoneMetricsObserver {
            NotificationCenter.default.removeObserver(phoneMetricsObserver)
        }
        watchCountdownTimer?.invalidate()
    }
    
    override func configHierarchy() {
        view.addSubview(mapView)
        view.addSubview(statsPanel)
        view.addSubview(buttonContainer)
        view.addSubview(countdownContainer)
        view.addSubview(pausedOverlay)
        view.addSubview(sourceBadge)
        
        // Stats Panel Hierarchy
        statsPanel.addArrangedSubview(createStatRow(label: "DURATION", valueLabel: durationLabel))
        statsPanel.addArrangedSubview(createDivider())
        statsPanel.addArrangedSubview(createStatRow(label: "DISTANCE", valueLabel: distanceLabel))
        statsPanel.addArrangedSubview(createDivider())
        
        paceStack.addArrangedSubview(createStatRow(label: "AVG PACE", valueLabel: avgPaceLabel))
        paceStack.addSubview(d1)
        paceStack.addArrangedSubview(createStatRow(label: "SEGMENT PACE", valueLabel: currPaceLabel))
        statsPanel.addArrangedSubview(paceStack)
        statsPanel.addArrangedSubview(createDivider())
        
        hrStack.addArrangedSubview(createStatRow(label: "AVG HEART RATE", valueLabel: avgHeartRateLabel))
        hrStack.addSubview(d2)
        hrStack.addArrangedSubview(createStatRow(label: "SEGMENT HEART RATE", valueLabel: currHeartRateLabel))
        statsPanel.addArrangedSubview(hrStack)
        statsPanel.addArrangedSubview(createDivider())
        
        // Button Container Hierarchy
        buttonContainer.addSubview(pauseButton)
        buttonContainer.addSubview(resumeButton)
        buttonContainer.addSubview(stopButton)
        
        // Countdown Hierarchy
        countdownContainer.addSubview(countdownLabel)
        countdownContainer.addSubview(countdownSubLabel)
        
        // Paused Overlay Hierarchy
        pausedOverlay.addSubview(pausedLabel)
    }
    
    override func configLayout() {
        mapView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(statsPanel.snp.top).offset(-12)
        }
        
        statsPanel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.bottom.equalTo(buttonContainer.snp.top)
        }
        
        buttonContainer.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-12)
            make.height.equalTo(116)
        }
        
        pauseButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(76)
        }
        
        resumeButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.centerX.equalToSuperview().offset(-60)
            make.width.height.equalTo(76)
        }
        
        stopButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.centerX.equalToSuperview().offset(60)
            make.width.height.equalTo(76)
        }
        
        d1.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.bottom.equalToSuperview()
            make.width.equalTo(1)
        }
        
        d2.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.bottom.equalToSuperview()
            make.width.equalTo(1)
        }
        
        countdownContainer.snp.makeConstraints { make in
            make.edges.equalTo(mapView)
        }
        
        countdownLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        countdownSubLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(countdownLabel.snp.bottom).offset(8)
        }
        
        pausedOverlay.snp.makeConstraints { make in
            make.edges.equalTo(mapView)
        }
        
        pausedLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        sourceBadge.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(10)
            make.centerX.equalToSuperview()
        }
    }
    
    override func configView() {
        view.backgroundColor = AppColor.UI.backgroundGrouped
        
        mapView.delegate                 = self
        mapView.isUserInteractionEnabled = false
        // mapView.showsUserLocation        = true
        mapView.mapType                  = .mutedStandard
        let config                   = MKStandardMapConfiguration()
        config.emphasisStyle         = .muted
        config.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration   = config
        mapView.layer.cornerRadius = 30
        mapView.layer.masksToBounds = true
        
        statsPanel.axis            = .vertical
        statsPanel.spacing         = 0
        statsPanel.backgroundColor = AppColor.UI.cardBackground.withAlphaComponent(0.96)
        statsPanel.layer.cornerRadius = 28
        statsPanel.layer.borderWidth = 1
        statsPanel.layer.borderColor = AppColor.UI.border.withAlphaComponent(0.7).cgColor
        statsPanel.layer.masksToBounds = true
        statsPanel.alpha           = 1
        
        paceStack.axis         = .horizontal
        paceStack.distribution = .fillEqually
        
        hrStack.axis         = .horizontal
        hrStack.distribution = .fillEqually
        
        d1.backgroundColor = AppColor.UI.separator
        d2.backgroundColor = AppColor.UI.separator
        
        // Button Container
        buttonContainer.backgroundColor = .clear
        buttonContainer.isHidden        = true
        
        // Buttons
        pauseButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)), for: .normal)
        pauseButton.tintColor          = AppColor.UI.textInverse
        pauseButton.backgroundColor    = AppColor.UI.workoutPause
        pauseButton.layer.cornerRadius = 38
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        
        resumeButton.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)), for: .normal)
        resumeButton.tintColor          = AppColor.UI.textInverse
        resumeButton.backgroundColor    = AppColor.UI.workoutResume
        resumeButton.layer.cornerRadius = 38
        resumeButton.addTarget(self, action: #selector(resumeTapped), for: .touchUpInside)
        resumeButton.isHidden           = true
        
        stopButton.setImage(UIImage(systemName: "stop.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)), for: .normal)
        stopButton.tintColor          = AppColor.UI.textInverse
        stopButton.backgroundColor    = AppColor.UI.workoutStop
        stopButton.layer.cornerRadius = 38
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        stopButton.isHidden           = true
        
        // Countdown Container
        countdownContainer.backgroundColor = AppColor.UI.backgroundGrouped
        
        countdownLabel.font          = AppFont.UI.metricDisplayXL
        countdownLabel.textColor     = AppColor.UI.workoutPause
        countdownLabel.textAlignment = .center
        countdownLabel.text          = "3"
        
        countdownSubLabel.font          = AppFont.UI.titleSM
        countdownSubLabel.textColor     = AppColor.UI.textSecondary
        countdownSubLabel.textAlignment = .center
        countdownSubLabel.text          = "준비하세요"
        
        // Paused Overlay
        pausedOverlay.backgroundColor = AppColor.UI.overlay
        pausedOverlay.isHidden        = true
        
        pausedLabel.text          = "일시정지"
        pausedLabel.font          = AppFont.UI.headlineLG
        pausedLabel.textColor     = AppColor.UI.textInverse
        pausedLabel.textAlignment = .center
        
        // Default values
        durationLabel.text      = "00:00"
        distanceLabel.text      = "0.00KM"
        avgPaceLabel.text       = "--'--\""
        currPaceLabel.text      = "--'--\""
        avgHeartRateLabel.text  = "--"
        currHeartRateLabel.text = "--"

        sourceBadge.textColor = AppColor.UI.textSecondary
        sourceBadge.backgroundColor = AppColor.UI.backgroundTertiary.withAlphaComponent(0.95)
        sourceBadge.layer.cornerRadius = 14
        sourceBadge.layer.borderWidth = 1
        sourceBadge.layer.borderColor = AppColor.UI.border.withAlphaComponent(0.8).cgColor
    }
    
    private func createStatRow(label: String, valueLabel: UILabel) -> UIView {
        let container = UIView()
        container.backgroundColor = AppColor.UI.backgroundSecondary
        container.layer.cornerRadius = 18
        container.layer.masksToBounds = true
        
        let lLabel           = UILabel()
        lLabel.text          = label
        lLabel.font          = AppFont.UI.labelMD
        lLabel.textColor     = AppColor.UI.textSecondary
        lLabel.textAlignment = .left
        
        if valueLabel === distanceLabel {
            valueLabel.font = UIFont.systemFont(ofSize: 38, weight: .black)
            valueLabel.textColor = RunningLevelManager.shared.accentUIColor
        } else if valueLabel === currPaceLabel {
            valueLabel.font = AppFont.UI.metricTitle
            valueLabel.textColor = AppColor.UI.textPrimary
        } else {
            valueLabel.font = AppFont.UI.metricBody
            valueLabel.textColor = AppColor.UI.textPrimary
        }
        valueLabel.textAlignment = .left
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        
        let stack     = UIStackView(arrangedSubviews: [lLabel, valueLabel])
        stack.axis    = .vertical
        stack.spacing = 6
        container.addSubview(stack)
        
        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.bottom.equalToSuperview().offset(-14)
            make.leading.trailing.equalToSuperview().inset(16)
        }

        let rowHeight: CGFloat = valueLabel === distanceLabel ? 118 : 72
        container.snp.makeConstraints { make in
            make.height.equalTo(rowHeight)
        }
        
        return container
    }
    
    private func createDivider(isVertical: Bool = false) -> UIView {
        let divider = UIView()
        divider.backgroundColor = .clear
        if isVertical {
            divider.snp.makeConstraints { make in
                make.width.equalTo(10)
            }
        } else {
            divider.snp.makeConstraints { make in
                make.height.equalTo(10)
            }
        }
        return divider
    }
    
    // MARK: - Phase Management

    private func beginCountdown() {
        phase = .preparing
        countdown = 1 // 1초로 단축하여 즉시 시작하는 느낌을 줌
        countdownLabel.text = "\(countdown)"

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.countdown -= 1
            if self.countdown > 0 {
                self.animateCountdown(self.countdown)
            } else {
                t.invalidate()
                self.countdownFinished()
            }
        }
    }

    private func animateCountdown(_ value: Int) {
        countdownLabel.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        countdownLabel.alpha = 0
        countdownLabel.text = "\(value)"
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: []) {
            self.countdownLabel.transform = .identity
            self.countdownLabel.alpha = 1
        }
    }

    private func countdownFinished() {
        UIView.animate(withDuration: 0.3) {
            self.countdownContainer.alpha = 0
            self.statsPanel.alpha = 1
        } completion: { _ in
            self.countdownContainer.isHidden = true
            self.buttonContainer.isHidden = false
        }
        if isWatchPrimary {
            startRunning(startDate: Date())
            return
        }

        let startDate = Date()
        HealthKitStore.shared.startPhoneWorkout(kind: .freeRun, isIndoor: isIndoor, start: startDate) { [weak self] ok, error in
            guard let self else { return }
            guard ok else {
                self.showAlert(
                    title: "운동 시작 실패",
                    message: error?.localizedDescription ?? "건강 권한 또는 세션 상태를 확인해주세요."
                ) { [weak self] in
                    self?.dismiss(animated: true)
                }
                return
            }
            self.startRunning(startDate: startDate)
        }
    }

    private func startRunning(startDate: Date) {
        phase = .running
        workoutStartDate = startDate
        resetSegmentState(startDate: startDate)
        if !isWatchPrimary {
            locationManager.startUpdatingLocation()
        }
        // Always run a local timer so duration never appears frozen.
        // When a watch snapshot arrives, applySnapshot overwrites elapsed, keeping them in sync.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.phase == .running else { return }
            self.elapsed += 1
            self.updateUI()
        }
        showRunningButtons()
    }

    private func enterWatchPreparingState(countdownValue: Int? = nil) {
        phase = .preparing
        if let countdownValue {
            countdown = countdownValue
        }
        countdownLabel.text = "\(max(countdown, 0))"
        countdownContainer.alpha = 1
        countdownContainer.isHidden = false
        buttonContainer.isHidden = true
        pausedOverlay.isHidden = true
    }

    private func updateWatchPreparingCountdown(endsAt: Date?, countdownValue: Int?) {
        watchCountdownEndsAt = endsAt
        enterWatchPreparingState(countdownValue: countdownValue)
        watchCountdownTimer?.invalidate()

        guard let endsAt else { return }
        watchCountdownTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let remaining = max(0, Int(ceil(endsAt.timeIntervalSinceNow)))
            self.countdownLabel.text = "\(remaining)"
            if remaining <= 0 {
                timer.invalidate()
                self.watchCountdownTimer = nil
            }
        }
    }

    @objc private func pauseTapped() {
        if isWatchPrimary {
            guard WatchBridge.shared.sendWorkoutCommand(WorkoutStreamKey.commandPause) else {
                showAlert(title: "워치 연결 필요", message: "워치 연결을 확인해주세요.")
                return
            }
            // Optimistic UI: apply local state immediately; watch snapshot will confirm
            phase = .paused
            pausedOverlay.isHidden = false
            showPausedButtons()
            return
        }
        phase = .paused
        locationManager.stopUpdatingLocation()
        HealthKitStore.shared.pausePhoneWorkout()
        pausedOverlay.isHidden = false
        showPausedButtons()
    }

    @objc private func resumeTapped() {
        if isWatchPrimary {
            guard WatchBridge.shared.sendWorkoutCommand(WorkoutStreamKey.commandResume) else {
                showAlert(title: "워치 연결 필요", message: "워치 연결을 확인해주세요.")
                return
            }
            // Optimistic UI: apply local state immediately; watch snapshot will confirm
            phase = .running
            pausedOverlay.isHidden = true
            showRunningButtons()
            return
        }
        phase = .running
        locationManager.startUpdatingLocation()
        HealthKitStore.shared.resumePhoneWorkout()
        pausedOverlay.isHidden = true
        showRunningButtons()
    }

    @objc private func stopTapped() {
        if isWatchPrimary {
            guard !isStoppingFromMirror else { return }
            guard WatchBridge.shared.sendWorkoutCommand(WorkoutStreamKey.commandStop) else {
                showAlert(title: "워치 연결 필요", message: "워치 연결을 확인해주세요.")
                return
            }
            isStoppingFromMirror = true
            return
        }
        isPresentingResult = true
        finishWorkout(showResult: true)
    }

    @objc private func stopFromMirror() {
        guard isWatchPrimary else { return }
        guard !hasShownResult else { return }
        isStoppingFromMirror = false
        isPresentingResult = true
        finishWorkout(showResult: true)
    }

    @objc private func fallbackToPhone() {
        guard isWatchPrimary else { return }
        isWatchPrimary = false
        isStoppingFromMirror = false
        // 스냅샷 옵저버 제거
        if let obs = snapshotObserver {
            NotificationCenter.default.removeObserver(obs)
            snapshotObserver = nil
        }
        disconnectTimer?.invalidate()
        disconnectTimer = nil
        sourceBadge.isHidden = true

        // 위치 권한 및 매니저 초기화
        setupLocationManager()
        locationManager.requestWhenInUseAuthorization()

        if phase == .preparing {
            watchCountdownTimer?.invalidate()
            watchCountdownTimer = nil
            beginCountdown()
            return
        }

        // 카운트다운 중이면 countdownFinished()에서 폰 HK 세션을 자동으로 시작하므로 여기서는 종료
        guard phase == .running || phase == .paused else { return }

        let startDate = workoutStartDate ?? Date()
        HealthKitStore.shared.startPhoneWorkout(kind: .freeRun, isIndoor: isIndoor, start: startDate) { [weak self] ok, _ in
            guard let self, ok, self.phase == .running else { return }
            DispatchQueue.main.async {
                self.locationManager.startUpdatingLocation()
            }
        }
    }

    private func finishWorkout(showResult: Bool) {
        guard phase != .finished else {
            if showResult {
                showResultScreen(workout: nil)
            }
            return
        }

        phase = .finished
        isStoppingFromMirror = false
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil

        guard !isWatchPrimary else {
            if showResult {
                showResultScreen(workout: nil)
            }
            return
        }

        let totalDistance = calculateTotalDistance()
        let endDate = Date()
        let duration = endDate.timeIntervalSince(workoutStartDate ?? endDate)

        guard HealthKitStore.shared.shouldSaveWorkout(duration: duration, distance: totalDistance) else {
            HealthKitStore.shared.discardActivePhoneWorkout { [weak self] _, _ in
                guard let self else { return }
                if showResult {
                    self.showResultScreen(workout: nil)
                }
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

            let openResult = {
                if showResult {
                    self.showResultScreen(workout: workout)
                }
            }

            if success {
                if let error {
                    self.showAlert(title: "운동 저장 완료", message: "운동은 저장됐지만 경로 저장 중 일부 문제가 발생했습니다.\n\(error.localizedDescription)") {
                        openResult()
                    }
                } else {
                    openResult()
                }
            } else {
                self.showAlert(title: "운동 저장 실패", message: error?.localizedDescription ?? "운동을 저장하지 못했습니다.") {
                    openResult()
                }
            }
        }
    }

    private func showResultScreen(workout: HKWorkout?) {
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
        let resultVC = WorkoutResultViewController(data: resultData)
        resultVC.modalPresentationStyle = .fullScreen
        present(resultVC, animated: true) { [weak self] in
            // 결과 화면 dismiss 시 운동 화면도 같이 dismiss
            resultVC.onDismiss = {
                self?.dismiss(animated: true)
            }
        }
    }

    private func buildSplits() -> [WorkoutResultDataModel.SplitData] {
        guard allLocations.count >= 2 else { return [] }
        var splits: [WorkoutResultDataModel.SplitData] = []
        var accumulated: Double = 0
        var kmStartIndex = 0
        var kmStartTime = allLocations[0].timestamp
        var currentKm = 1

        for i in 1..<allLocations.count {
            let segDist = allLocations[i].distance(from: allLocations[i - 1])
            accumulated += segDist

            while accumulated >= Double(currentKm) * 1000 {
                let dur = allLocations[i].timestamp.timeIntervalSince(kmStartTime)
                let pace = dur > 0 ? dur : 0
                splits.append(WorkoutResultDataModel.SplitData(km: currentKm, pace: pace, distance: 1000))
                kmStartTime = allLocations[i].timestamp
                kmStartIndex = i
                currentKm += 1
            }
        }

        // 마지막 불완전 km
        let remaining = accumulated - Double(currentKm - 1) * 1000
        if remaining > 100, let last = allLocations.last {
            let dur = last.timestamp.timeIntervalSince(kmStartTime)
            let pace = dur / (remaining / 1000)
            splits.append(WorkoutResultDataModel.SplitData(km: currentKm, pace: pace, distance: remaining))
        }

        return splits
    }

    private func showRunningButtons() {
        pauseButton.isHidden = false
        resumeButton.isHidden = true
        stopButton.isHidden = true
    }

    private func showPausedButtons() {
        pauseButton.isHidden = true
        resumeButton.isHidden = false
        stopButton.isHidden = false
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
            self.updateUI()
        }
    }

    private func updateUI() {
        // Duration
        let h = Int(elapsed) / 3600
        let m = Int(elapsed) % 3600 / 60
        let s = Int(elapsed) % 60
        durationLabel.text = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)

        // Distance
        let totalDist = isWatchPrimary ? watchTotalDistance : calculateTotalDistance()
        distanceLabel.text = String(format: "%.2fKM", totalDist / 1000.0)

        if isWatchPrimary {
            avgPaceLabel.text = formatPace(watchAvgPace)
            currPaceLabel.text = formatPace(watchSegmentPace)
            avgHeartRateLabel.text = formatHeartRate(watchAvgHeartRate)
            currHeartRateLabel.text = formatHeartRate(watchSegmentAvgHeartRate)
            return
        }

        if totalDist > 10 {
            avgPaceLabel.text = formatPace(elapsed / (totalDist / 1000.0))
        } else {
            avgPaceLabel.text = "--'--\""
        }

        currPaceLabel.text = formatPace(calculateCurrentSegmentPace(totalDistance: totalDist))

        let metrics = HealthKitStore.shared.currentPhoneWorkoutMetrics
        avgHeartRateLabel.text = formatHeartRate(metrics.avgHeartRate)
        currHeartRateLabel.text = formatHeartRate(calculateCurrentSegmentAverageHeartRate(from: metrics))
    }

    private func calculateTotalDistance() -> CLLocationDistance {
        guard allLocations.count >= 2 else { return 0 }
        var dist: CLLocationDistance = 0
        for i in 0..<allLocations.count - 1 {
            dist += allLocations[i+1].distance(from: allLocations[i])
        }
        return dist
    }

    private func calculateCurrentSegmentPace(totalDistance: CLLocationDistance) -> TimeInterval? {
        let segmentDistance = totalDistance - segmentStartDistance
        let segmentElapsed = elapsed - segmentStartElapsed
        guard segmentDistance > 10, segmentElapsed > 0 else { return nil }
        return segmentElapsed / (segmentDistance / 1000.0)
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

    private func calculateCurrentSegmentAverageHeartRate(from metrics: HealthKitStore.PhoneWorkoutMetrics) -> Double? {
        guard let segmentStartDate else { return nil }
        let samples = metrics.heartRateSamples.filter { $0.date >= segmentStartDate }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0) { $0 + $1.bpm } / Double(samples.count)
    }

    private func setupSnapshotObserver() {
        snapshotObserver = NotificationCenter.default.addObserver(
            forName: WatchBridge.workoutSnapshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let snapshot = note.userInfo?["snapshot"] as? WorkoutDataSnapshot else { return }
            self.lastSnapshotDate = Date()
            self.elapsed = snapshot.elapsed
            self.watchTotalDistance = snapshot.totalDistance
            self.watchAvgPace = snapshot.avgPace
            self.watchSegmentPace = snapshot.segmentPace ?? snapshot.currentPace
            self.watchAvgHeartRate = snapshot.avgHeartRate
            self.watchSegmentAvgHeartRate = snapshot.segmentAvgHeartRate ?? snapshot.heartRate
            self.routeCoordinates = {
                guard let lat = snapshot.currentLatitude, let lng = snapshot.currentLongitude else {
                    return self.routeCoordinates
                }
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                if let last = self.routeCoordinates.last,
                   last.latitude == coord.latitude,
                   last.longitude == coord.longitude {
                    return self.routeCoordinates
                }
                return self.routeCoordinates + [coord]
            }()

            switch snapshot.phase {
            case "preparing":
                let endsAt = snapshot.countdownEndsAt.map(Date.init(timeIntervalSince1970:))
                self.updateWatchPreparingCountdown(endsAt: endsAt, countdownValue: snapshot.countdownValue)
                return
            case "paused":
                self.watchCountdownTimer?.invalidate()
                self.watchCountdownTimer = nil
                self.phase = .paused
                self.pausedOverlay.isHidden = false
                self.showPausedButtons()
            case "running":
                self.watchCountdownTimer?.invalidate()
                self.watchCountdownTimer = nil
                self.phase = .running
                self.pausedOverlay.isHidden = true
                self.showRunningButtons()
            case "finished":
                self.watchCountdownTimer?.invalidate()
                self.watchCountdownTimer = nil
                self.isStoppingFromMirror = false
                self.isPresentingResult = true
                self.finishWorkout(showResult: true)
                return
            default:
                break
            }

            self.updateUI()

            if let lat = snapshot.currentLatitude, let lng = snapshot.currentLongitude {
                self.updateMap(with: CLLocationCoordinate2D(latitude: lat, longitude: lng))
            }
        }

        disconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, self.isWatchPrimary else { return }
            if self.phase == .finished { return }
            if let last = self.lastSnapshotDate, Date().timeIntervalSince(last) > 10 {
                self.sourceBadge.text = " 워치 연결 끊김 "
                self.sourceBadge.textColor = AppColor.UI.workoutStop
                self.sourceBadge.isHidden = false
            } else {
                self.sourceBadge.text = " Apple Watch에서 센서 측정 중 "
                self.sourceBadge.textColor = AppColor.UI.success
                self.sourceBadge.isHidden = false
            }
        }
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        allLocations.append(loc)
        routeCoordinates.append(loc.coordinate)

        recentLocations.append(loc)
        if recentLocations.count > 8 { recentLocations.removeFirst() }
        advanceSegmentBoundaryIfNeeded(totalDistance: calculateTotalDistance(), at: loc.timestamp)

        updateMap(with: loc.coordinate)
        updateUI()
    }

    private func updateMap(with coordinate: CLLocationCoordinate2D) {
        if isFirstMapUpdate {
            let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 300, longitudinalMeters: 300)
            mapView.setRegion(region, animated: false)
            isFirstMapUpdate = false
        } else {
            let camera = MKMapCamera(lookingAtCenter: coordinate, fromDistance: 300, pitch: 0, heading: 0)
            mapView.setCamera(camera, animated: true)
        }

        // Update Polyline
        mapView.removeOverlays(mapView.overlays)
        if routeCoordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
            mapView.addOverlay(polyline)
        }

        // Update Marker
        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        mapView.addAnnotation(annotation)
    }

    // MARK: - MKMapViewDelegate
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(AppColor.workoutRoute)
            renderer.lineWidth = 6
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }
        let id = "currentLocation"
        var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
        if view == nil {
            view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
        } else {
            view?.annotation = annotation
        }
        view?.markerTintColor = UIColor(AppColor.workoutRoute)
        view?.glyphText = ""
        return view
    }

    private func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }

}

// MARK: - SwiftUI Wrapper

struct FreeRunView: UIViewControllerRepresentable {
    var isIndoor: Bool = false
    var isWatchPrimary: Bool = false

    func makeUIViewController(context: Context) -> FreeRunViewController {
        return FreeRunViewController(isIndoor: isIndoor, isWatchPrimary: isWatchPrimary)
    }

    func updateUIViewController(_ uiViewController: FreeRunViewController, context: Context) {}
}

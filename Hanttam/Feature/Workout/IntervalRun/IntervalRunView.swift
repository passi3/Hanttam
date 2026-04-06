//
//  IntervalRunView.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import UIKit
import MapKit
import CoreLocation
import SwiftUI
import SnapKit
internal import HealthKit

// MARK: - ViewController

class IntervalRunViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate {

    // MARK: - Phase

    private enum Phase {
        case preparing
        case runningLap
        case resting
        indirect case paused(prior: Phase)
        case finished
    }

    // MARK: - Init Params

    private let totalSets     : Int
    private let lapDistance   : Double
    private let restDuration  : TimeInterval
    private let isIndoor      : Bool
    private var isWatchPrimary: Bool

    init(sets: Int, lapDistance: Double, restDuration: TimeInterval, isIndoor: Bool = false, isWatchPrimary: Bool = false) {
        self.totalSets      = sets
        self.lapDistance    = lapDistance
        self.restDuration   = restDuration
        self.isIndoor       = isIndoor
        self.isWatchPrimary = isWatchPrimary
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - State

    private var phase: Phase                = .preparing
    private var currentSet: Int             = 1
    private var elapsed: TimeInterval       = 0
    private var lapElapsed: TimeInterval    = 0
    private var lapDistance_: Double        = 0  // current lap distance accumulated
    private var restRemaining: TimeInterval = 0
    private var countdown: Int              = 3
    private var timer: Timer?
    private var snapshotObserver: NSObjectProtocol?
    private var phoneMetricsObserver: NSObjectProtocol?
    private var lastSnapshotDate: Date?
    private var disconnectTimer: Timer?
    private var watchCountdownTimer: Timer?
    private var watchCountdownEndsAt: Date?
    private var hasShownResult = false
    private var isFirstMapUpdate = true
    private var workoutStartDate: Date?
    private var isPresentingResult = false
    private var watchAvgPace: TimeInterval?
    private var watchLapPace: TimeInterval?
    private var watchAvgHeartRate: Double?
    private var watchLapAvgHeartRate: Double?
    private var lastRunLapPace: TimeInterval?
    private var lastRunLapAvgHeartRate: Double?

    // location
    private let locationManager = CLLocationManager()
    private var allLocations: [CLLocation] = []
    private var lapLocations: [CLLocation] = []
    private var recentLocations: [CLLocation] = []
    private var routeCoordinates: [CLLocationCoordinate2D] = []

    // recording
    private var laps: [IntervalLap] = []
    private var lapStartDate = Date()

    // MARK: - UI Components

    private let mapView         = MKMapView()
    private let statsPanel      = UIStackView()
    private let buttonContainer = UIView()

    private let durationLabel    = UILabel()
    private let lapDistanceLabel = UILabel()
    private let avgPaceLabel     = UILabel()
    private let currPaceLabel    = UILabel()
    private let avgHeartRateLabel = UILabel()
    private let currHeartRateLabel = UILabel()
    private let setLabel         = UILabel()

    private let pauseButton     = UIButton()
    private let resumeButton    = UIButton()
    private let stopButton      = UIButton()
    private let manualLapButton = UIButton()

    private let countdownContainer = UIView()
    private let countdownLabel     = UILabel()
    private let countdownSubLabel  = UILabel()

    private let restOverlay        = UIView()
    private let restCountdownLabel = UILabel()
    private let restTitleLabel     = UILabel()

    private let pausedOverlay = UIView()
    private let pausedLabel   = UILabel()
    private let sourceBadge   = UILabel()
    private let hrStack       = UIStackView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
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
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stopFromMirror),
                                               name: WatchBridge.workoutStoppedNotification,
                                               object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if case .finished = phase {} else if !isPresentingResult {
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

    // MARK: - Setup UI

    private func setupUI() {
        view.backgroundColor = AppColor.UI.backgroundGrouped

        // MapView
        mapView.delegate = self
        mapView.isUserInteractionEnabled = false
        let config = MKStandardMapConfiguration()
        config.emphasisStyle = .muted
        config.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = config
        mapView.layer.cornerRadius = 30
        mapView.layer.masksToBounds = true
        view.addSubview(mapView)
        view.addSubview(sourceBadge)

        // Stats Panel
        statsPanel.axis = .vertical
        statsPanel.spacing = 0
        statsPanel.backgroundColor = AppColor.UI.cardBackground.withAlphaComponent(0.96)
        statsPanel.layer.cornerRadius = 28
        statsPanel.layer.borderWidth = 1
        statsPanel.layer.borderColor = AppColor.UI.border.withAlphaComponent(0.7).cgColor
        statsPanel.layer.masksToBounds = true
        view.addSubview(statsPanel)

        // Stats Rows
        statsPanel.addArrangedSubview(createStatRow(label: "DURATION", valueLabel: durationLabel))
        statsPanel.addArrangedSubview(createDivider())
        statsPanel.addArrangedSubview(createStatRow(label: "LAP DISTANCE", valueLabel: lapDistanceLabel))
        statsPanel.addArrangedSubview(createDivider())

        let paceStack = UIStackView()
        paceStack.axis = .horizontal
        paceStack.distribution = .fillEqually
        paceStack.addArrangedSubview(createStatRow(label: "AVG PACE", valueLabel: avgPaceLabel))
        let d1 = createDivider(isVertical: true)
        paceStack.addSubview(d1)
        paceStack.addArrangedSubview(createStatRow(label: "LAP PACE", valueLabel: currPaceLabel))
        statsPanel.addArrangedSubview(paceStack)
        statsPanel.addArrangedSubview(createDivider())

        hrStack.axis = .horizontal
        hrStack.distribution = .fillEqually
        hrStack.addArrangedSubview(createStatRow(label: "AVG HR", valueLabel: avgHeartRateLabel))
        let d2 = createDivider(isVertical: true)
        hrStack.addSubview(d2)
        hrStack.addArrangedSubview(createStatRow(label: "LAP HR", valueLabel: currHeartRateLabel))
        statsPanel.addArrangedSubview(hrStack)
        statsPanel.addArrangedSubview(createDivider())

        statsPanel.addArrangedSubview(createStatRow(label: "SET", valueLabel: setLabel))
        statsPanel.addArrangedSubview(createDivider())

        // Button Container
        buttonContainer.backgroundColor = .clear
        view.addSubview(buttonContainer)

        // Buttons
        configureButton(pauseButton, systemName: "pause.fill", color: AppColor.UI.workoutPause, action: #selector(pauseTapped))
        configureButton(resumeButton, systemName: "play.fill", color: AppColor.UI.workoutResume, action: #selector(resumeTapped))
        configureButton(stopButton, systemName: "stop.fill", color: AppColor.UI.workoutStop, action: #selector(stopTapped))
        resumeButton.isHidden = true
        stopButton.isHidden = true
        buttonContainer.addSubview(pauseButton)
        buttonContainer.addSubview(resumeButton)
        buttonContainer.addSubview(stopButton)

        // Manual Lap Button
        manualLapButton.setImage(UIImage(systemName: "forward.end.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)), for: .normal)
        manualLapButton.tintColor = AppColor.UI.textInverse
        manualLapButton.backgroundColor = AppColor.UI.primary
        manualLapButton.layer.cornerRadius = 28
        manualLapButton.addTarget(self, action: #selector(manualLapTapped), for: .touchUpInside)
        manualLapButton.isHidden = true
        buttonContainer.addSubview(manualLapButton)

        // Countdown
        countdownContainer.backgroundColor = AppColor.UI.backgroundGrouped
        view.addSubview(countdownContainer)
        countdownLabel.font = AppFont.UI.metricDisplayXL
        countdownLabel.textColor = AppColor.UI.workoutPause
        countdownLabel.textAlignment = .center
        countdownLabel.text = "3"
        countdownContainer.addSubview(countdownLabel)
        countdownSubLabel.font = AppFont.UI.titleSM
        countdownSubLabel.textColor = AppColor.UI.textSecondary
        countdownSubLabel.textAlignment = .center
        countdownSubLabel.text = "준비하세요"
        countdownContainer.addSubview(countdownSubLabel)

        // Rest Overlay
        restOverlay.backgroundColor = AppColor.UI.overlayStrong
        restOverlay.isHidden = true
        view.addSubview(restOverlay)

        restTitleLabel.text = "REST"
        restTitleLabel.font = AppFont.UI.titleSM
        restTitleLabel.textColor = AppColor.UI.textInverseSecondary
        restTitleLabel.textAlignment = .center
        restOverlay.addSubview(restTitleLabel)

        restCountdownLabel.font = AppFont.UI.metricDisplayLG
        restCountdownLabel.textColor = AppColor.UI.textInverse
        restCountdownLabel.textAlignment = .center
        restOverlay.addSubview(restCountdownLabel)

        // Paused Overlay
        pausedOverlay.backgroundColor = AppColor.UI.overlay
        pausedOverlay.isHidden = true
        view.addSubview(pausedOverlay)
        pausedLabel.text = "일시정지"
        pausedLabel.font = AppFont.UI.headlineLG
        pausedLabel.textColor = AppColor.UI.textInverse
        pausedLabel.textAlignment = .center
        pausedOverlay.addSubview(pausedLabel)

        sourceBadge.font = AppFont.UI.labelSM
        sourceBadge.textColor = AppColor.UI.textSecondary
        sourceBadge.backgroundColor = AppColor.UI.backgroundTertiary.withAlphaComponent(0.95)
        sourceBadge.layer.cornerRadius = 12
        sourceBadge.layer.masksToBounds = true
        sourceBadge.textAlignment = .center
        sourceBadge.text = " Apple Watch에서 센서 측정 중 "
        sourceBadge.isHidden = !isWatchPrimary
        sourceBadge.layer.cornerRadius = 14
        sourceBadge.layer.borderWidth = 1
        sourceBadge.layer.borderColor = AppColor.UI.border.withAlphaComponent(0.8).cgColor

        // Layout
        mapView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(statsPanel.snp.top).offset(-12)
        }
        sourceBadge.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(10)
            make.centerX.equalToSuperview()
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
        manualLapButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().offset(-32)
            make.width.height.equalTo(56)
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
        restOverlay.snp.makeConstraints { make in
            make.edges.equalTo(mapView)
        }
        restTitleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(restCountdownLabel.snp.top).offset(-4)
        }
        restCountdownLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        pausedOverlay.snp.makeConstraints { make in
            make.edges.equalTo(mapView)
        }
        pausedLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        // Defaults
        durationLabel.text = "00:00"
        lapDistanceLabel.text = "0m / \(Int(lapDistance))m"
        avgPaceLabel.text = "--'--\""
        currPaceLabel.text = "--'--\""
        avgHeartRateLabel.text = "--"
        currHeartRateLabel.text = "--"
        setLabel.text = "1 / \(totalSets)"

        statsPanel.alpha = 1
        buttonContainer.isHidden = true
    }

    private func configureButton(_ button: UIButton, systemName: String, color: UIColor, action: Selector) {
        button.setImage(UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)), for: .normal)
        button.tintColor          = AppColor.UI.textInverse
        button.backgroundColor    = color
        button.layer.cornerRadius = 38
        button.addTarget(self, action: action, for: .touchUpInside)
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

        if valueLabel === lapDistanceLabel {
            valueLabel.font = UIFont.systemFont(ofSize: 34, weight: .black)
            valueLabel.textColor = RunningLevelManager.shared.accentUIColor
        } else if valueLabel === currPaceLabel {
            valueLabel.font = AppFont.UI.metricTitle
            valueLabel.textColor = AppColor.UI.textPrimary
        } else if valueLabel === currHeartRateLabel {
            valueLabel.font = AppFont.UI.metricTitle
            valueLabel.textColor = AppColor.UI.textPrimary
        } else {
            valueLabel.font = AppFont.UI.metricBody
            valueLabel.textColor = AppColor.UI.textPrimary
        }
        valueLabel.textAlignment = .left
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        let stack = UIStackView(arrangedSubviews: [lLabel, valueLabel])
        stack.axis    = .vertical
        stack.spacing = 6
        container.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.bottom.equalToSuperview().offset(-14)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        let rowHeight: CGFloat = valueLabel === lapDistanceLabel ? 110 : 72
        container.snp.makeConstraints { make in
            make.height.equalTo(rowHeight)
        }
        return container
    }

    private func createDivider(isVertical: Bool = false) -> UIView {
        let divider = UIView()
        divider.backgroundColor = .clear
        if isVertical {
            divider.snp.makeConstraints { make in make.width.equalTo(10) }
        } else {
            divider.snp.makeConstraints { make in make.height.equalTo(10) }
        }
        return divider
    }

    // MARK: - Location

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

    private func setupLocationManager() {
        locationManager.delegate        = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter  = 5
    }

    // MARK: - Countdown

    private func beginCountdown() {
        phase               = .preparing
        countdown           = 1 // 1초로 단축
        countdownLabel.text = "1"

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
        countdownLabel.alpha     = 0
        countdownLabel.text      = "\(value)"
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: []) {
            self.countdownLabel.transform = .identity
            self.countdownLabel.alpha = 1
        }
    }

    private func countdownFinished() {
        UIView.animate(withDuration: 0.3) {
            self.countdownContainer.alpha = 0
            self.statsPanel.alpha         = 1
        } completion: { _ in
            self.countdownContainer.isHidden = true
            self.buttonContainer.isHidden    = false
        }
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
                self.showAlert(
                    title: "운동 시작 실패",
                    message: error?.localizedDescription ?? "건강 권한 또는 세션 상태를 확인해주세요."
                ) { [weak self] in
                    self?.dismiss(animated: true)
                }
                return
            }
            self.startWorkoutFlow(startDate: startDate)
        }
    }

    private func startWorkoutFlow(startDate: Date) {
        workoutStartDate = startDate
        startRunningLap()
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
        restOverlay.isHidden = true
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

    // MARK: - State Transitions

    private func startRunningLap() {
        phase           = .runningLap
        lapElapsed      = 0
        lapDistance_    = 0
        lapLocations    = []
        lapStartDate    = Date()
        recentLocations = []

        if !isWatchPrimary {
            locationManager.startUpdatingLocation()
            startTimer()
        }
        showRunningButtons()
        manualLapButton.isHidden = isWatchPrimary
        restOverlay.isHidden     = true

        triggerHaptic(.success)
    }

    private func startResting() {
        // record run lap
        recordLap(type: .run)

        phase         = .resting
        restRemaining = restDuration
        lapStartDate  = Date()

        locationManager.stopUpdatingLocation()
        manualLapButton.isHidden = true

        restOverlay.isHidden    = false
        restCountdownLabel.text = "\(Int(restRemaining))"

        triggerHaptic(.success)
    }

    private func restFinished() {
        // record rest lap
        recordLap(type: .rest)

        restOverlay.isHidden = true
        currentSet += 1

        if currentSet > totalSets {
            finishAndShowResult()
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
                self.elapsed += 1
                self.lapElapsed += 1
                self.updateUI()

            case .resting:
                self.elapsed += 1
                self.restRemaining -= 1
                // haptic at 3 seconds before
                if self.restRemaining <= 3 && self.restRemaining > 0 {
                    self.triggerHaptic(.warning)
                }
                if self.restRemaining <= 0 {
                    self.restFinished()
                } else {
                    self.restCountdownLabel.text = "\(Int(self.restRemaining))"
                }
                self.updateUI()

            default:
                break
            }
        }
    }

    // MARK: - Button Actions

    @objc private func pauseTapped() {
        if isWatchPrimary {
            guard WatchBridge.shared.sendWorkoutCommand(WorkoutStreamKey.commandPause) else {
                showAlert(title: "워치 연결 필요", message: "워치 연결을 확인해주세요.")
                return
            }
            return
        }
        guard case .runningLap = phase else {
            if case .resting = phase {
                phase = .paused(prior: .resting)
                timer?.invalidate()
                locationManager.stopUpdatingLocation()
                pausedOverlay.isHidden = false
                showPausedButtons()
            }
            return
        }
        phase = .paused(prior: .runningLap)
        timer?.invalidate()
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
            return
        }
        guard case .paused(let prior) = phase else { return }
        pausedOverlay.isHidden = true

        switch prior {
        case .runningLap:
            phase = .runningLap
            locationManager.startUpdatingLocation()
            HealthKitStore.shared.resumePhoneWorkout()
            startTimer()
            showRunningButtons()
            manualLapButton.isHidden = false
        case .resting:
            phase = .resting
            HealthKitStore.shared.resumePhoneWorkout()
            startTimer()
            showRunningButtons()
            manualLapButton.isHidden = true
        default:
            break
        }
    }

    @objc private func stopTapped() {
        if isWatchPrimary {
            guard WatchBridge.shared.sendWorkoutCommand(WorkoutStreamKey.commandStop) else {
                showAlert(title: "워치 연결 필요", message: "워치 연결을 확인해주세요.")
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

        // record current in-progress lap
        if case .paused(let prior) = phase {
            switch prior {
            case .runningLap: recordLap(type: .run)
            case .resting: recordLap(type: .rest)
            default: break
            }
        }
        isPresentingResult = true
        finishAndShowResult()
    }

    @objc private func manualLapTapped() {
        guard case .runningLap = phase else { return }
        startResting()
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
        manualLapButton.isHidden = true
    }

    // MARK: - Recording

    private func recordLap(type: IntervalLap.LapType) {
        let now = Date()
        let lapNumber = laps.count + 1
        let dist = type == .run ? lapDistance_ : 0
        let dur = type == .run ? lapElapsed : (restDuration - restRemaining)
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

    private func finishWorkout(showResult: Bool, completion: ((HKWorkout?) -> Void)? = nil) {
        if case .finished = phase {
            completion?(nil)
            return
        }

        phase = .finished
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()

        // 워치 프라이머리일 때 폰에서는 HealthKit 저장 안 함 (워치 HKLiveWorkoutBuilder가 저장)
        guard !isWatchPrimary else {
            if showResult {
                showResultScreen(workout: nil)
            }
            completion?(nil)
            return
        }

        let totalDist = laps.filter { $0.type == .run }.reduce(0) { $0 + $1.distance }
        let endDate = Date()
        let duration = endDate.timeIntervalSince(workoutStartDate ?? endDate)

        guard HealthKitStore.shared.shouldSaveWorkout(duration: duration, distance: totalDist) else {
            HealthKitStore.shared.discardActivePhoneWorkout { [weak self] _, _ in
                guard let self else { return }
                completion?(nil)
                if showResult {
                    self.showResultScreen(workout: nil)
                }
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

            let finishUI = {
                completion?(workout)
                if showResult {
                    self.showResultScreen(workout: workout)
                }
            }

            if success {
                if let error {
                    self.showAlert(title: "운동 저장 완료", message: "운동은 저장됐지만 경로 저장 중 일부 문제가 발생했습니다.\n\(error.localizedDescription)") {
                        finishUI()
                    }
                } else {
                    finishUI()
                }
            } else {
                self.showAlert(title: "운동 저장 실패", message: error?.localizedDescription ?? "운동을 저장하지 못했습니다.") {
                    finishUI()
                }
            }
        }
    }

    @objc private func stopFromMirror() {
        isPresentingResult = true
        finishAndShowResult()
    }

    @objc private func fallbackToPhone() {
        guard isWatchPrimary else { return }
        isWatchPrimary = false
        // 스냅샷 옵저버 제거
        if let obs = snapshotObserver {
            NotificationCenter.default.removeObserver(obs)
            snapshotObserver = nil
        }
        disconnectTimer?.invalidate()
        disconnectTimer = nil
        sourceBadge.isHidden = true

        setupLocationManager()
        locationManager.requestWhenInUseAuthorization()

        if case .preparing = phase {
            watchCountdownTimer?.invalidate()
            watchCountdownTimer = nil
            beginCountdown()
            return
        }

        // 카운트다운 중이면 countdownFinished()에서 폰 HK 세션 자동 시작
        guard case .runningLap = phase else { return }

        let settings = IntervalSettings(sets: totalSets, lapDistance: lapDistance, restDuration: restDuration)
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

    private func finishAndShowResult() {
        guard !hasShownResult else { return }
        finishWorkout(showResult: true)
    }

    private func showResultScreen(workout: HKWorkout?) {
        guard !hasShownResult else { return }
        hasShownResult = true
        let runLaps = laps.filter { $0.type == .run }
        let totalDist = runLaps.reduce(0) { $0 + $1.distance }
        let avgPace: TimeInterval? = totalDist > 10 ? elapsed / (totalDist / 1000) : nil

        // 인터벌에서는 세트별 페이스를 스플릿으로 표시
        let splits: [WorkoutResultDataModel.SplitData] = runLaps.enumerated().map { i, lap in
            let pace = lap.avgPace ?? (lap.duration / max(0.001, lap.distance / 1000))
            return WorkoutResultDataModel.SplitData(km: i + 1, pace: pace, distance: lap.distance)
        }

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
            resultVC.onDismiss = {
                self?.dismiss(animated: true)
            }
        }
    }

    // MARK: - Watch Snapshot Observer

    private func setupSnapshotObserver() {
        snapshotObserver = NotificationCenter.default.addObserver(
            forName: WatchBridge.workoutSnapshotNotification,
            object: nil, queue: .main
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
                self.sourceBadge.text = " 워치 연결 끊김 "
                self.sourceBadge.textColor = AppColor.UI.workoutStop
                self.sourceBadge.isHidden = false
            } else {
                self.sourceBadge.text = " Apple Watch에서 센서 측정 중 "
                self.sourceBadge.textColor = AppColor.UI.success
            }
        }
    }

    private func applySnapshot(_ snapshot: WorkoutDataSnapshot) {
        if case .finished = phase { return }
        elapsed = snapshot.elapsed

        // Phase sync
        let phaseStr = snapshot.phase
        switch phaseStr {
        case "preparing":
            let endsAt = snapshot.countdownEndsAt.map(Date.init(timeIntervalSince1970:))
            updateWatchPreparingCountdown(endsAt: endsAt, countdownValue: snapshot.countdownValue)
            return
        case "paused":
            watchCountdownTimer?.invalidate()
            watchCountdownTimer = nil
            if case .paused = phase {} else {
                phase = .paused(prior: .runningLap)
                pausedOverlay.isHidden = false
                showPausedButtons()
            }
        case "running":
            watchCountdownTimer?.invalidate()
            watchCountdownTimer = nil
            if snapshot.intervalPhase == "resting" {
                if case .resting = phase {} else {
                    phase = .resting
                    restOverlay.isHidden = false
                    manualLapButton.isHidden = true
                    showRunningButtons()
                }
            } else {
                if case .runningLap = phase {} else {
                    phase = .runningLap
                    restOverlay.isHidden = true
                    pausedOverlay.isHidden = true
                    showRunningButtons()
                    manualLapButton.isHidden = false
                }
            }
        case "finished":
            watchCountdownTimer?.invalidate()
            watchCountdownTimer = nil
            if case .finished = phase {} else {
                finishWorkout(showResult: false)
                finishAndShowResult()
                return
            }
        default:
            break
        }

        // Duration
        let h = Int(elapsed) / 3600
        let m = Int(elapsed) % 3600 / 60
        let s = Int(elapsed) % 60
        durationLabel.text = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)

        // Set
        if let cs = snapshot.currentSet, let ts = snapshot.totalSets {
            currentSet = cs
            setLabel.text = "\(cs) / \(ts)"
        }

        // Lap distance / rest
        if snapshot.intervalPhase == "resting", let rest = snapshot.restRemaining {
            restRemaining = rest
            lapDistanceLabel.text = "REST \(Int(rest))s"
            restCountdownLabel.text = "\(Int(rest))"
        } else if let ld = snapshot.lapDistanceCurrent {
            lapDistance_ = ld
            lapDistanceLabel.text = "\(Int(ld))m / \(Int(lapDistance))m"
        }

        // Pace
        watchAvgPace = snapshot.avgPace
        watchLapPace = snapshot.segmentPace ?? snapshot.currentPace
        watchAvgHeartRate = snapshot.avgHeartRate
        watchLapAvgHeartRate = snapshot.segmentAvgHeartRate ?? snapshot.heartRate
        avgPaceLabel.text = formatPace(watchAvgPace)
        currPaceLabel.text = formatPace(watchLapPace)
        avgHeartRateLabel.text = formatHeartRate(watchAvgHeartRate)
        currHeartRateLabel.text = formatHeartRate(watchLapAvgHeartRate)

        // Map
        if let lat = snapshot.currentLatitude, let lng = snapshot.currentLongitude {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            routeCoordinates.append(coord)
            updateMap(with: coord)
        }
    }

    // MARK: - UI Updates

    private func updateUI() {
        // Duration
        let h = Int(elapsed) / 3600
        let m = Int(elapsed) % 3600 / 60
        let s = Int(elapsed) % 60
        durationLabel.text = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)

        // Lap distance or rest countdown
        if case .resting = phase {
            lapDistanceLabel.text = "REST \(Int(restRemaining))s"
        } else {
            lapDistanceLabel.text = "\(Int(lapDistance_))m / \(Int(lapDistance))m"
        }

        // Set
        setLabel.text = "\(currentSet) / \(totalSets)"

        if isWatchPrimary {
            avgPaceLabel.text = formatPace(watchAvgPace)
            currPaceLabel.text = formatPace(watchLapPace)
            avgHeartRateLabel.text = formatHeartRate(watchAvgHeartRate)
            currHeartRateLabel.text = formatHeartRate(watchLapAvgHeartRate)
            return
        }

        // Pace
        let runDist = laps.filter { $0.type == .run }.reduce(0) { $0 + $1.distance } + lapDistance_
        let runTime = laps.filter { $0.type == .run }.reduce(0) { $0 + $1.duration } + lapElapsed
        if runDist > 10 {
            avgPaceLabel.text = formatPace(runTime / (runDist / 1000.0))
        } else {
            avgPaceLabel.text = "--'--\""
        }

        let metrics = HealthKitStore.shared.currentPhoneWorkoutMetrics
        avgHeartRateLabel.text = formatHeartRate(metrics.avgHeartRate)
        currHeartRateLabel.text = formatHeartRate(
            currentLapAverageHeartRate(from: metrics)
        )

        if case .resting = phase {
            currPaceLabel.text = formatPace(lastRunLapPace)
        } else {
            currPaceLabel.text = formatPace(calculateCurrentLapPace())
        }
    }

    private func calculateCurrentLapPace() -> TimeInterval? {
        guard lapDistance_ > 10, lapElapsed > 0 else { return nil }
        return lapElapsed / (lapDistance_ / 1000.0)
    }

    private func currentLapAverageHeartRate(from metrics: HealthKitStore.PhoneWorkoutMetrics) -> Double? {
        if case .resting = phase {
            return lastRunLapAvgHeartRate
        }
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

    // MARK: - GPS → Lap auto-complete

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        allLocations.append(loc)
        routeCoordinates.append(loc.coordinate)

        // Lap distance tracking
        if let prev = lapLocations.last {
            let delta = loc.distance(from: prev)
            lapDistance_ += delta
        }
        lapLocations.append(loc)

        recentLocations.append(loc)
        if recentLocations.count > 8 { recentLocations.removeFirst() }

        updateMap(with: loc.coordinate)
        updateUI()

        // Auto-complete lap by distance
        if case .runningLap = phase, lapDistance_ >= lapDistance {
            if currentSet >= totalSets {
                // last set — finish after recording
                recordLap(type: .run)
                finishAndShowResult()
            } else {
                startResting()
            }
        }
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

        mapView.removeOverlays(mapView.overlays)
        if routeCoordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
            mapView.addOverlay(polyline)
        }

        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        mapView.addAnnotation(annotation)
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = AppColor.UI.workoutRoute
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
        view?.markerTintColor = AppColor.UI.workoutRoute
        view?.glyphText = ""
        return view
    }

    // MARK: - Haptic

    private func triggerHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
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

struct IntervalRunView: UIViewControllerRepresentable {
    let sets: Int
    let lapDistance: Double
    let restDuration: TimeInterval
    var isIndoor: Bool = false
    var isWatchPrimary: Bool = false

    func makeUIViewController(context: Context) -> IntervalRunViewController {
        IntervalRunViewController(
            sets: sets,
            lapDistance: lapDistance,
            restDuration: restDuration,
            isIndoor: isIndoor,
            isWatchPrimary: isWatchPrimary
        )
    }

    func updateUIViewController(_ uiViewController: IntervalRunViewController, context: Context) {}
}

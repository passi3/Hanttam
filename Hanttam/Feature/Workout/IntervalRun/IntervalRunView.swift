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
    private let isWatchPrimary: Bool

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

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupLocationManager()
        beginCountdown()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if case .finished = phase {} else {
            finishWorkout()
        }
    }

    // MARK: - Setup UI

    private func setupUI() {
        view.backgroundColor = AppColor.UI.workoutBg

        // MapView
        mapView.delegate = self
        mapView.isUserInteractionEnabled = false
        let config = MKStandardMapConfiguration()
        config.emphasisStyle = .muted
        config.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = config
        view.addSubview(mapView)
        view.addSubview(sourceBadge)

        // Stats Panel
        statsPanel.axis = .vertical
        statsPanel.spacing = 0
        statsPanel.backgroundColor = AppColor.UI.workoutBg
        view.addSubview(statsPanel)

        // Stats Rows
        statsPanel.addArrangedSubview(createStatRow(label: "DURATION", valueLabel: durationLabel))
        statsPanel.addArrangedSubview(createDivider())
        statsPanel.addArrangedSubview(createStatRow(label: "LAP DISTANCE", valueLabel: lapDistanceLabel))
        statsPanel.addArrangedSubview(createDivider())

        let paceStack = UIStackView()
        paceStack.axis = .horizontal
        paceStack.distribution = .fillEqually
        paceStack.addArrangedSubview(createStatRow(label: "Avg. PACE", valueLabel: avgPaceLabel))
        let d1 = createDivider(isVertical: true)
        paceStack.addSubview(d1)
        paceStack.addArrangedSubview(createStatRow(label: "Curr. PACE", valueLabel: currPaceLabel))
        statsPanel.addArrangedSubview(paceStack)
        statsPanel.addArrangedSubview(createDivider())

        statsPanel.addArrangedSubview(createStatRow(label: "SET", valueLabel: setLabel))
        statsPanel.addArrangedSubview(createDivider())

        // Button Container
        buttonContainer.backgroundColor = AppColor.UI.workoutBg
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
        countdownContainer.backgroundColor = AppColor.UI.workoutBg
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
        sourceBadge.textColor = AppColor.UI.success
        sourceBadge.backgroundColor = AppColor.UI.cardBackground.withAlphaComponent(0.92)
        sourceBadge.layer.cornerRadius = 12
        sourceBadge.layer.masksToBounds = true
        sourceBadge.textAlignment = .center
        sourceBadge.text = " Apple Watch에서 센서 측정 중 "
        sourceBadge.isHidden = !isWatchPrimary

        // Layout
        mapView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(statsPanel.snp.top)
        }
        sourceBadge.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(10)
            make.centerX.equalToSuperview()
        }
        statsPanel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(buttonContainer.snp.top)
        }
        buttonContainer.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
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
        setLabel.text = "1 / \(totalSets)"

        statsPanel.alpha = 0.3
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
        let container             = UIView()
        container.backgroundColor = AppColor.UI.workoutBg

        let lLabel           = UILabel()
        lLabel.text          = label
        lLabel.font          = AppFont.UI.captionMD
        lLabel.textColor     = AppColor.UI.textSecondary
        lLabel.textAlignment = .center

        valueLabel.font          = AppFont.UI.metricBody
        valueLabel.textColor     = AppColor.UI.textPrimary
        valueLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [lLabel, valueLabel])
        stack.axis    = .vertical
        stack.spacing = 3
        container.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.bottom.equalToSuperview().offset(-14)
            make.centerX.equalToSuperview()
        }
        return container
    }

    private func createDivider(isVertical: Bool = false) -> UIView {
        let divider             = UIView()
        divider.backgroundColor = AppColor.UI.separator
        if !isVertical {
            divider.snp.makeConstraints { make in make.height.equalTo(0.5) }
        }
        return divider
    }

    // MARK: - Location

    private func setupLocationManager() {
        locationManager.delegate        = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter  = 5
    }

    // MARK: - Countdown

    private func beginCountdown() {
        phase               = .preparing
        countdown           = 3
        countdownLabel.text = "3"

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
        startRunningLap()
    }

    // MARK: - State Transitions

    private func startRunningLap() {
        phase           = .runningLap
        lapElapsed      = 0
        lapDistance_    = 0
        lapLocations    = []
        lapStartDate    = Date()
        recentLocations = []

        locationManager.startUpdatingLocation()
        startTimer()
        showRunningButtons()
        manualLapButton.isHidden = false
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
        pausedOverlay.isHidden = false
        showPausedButtons()
    }

    @objc private func resumeTapped() {
        guard case .paused(let prior) = phase else { return }
        pausedOverlay.isHidden = true

        switch prior {
        case .runningLap:
            phase = .runningLap
            locationManager.startUpdatingLocation()
            startTimer()
            showRunningButtons()
            manualLapButton.isHidden = false
        case .resting:
            phase = .resting
            startTimer()
            showRunningButtons()
            manualLapButton.isHidden = true
        default:
            break
        }
    }

    @objc private func stopTapped() {
        // record current in-progress lap
        if case .paused(let prior) = phase {
            switch prior {
            case .runningLap: recordLap(type: .run)
            case .resting: recordLap(type: .rest)
            default: break
            }
        }
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
    }

    private func finishWorkout() {
        phase = .finished
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()

        let totalDist = laps.filter { $0.type == .run }.reduce(0) { $0 + $1.distance }
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-elapsed)
        let settings = IntervalSettings(sets: totalSets, lapDistance: lapDistance, restDuration: restDuration)

        HealthKitStore.shared.saveIntervalWorkout(
            start: startDate,
            end: endDate,
            distance: totalDist,
            calories: nil,
            laps: laps,
            settings: settings,
            routeLocations: allLocations,
            isIndoor: isIndoor
        ) { success, error in
            if !success {
                print("[Interval] HealthKit 저장 실패: \(error?.localizedDescription ?? "")")
            }
        }
    }

    private func finishAndShowResult() {
        finishWorkout()

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
        let startDate = endDate.addingTimeInterval(-elapsed)
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
            isIndoor: isIndoor,
            alreadySaved: true
        )
        let resultVC = WorkoutResultViewController(data: resultData)
        resultVC.modalPresentationStyle = .fullScreen
        present(resultVC, animated: true) { [weak self] in
            resultVC.onDismiss = {
                self?.dismiss(animated: true)
            }
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

        // Pace
        let runDist = laps.filter { $0.type == .run }.reduce(0) { $0 + $1.distance } + lapDistance_
        let runTime = laps.filter { $0.type == .run }.reduce(0) { $0 + $1.duration } + lapElapsed
        if runDist > 10 {
            avgPaceLabel.text = formatPace(runTime / (runDist / 1000.0))
        } else {
            avgPaceLabel.text = "--'--\""
        }

        if let cp = calculateCurrentPace() {
            currPaceLabel.text = formatPace(cp)
        } else {
            currPaceLabel.text = "--'--\""
        }
    }

    private func calculateCurrentPace() -> TimeInterval? {
        guard recentLocations.count >= 2 else { return nil }
        var dist: CLLocationDistance = 0
        for i in 0..<recentLocations.count - 1 {
            dist += recentLocations[i + 1].distance(from: recentLocations[i])
        }
        guard dist > 5 else { return nil }
        let time = recentLocations.last!.timestamp.timeIntervalSince(recentLocations.first!.timestamp)
        return time / (dist / 1000.0)
    }

    private func formatPace(_ secPerKm: TimeInterval) -> String {
        guard secPerKm.isFinite, secPerKm > 0, secPerKm < 3600 else { return "--'--\"" }
        return String(format: "%d'%02d\"", Int(secPerKm) / 60, Int(secPerKm) % 60)
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
        let camera = MKMapCamera(lookingAtCenter: coordinate, fromDistance: 300, pitch: 0, heading: 0)
        mapView.setCamera(camera, animated: true)

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

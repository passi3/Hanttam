//
//  FreeRunViewController.swift
//  Hanttam
//
//  Created by passi on 3/31/26.
//

import UIKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif
import CoreLocation
import MapKit
import SnapKit

final class FreeRunViewController: HTViewController, CLLocationManagerDelegate, MKMapViewDelegate {
    private let isIndoor: Bool
    private let isWatchPrimary: Bool
    
    // MARK: - Properties
    private let locationManager = CLLocationManager()
    private var allLocations    : [CLLocation] = []
    private var recentLocations : [CLLocation] = []
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    
    private var elapsed: TimeInterval = 0
    private var timer  : Timer?
#if canImport(ActivityKit)
    private var liveActivity: Activity<WorkoutAttributes>?
#endif
    private var phase: WorkoutPhase = .preparing
    private var countdown: Int = 3
    
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
        
        setupLocationManager()
        startLiveActivity()
        beginCountdown()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stopFromMirror),
                                               name: WatchBridge.workoutStoppedNotification,
                                               object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if phase != .finished {
            finishWorkout()
        }
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
        
        paceStack.addArrangedSubview(createStatRow(label: "Avg. PACE", valueLabel: avgPaceLabel))
        paceStack.addSubview(d1)
        paceStack.addArrangedSubview(createStatRow(label: "Curr. PACE", valueLabel: currPaceLabel))
        statsPanel.addArrangedSubview(paceStack)
        statsPanel.addArrangedSubview(createDivider())
        
        hrStack.addArrangedSubview(createStatRow(label: "Avg. HEART RATE", valueLabel: avgHeartRateLabel))
        hrStack.addSubview(d2)
        hrStack.addArrangedSubview(createStatRow(label: "Curr. HEART RATE", valueLabel: currHeartRateLabel))
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
            make.bottom.equalTo(statsPanel.snp.top)
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
        view.backgroundColor = AppColor.UI.workoutBg
        
        mapView.delegate                 = self
        mapView.isUserInteractionEnabled = false
        // mapView.showsUserLocation        = true
        mapView.mapType                  = .mutedStandard
        let config                   = MKStandardMapConfiguration()
        config.emphasisStyle         = .muted
        config.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration   = config
        
        statsPanel.axis            = .vertical
        statsPanel.spacing         = 0
        statsPanel.backgroundColor = AppColor.UI.workoutBg
        statsPanel.alpha           = 0.3
        
        paceStack.axis         = .horizontal
        paceStack.distribution = .fillEqually
        
        hrStack.axis         = .horizontal
        hrStack.distribution = .fillEqually
        
        d1.backgroundColor = AppColor.UI.separator
        d2.backgroundColor = AppColor.UI.separator
        
        // Button Container
        buttonContainer.backgroundColor = AppColor.UI.workoutBg
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
        countdownContainer.backgroundColor = AppColor.UI.workoutBg
        
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
        
        sourceBadge.font                = AppFont.UI.labelSM
        sourceBadge.textColor           = AppColor.UI.success
        sourceBadge.backgroundColor     = AppColor.UI.cardBackground.withAlphaComponent(0.92)
        sourceBadge.layer.cornerRadius  = 12
        sourceBadge.layer.masksToBounds = true
        sourceBadge.textAlignment       = .center
        sourceBadge.text                = " Apple Watch에서 센서 측정 중 "
        sourceBadge.isHidden            = !isWatchPrimary
        
        // Default values
        durationLabel.text      = "00:00"
        distanceLabel.text      = "0.00KM"
        avgPaceLabel.text       = "--'--\""
        currPaceLabel.text      = "--'--\""
        avgHeartRateLabel.text  = "--"
        currHeartRateLabel.text = "--"
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
        
        let stack     = UIStackView(arrangedSubviews: [lLabel, valueLabel])
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
        let divider = UIView()
        divider.backgroundColor = AppColor.UI.separator
        if !isVertical {
            divider.snp.makeConstraints { make in
                make.height.equalTo(0.5)
            }
        }
        return divider
    }
    
    // MARK: - Phase Management

    private func beginCountdown() {
        phase = .preparing
        countdown = 3
        countdownLabel.text = "\(countdown)"
        updateLiveActivity()

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.countdown -= 1
            if self.countdown > 0 {
                self.animateCountdown(self.countdown)
                self.updateLiveActivity()
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
        startRunning()
    }

    private func startRunning() {
        phase = .running
        locationManager.startUpdatingLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.phase == .running else { return }
            self.elapsed += 1
            self.updateUI()
            self.updateLiveActivity()
        }
        updateLiveActivity()
        showRunningButtons()
    }

    @objc private func pauseTapped() {
        phase = .paused
        locationManager.stopUpdatingLocation()
        pausedOverlay.isHidden = false
        showPausedButtons()
        updateLiveActivity()
    }

    @objc private func resumeTapped() {
        phase = .running
        locationManager.startUpdatingLocation()
        pausedOverlay.isHidden = true
        showRunningButtons()
        updateLiveActivity()
    }

    @objc private func stopTapped() {
        WatchBridge.shared.sendWorkoutStopped()
        finishWorkout()
        showResult()
    }

    @objc private func stopFromMirror() {
        finishWorkout()
        showResult()
    }

    private func finishWorkout() {
        phase = .finished
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        stopLiveActivity()
    }

    private func showResult() {
        let totalDist = calculateTotalDistance()
        let avgPace: TimeInterval? = totalDist > 10 ? elapsed / (totalDist / 1000) : nil
        let splits = buildSplits()
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
            isIndoor: isIndoor
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

    private func updateUI() {
        // Duration
        let h = Int(elapsed) / 3600
        let m = Int(elapsed) % 3600 / 60
        let s = Int(elapsed) % 60
        durationLabel.text = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)

        // Distance
        let totalDist = calculateTotalDistance()
        distanceLabel.text = String(format: "%.2fKM", totalDist / 1000.0)

        // Avg Pace
        if totalDist > 10 {
            avgPaceLabel.text = formatPace(elapsed / (totalDist / 1000.0))
        } else {
            avgPaceLabel.text = "--'--\""
        }

        // Curr Pace
        if let currentPace = calculateCurrentPace() {
            currPaceLabel.text = formatPace(currentPace)
        } else {
            currPaceLabel.text = "--'--\""
        }
    }

    private func calculateTotalDistance() -> CLLocationDistance {
        guard allLocations.count >= 2 else { return 0 }
        var dist: CLLocationDistance = 0
        for i in 0..<allLocations.count - 1 {
            dist += allLocations[i+1].distance(from: allLocations[i])
        }
        return dist
    }

    private func calculateCurrentPace() -> TimeInterval? {
        guard recentLocations.count >= 2 else { return nil }
        var dist: CLLocationDistance = 0
        for i in 0..<recentLocations.count - 1 {
            dist += recentLocations[i+1].distance(from: recentLocations[i])
        }
        guard dist > 5 else { return nil }
        let time = recentLocations.last!.timestamp.timeIntervalSince(recentLocations.first!.timestamp)
        return time / (dist / 1000.0)
    }

    private func formatPace(_ secPerKm: TimeInterval) -> String {
        guard secPerKm.isFinite, secPerKm > 0, secPerKm < 3600 else { return "--'--\"" }
        return String(format: "%d'%02d\"", Int(secPerKm) / 60, Int(secPerKm) % 60)
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        allLocations.append(loc)
        routeCoordinates.append(loc.coordinate)

        recentLocations.append(loc)
        if recentLocations.count > 8 { recentLocations.removeFirst() }

        updateMap(with: loc.coordinate)
        updateUI()
    }

    private func updateMap(with coordinate: CLLocationCoordinate2D) {
        let camera = MKMapCamera(lookingAtCenter: coordinate, fromDistance: 300, pitch: 0, heading: 0)
        mapView.setCamera(camera, animated: true)

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

    // MARK: - Live Activity

    #if canImport(ActivityKit)
    private func startLiveActivity() {
        let authInfo = ActivityAuthorizationInfo()
        print("[LiveActivity] areActivitiesEnabled=\(authInfo.areActivitiesEnabled)")
        guard authInfo.areActivitiesEnabled else { return }

        // 기존 라이브 액티비티 모두 종료
        for existing in Activity<WorkoutAttributes>.activities {
            Task {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
        }

        let state = WorkoutAttributes.ContentState(
            phase: .preparing,
            elapsed: 0,
            distance: 0,
            avgPace: nil,
            currentPace: nil,
            countdown: countdown
        )
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            liveActivity = try Activity.request(
                attributes: WorkoutAttributes(),
                content: content,
                pushType: nil
            )
            print("[LiveActivity] started id=\(liveActivity?.id ?? "nil")")
        } catch {
            print("[LiveActivity] failed: \(error)")
        }
    }

    private func updateLiveActivity() {
        guard let activity = liveActivity else { return }
        let totalDist = calculateTotalDistance()
        let avgPace: Double? = totalDist > 10 ? elapsed / (totalDist / 1000) : nil
        let state = WorkoutAttributes.ContentState(
            phase: phase,
            elapsed: elapsed,
            distance: totalDist,
            avgPace: avgPace,
            currentPace: phase == .running ? calculateCurrentPace() : nil,
            countdown: phase == .preparing ? countdown : nil
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func stopLiveActivity() {
        guard let activity = liveActivity else { return }
        let totalDist = calculateTotalDistance()
        let avgPace: Double? = totalDist > 10 ? elapsed / (totalDist / 1000) : nil
        let finalState = WorkoutAttributes.ContentState(
            phase: .finished,
            elapsed: elapsed,
            distance: totalDist,
            avgPace: avgPace,
            currentPace: nil,
            countdown: nil
        )
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + 300)
            )
        }
        liveActivity = nil
    }
    #else
    private func startLiveActivity() {}
    private func updateLiveActivity() {}
    private func stopLiveActivity() {}
    #endif
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

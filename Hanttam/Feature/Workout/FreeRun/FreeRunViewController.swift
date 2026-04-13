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
import RxSwift
import RxCocoa
internal import HealthKit

final class FreeRunViewController: HTViewController, MKMapViewDelegate {

    // MARK: - ViewModel
    private let viewModel: FreeRunViewModel
    private let disposeBag = DisposeBag()

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
    private let sourceBadge   = UILabel()

    // MARK: - Layout Helpers
    private let paceStack = UIStackView()
    private let hrStack   = UIStackView()
    private let d1        = UIView()
    private let d2        = UIView()

    private var isPresentingResult = false
    private var isFirstMapUpdate   = true

    // MARK: - Init
    init(isIndoor: Bool = false, isWatchPrimary: Bool = false) {
        self.viewModel = FreeRunViewModel(isIndoor: isIndoor, isWatchPrimary: isWatchPrimary)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        bindViewModel()
        viewModel.viewDidLoad()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !isPresentingResult {
            viewModel.viewWillDisappear()
        }
    }

    // MARK: - Hierarchy / Layout / Style
    override func configHierarchy() {
        view.addSubview(mapView)
        view.addSubview(statsPanel)
        view.addSubview(buttonContainer)
        view.addSubview(countdownContainer)
        view.addSubview(pausedOverlay)
        view.addSubview(sourceBadge)

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

        buttonContainer.addSubview(pauseButton)
        buttonContainer.addSubview(resumeButton)
        buttonContainer.addSubview(stopButton)

        countdownContainer.addSubview(countdownLabel)
        countdownContainer.addSubview(countdownSubLabel)

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
        mapView.mapType                  = .mutedStandard
        let config                       = MKStandardMapConfiguration()
        config.emphasisStyle             = .muted
        config.pointOfInterestFilter     = .excludingAll
        mapView.preferredConfiguration   = config
        mapView.layer.cornerRadius       = 30
        mapView.layer.masksToBounds      = true

        statsPanel.axis               = .vertical
        statsPanel.spacing            = 0
        statsPanel.backgroundColor    = AppColor.UI.cardBackground.withAlphaComponent(0.96)
        statsPanel.layer.cornerRadius = 28
        statsPanel.layer.borderWidth  = 1
        statsPanel.layer.borderColor  = AppColor.UI.border.withAlphaComponent(0.7).cgColor
        statsPanel.layer.masksToBounds = true
        statsPanel.alpha              = 1

        paceStack.axis         = .horizontal
        paceStack.distribution = .fillEqually

        hrStack.axis         = .horizontal
        hrStack.distribution = .fillEqually

        d1.backgroundColor = AppColor.UI.separator
        d2.backgroundColor = AppColor.UI.separator

        buttonContainer.backgroundColor = .clear
        buttonContainer.isHidden        = true

        pauseButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)), for: .normal)
        pauseButton.tintColor          = AppColor.UI.textInverse
        pauseButton.backgroundColor    = AppColor.UI.workoutPause
        pauseButton.layer.cornerRadius = 38

        resumeButton.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)), for: .normal)
        resumeButton.tintColor          = AppColor.UI.textInverse
        resumeButton.backgroundColor    = AppColor.UI.workoutResume
        resumeButton.layer.cornerRadius = 38
        resumeButton.isHidden           = true

        stopButton.setImage(UIImage(systemName: "stop.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)), for: .normal)
        stopButton.tintColor          = AppColor.UI.textInverse
        stopButton.backgroundColor    = AppColor.UI.workoutStop
        stopButton.layer.cornerRadius = 38
        stopButton.isHidden           = true

        countdownContainer.backgroundColor = AppColor.UI.backgroundGrouped

        countdownLabel.font          = AppFont.UI.metricDisplayXL
        countdownLabel.textColor     = AppColor.UI.workoutPause
        countdownLabel.textAlignment = .center
        countdownLabel.text          = "1"

        countdownSubLabel.font          = AppFont.UI.titleSM
        countdownSubLabel.textColor     = AppColor.UI.textSecondary
        countdownSubLabel.textAlignment = .center
        countdownSubLabel.text          = "준비하세요"

        pausedOverlay.backgroundColor = AppColor.UI.overlay
        pausedOverlay.isHidden        = true

        pausedLabel.text          = "일시정지"
        pausedLabel.font          = AppFont.UI.headlineLG
        pausedLabel.textColor     = AppColor.UI.textInverse
        pausedLabel.textAlignment = .center

        durationLabel.text      = "00:00"
        distanceLabel.text      = "0.00KM"
        avgPaceLabel.text       = "--'--\""
        currPaceLabel.text      = "--'--\""
        avgHeartRateLabel.text  = "--"
        currHeartRateLabel.text = "--"

        sourceBadge.textColor           = AppColor.UI.textSecondary
        sourceBadge.backgroundColor     = AppColor.UI.backgroundTertiary.withAlphaComponent(0.95)
        sourceBadge.layer.cornerRadius  = 14
        sourceBadge.layer.borderWidth   = 1
        sourceBadge.layer.borderColor   = AppColor.UI.border.withAlphaComponent(0.8).cgColor
        sourceBadge.layer.masksToBounds = true
        sourceBadge.isHidden            = true
    }

    // MARK: - ViewModel Binding
    private func bindViewModel() {
        let input = FreeRunViewModel.Input(
            pauseTapped : pauseButton.rx.tap.asObservable(),
            resumeTapped: resumeButton.rx.tap.asObservable(),
            stopTapped  : stopButton.rx.tap.asObservable()
        )
        let output = viewModel.transform(input: input)

        output.phase
            .drive(onNext: { [weak self] phase in self?.applyPhase(phase) })
            .disposed(by: disposeBag)

        output.countdownText
            .drive(onNext: { [weak self] text in self?.animateCountdown(text) })
            .disposed(by: disposeBag)

        output.durationText
            .drive(durationLabel.rx.text)
            .disposed(by: disposeBag)

        output.distanceText
            .drive(distanceLabel.rx.text)
            .disposed(by: disposeBag)

        output.avgPaceText
            .drive(avgPaceLabel.rx.text)
            .disposed(by: disposeBag)

        output.segmentPaceText
            .drive(currPaceLabel.rx.text)
            .disposed(by: disposeBag)

        output.avgHRText
            .drive(avgHeartRateLabel.rx.text)
            .disposed(by: disposeBag)

        output.segmentHRText
            .drive(currHeartRateLabel.rx.text)
            .disposed(by: disposeBag)

        output.routeUpdate
            .drive(onNext: { [weak self] update in self?.applyRouteUpdate(update) })
            .disposed(by: disposeBag)

        output.sourceBadgeState
            .drive(onNext: { [weak self] state in self?.applySourceBadge(state) })
            .disposed(by: disposeBag)

        output.showResult
            .drive(onNext: { [weak self] data in self?.showResultScreen(data: data) })
            .disposed(by: disposeBag)

        output.showAlert
            .drive(onNext: { [weak self] info in self?.showAlertInfo(info) })
            .disposed(by: disposeBag)
    }

    // MARK: - Phase UI
    private func applyPhase(_ phase: WorkoutPhase) {
        switch phase {
        case .preparing:
            countdownContainer.alpha  = 1
            countdownContainer.isHidden = false
            buttonContainer.isHidden  = true
            pausedOverlay.isHidden    = true
        case .running:
            hideCountdownIfNeeded()
            buttonContainer.isHidden = false
            pausedOverlay.isHidden   = true
            showRunningButtons()
        case .paused:
            hideCountdownIfNeeded()
            buttonContainer.isHidden = false
            pausedOverlay.isHidden   = false
            showPausedButtons()
        case .finished:
            break
        }
    }

    private func hideCountdownIfNeeded() {
        guard !countdownContainer.isHidden else { return }
        UIView.animate(withDuration: 0.3) {
            self.countdownContainer.alpha = 0
            self.statsPanel.alpha = 1
        } completion: { _ in
            self.countdownContainer.isHidden = true
            self.buttonContainer.isHidden = false
        }
    }

    private func animateCountdown(_ text: String) {
        guard countdownLabel.text != text else { return }
        countdownLabel.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        countdownLabel.alpha = 0
        countdownLabel.text = text
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: []) {
            self.countdownLabel.transform = .identity
            self.countdownLabel.alpha = 1
        }
    }

    private func showRunningButtons() {
        pauseButton.isHidden  = false
        resumeButton.isHidden = true
        stopButton.isHidden   = true
    }

    private func showPausedButtons() {
        pauseButton.isHidden  = true
        resumeButton.isHidden = false
        stopButton.isHidden   = false
    }

    // MARK: - Map
    private func applyRouteUpdate(_ update: FreeRunViewModel.RouteUpdate) {
        if update.isFirstUpdate {
            let region = MKCoordinateRegion(center: update.coordinate, latitudinalMeters: 300, longitudinalMeters: 300)
            mapView.setRegion(region, animated: false)
        } else {
            let camera = MKMapCamera(lookingAtCenter: update.coordinate, fromDistance: 300, pitch: 0, heading: 0)
            mapView.setCamera(camera, animated: true)
        }

        mapView.removeOverlays(mapView.overlays)
        if update.allCoordinates.count >= 2 {
            var coords = update.allCoordinates
            let polyline = MKPolyline(coordinates: &coords, count: coords.count)
            mapView.addOverlay(polyline)
        }

        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = update.coordinate
        mapView.addAnnotation(annotation)
    }

    // MARK: - Source Badge
    private func applySourceBadge(_ state: FreeRunViewModel.SourceBadgeState) {
        switch state {
        case .hidden:
            sourceBadge.isHidden = true
        case .connected:
            sourceBadge.text      = " Apple Watch에서 센서 측정 중 "
            sourceBadge.textColor = AppColor.UI.success
            sourceBadge.isHidden  = false
        case .disconnected:
            sourceBadge.text      = " 워치 연결 끊김 "
            sourceBadge.textColor = AppColor.UI.workoutStop
            sourceBadge.isHidden  = false
        }
    }

    // MARK: - Result
    private func showResultScreen(data: WorkoutResultDataModel) {
        isPresentingResult = true
        let resultVC = WorkoutResultViewController(data: data)
        resultVC.modalPresentationStyle = .fullScreen
        present(resultVC, animated: true) { [weak self] in
            resultVC.onDismiss = {
                self?.dismiss(animated: true)
            }
        }
    }

    // MARK: - Alert
    private func showAlertInfo(_ info: FreeRunViewModel.AlertInfo) {
        let alert = UIAlertController(title: info.title, message: info.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in
            info.onConfirm?()
        })
        present(alert, animated: true)
    }

    // MARK: - Factory
    private func createStatRow(label: String, valueLabel: UILabel) -> UIView {
        let container = UIView()
        container.backgroundColor    = AppColor.UI.backgroundSecondary
        container.layer.cornerRadius = 18
        container.layer.masksToBounds = true

        let lLabel           = UILabel()
        lLabel.text          = label
        lLabel.font          = AppFont.UI.labelMD
        lLabel.textColor     = AppColor.UI.textSecondary
        lLabel.textAlignment = .left

        if valueLabel === distanceLabel {
            valueLabel.font      = UIFont.systemFont(ofSize: 38, weight: .black)
            valueLabel.textColor = RunningLevelManager.shared.accentUIColor
        } else if valueLabel === currPaceLabel {
            valueLabel.font      = AppFont.UI.metricTitle
            valueLabel.textColor = AppColor.UI.textPrimary
        } else {
            valueLabel.font      = AppFont.UI.metricBody
            valueLabel.textColor = AppColor.UI.textPrimary
        }
        valueLabel.textAlignment            = .left
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor       = 0.7

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
            divider.snp.makeConstraints { make in make.width.equalTo(10) }
        } else {
            divider.snp.makeConstraints { make in make.height.equalTo(10) }
        }
        return divider
    }

    // MARK: - MKMapViewDelegate
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(AppColor.workoutRoute)
            renderer.lineWidth   = 6
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
        view?.glyphText       = ""
        return view
    }
}

// MARK: - SwiftUI Wrapper
struct FreeRunView: UIViewControllerRepresentable {
    var isIndoor      : Bool = false
    var isWatchPrimary: Bool = false

    func makeUIViewController(context: Context) -> FreeRunViewController {
        FreeRunViewController(isIndoor: isIndoor, isWatchPrimary: isWatchPrimary)
    }

    func updateUIViewController(_ uiViewController: FreeRunViewController, context: Context) {}
}

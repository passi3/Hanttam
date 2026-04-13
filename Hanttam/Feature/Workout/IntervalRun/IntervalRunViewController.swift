//
//  IntervalRunViewController.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import UIKit
import MapKit
import CoreLocation
import SwiftUI
import SnapKit
import RxSwift
import RxCocoa
internal import HealthKit

// MARK: - ViewController

class IntervalRunViewController: UIViewController {

    // MARK: - ViewModel
    private let viewModel  : IntervalRunViewModel
    private let mapDelegate = WorkoutMapDelegate()
    private let disposeBag = DisposeBag()

    // MARK: - Init
    init(sets: Int, lapDistance: Double, restDuration: TimeInterval, isIndoor: Bool = false, isWatchPrimary: Bool = false) {
        self.viewModel = IntervalRunViewModel(
            sets: sets,
            lapDistance: lapDistance,
            restDuration: restDuration,
            isIndoor: isIndoor,
            isWatchPrimary: isWatchPrimary
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI Components
    private let mapView         = MKMapView()
    private let statsPanel      = UIStackView()
    private let buttonContainer = UIView()

    private let durationLabel      = UILabel()
    private let lapDistanceLabel   = UILabel()
    private let avgPaceLabel       = UILabel()
    private let currPaceLabel      = UILabel()
    private let avgHeartRateLabel  = UILabel()
    private let currHeartRateLabel = UILabel()
    private let setLabel           = UILabel()

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

    private var isPresentingResult = false

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        viewModel.viewDidLoad()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !isPresentingResult {
            viewModel.viewWillDisappear()
        }
    }

    // MARK: - ViewModel Binding
    private func bindViewModel() {
        let input = IntervalRunViewModel.Input(
            pauseTapped    : pauseButton.rx.tap.asObservable(),
            resumeTapped   : resumeButton.rx.tap.asObservable(),
            stopTapped     : stopButton.rx.tap.asObservable(),
            manualLapTapped: manualLapButton.rx.tap.asObservable()
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

        output.lapDistanceText
            .drive(lapDistanceLabel.rx.text)
            .disposed(by: disposeBag)

        output.avgPaceText
            .drive(avgPaceLabel.rx.text)
            .disposed(by: disposeBag)

        output.lapPaceText
            .drive(currPaceLabel.rx.text)
            .disposed(by: disposeBag)

        output.avgHRText
            .drive(avgHeartRateLabel.rx.text)
            .disposed(by: disposeBag)

        output.lapHRText
            .drive(currHeartRateLabel.rx.text)
            .disposed(by: disposeBag)

        output.setCountText
            .drive(setLabel.rx.text)
            .disposed(by: disposeBag)

        output.restCountdown
            .drive(restCountdownLabel.rx.text)
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

        output.hapticFeedback
            .drive(onNext: { type in
                UINotificationFeedbackGenerator().notificationOccurred(type)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Phase UI
    private func applyPhase(_ phase: IntervalRunViewModel.Phase) {
        switch phase {
        case .preparing:
            countdownContainer.alpha  = 1
            countdownContainer.isHidden = false
            buttonContainer.isHidden  = true
            pausedOverlay.isHidden    = true
            restOverlay.isHidden      = true

        case .runningLap:
            hideCountdownIfNeeded()
            buttonContainer.isHidden  = false
            restOverlay.isHidden      = true
            pausedOverlay.isHidden    = true
            showRunningButtons()
            manualLapButton.isHidden  = false

        case .resting:
            hideCountdownIfNeeded()
            buttonContainer.isHidden  = false
            restOverlay.isHidden      = false
            pausedOverlay.isHidden    = true
            showRunningButtons()
            manualLapButton.isHidden  = true

        case .paused:
            pausedOverlay.isHidden    = false
            showPausedButtons()
            manualLapButton.isHidden  = true

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
        countdownLabel.alpha     = 0
        countdownLabel.text      = text
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: []) {
            self.countdownLabel.transform = .identity
            self.countdownLabel.alpha = 1
        }
    }

    private func showRunningButtons() {
        pauseButton.isHidden   = false
        resumeButton.isHidden  = true
        stopButton.isHidden    = true
    }

    private func showPausedButtons() {
        pauseButton.isHidden   = true
        resumeButton.isHidden  = false
        stopButton.isHidden    = false
        manualLapButton.isHidden = true
    }

    // MARK: - Map
    private func applyRouteUpdate(_ update: WorkoutRouteUpdate) {
        mapDelegate.apply(update, to: mapView)
    }

    // MARK: - Source Badge
    private func applySourceBadge(_ state: IntervalRunViewModel.SourceBadgeState) {
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

    // MARK: - Result & Alert
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

    private func showAlertInfo(_ info: IntervalRunViewModel.AlertInfo) {
        let alert = UIAlertController(title: info.title, message: info.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in
            info.onConfirm?()
        })
        present(alert, animated: true)
    }

    // MARK: - Setup UI
    private func setupUI() {
        view.backgroundColor = AppColor.UI.backgroundGrouped

        // MapView
        mapView.delegate                 = mapDelegate
        mapView.isUserInteractionEnabled = false
        let config                       = MKStandardMapConfiguration()
        config.emphasisStyle             = .muted
        config.pointOfInterestFilter     = .excludingAll
        mapView.preferredConfiguration   = config
        mapView.layer.cornerRadius       = 30
        mapView.layer.masksToBounds      = true
        view.addSubview(mapView)
        view.addSubview(sourceBadge)

        // Stats Panel
        statsPanel.axis               = .vertical
        statsPanel.spacing            = 0
        statsPanel.backgroundColor    = AppColor.UI.cardBackground.withAlphaComponent(0.96)
        statsPanel.layer.cornerRadius = 28
        statsPanel.layer.borderWidth  = 1
        statsPanel.layer.borderColor  = AppColor.UI.border.withAlphaComponent(0.7).cgColor
        statsPanel.layer.masksToBounds = true
        view.addSubview(statsPanel)

        statsPanel.addArrangedSubview(createStatRow(label: "DURATION", valueLabel: durationLabel))
        statsPanel.addArrangedSubview(createDivider())
        statsPanel.addArrangedSubview(createStatRow(label: "LAP DISTANCE", valueLabel: lapDistanceLabel))
        statsPanel.addArrangedSubview(createDivider())

        let paceStack = UIStackView()
        paceStack.axis         = .horizontal
        paceStack.distribution = .fillEqually
        paceStack.addArrangedSubview(createStatRow(label: "AVG PACE", valueLabel: avgPaceLabel))
        let d1 = createDivider(isVertical: true)
        paceStack.addSubview(d1)
        paceStack.addArrangedSubview(createStatRow(label: "LAP PACE", valueLabel: currPaceLabel))
        statsPanel.addArrangedSubview(paceStack)
        statsPanel.addArrangedSubview(createDivider())

        hrStack.axis         = .horizontal
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
        configureButton(pauseButton,     systemName: "pause.fill",       color: AppColor.UI.workoutPause)
        configureButton(resumeButton,    systemName: "play.fill",        color: AppColor.UI.workoutResume)
        configureButton(stopButton,      systemName: "stop.fill",        color: AppColor.UI.workoutStop)
        resumeButton.isHidden = true
        stopButton.isHidden   = true
        buttonContainer.addSubview(pauseButton)
        buttonContainer.addSubview(resumeButton)
        buttonContainer.addSubview(stopButton)

        manualLapButton.setImage(UIImage(systemName: "forward.end.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)), for: .normal)
        manualLapButton.tintColor          = AppColor.UI.textInverse
        manualLapButton.backgroundColor    = AppColor.UI.primary
        manualLapButton.layer.cornerRadius = 28
        manualLapButton.isHidden           = true
        buttonContainer.addSubview(manualLapButton)

        // Countdown
        countdownContainer.backgroundColor = AppColor.UI.backgroundGrouped
        view.addSubview(countdownContainer)
        countdownLabel.font          = AppFont.UI.metricDisplayXL
        countdownLabel.textColor     = AppColor.UI.workoutPause
        countdownLabel.textAlignment = .center
        countdownLabel.text          = "1"
        countdownContainer.addSubview(countdownLabel)
        countdownSubLabel.font          = AppFont.UI.titleSM
        countdownSubLabel.textColor     = AppColor.UI.textSecondary
        countdownSubLabel.textAlignment = .center
        countdownSubLabel.text          = "준비하세요"
        countdownContainer.addSubview(countdownSubLabel)

        // Rest Overlay
        restOverlay.backgroundColor = AppColor.UI.overlayStrong
        restOverlay.isHidden        = true
        view.addSubview(restOverlay)
        restTitleLabel.text          = "REST"
        restTitleLabel.font          = AppFont.UI.titleSM
        restTitleLabel.textColor     = AppColor.UI.textInverseSecondary
        restTitleLabel.textAlignment = .center
        restOverlay.addSubview(restTitleLabel)
        restCountdownLabel.font          = AppFont.UI.metricDisplayLG
        restCountdownLabel.textColor     = AppColor.UI.textInverse
        restCountdownLabel.textAlignment = .center
        restOverlay.addSubview(restCountdownLabel)

        // Paused Overlay
        pausedOverlay.backgroundColor = AppColor.UI.overlay
        pausedOverlay.isHidden        = true
        view.addSubview(pausedOverlay)
        pausedLabel.text          = "일시정지"
        pausedLabel.font          = AppFont.UI.headlineLG
        pausedLabel.textColor     = AppColor.UI.textInverse
        pausedLabel.textAlignment = .center
        pausedOverlay.addSubview(pausedLabel)

        sourceBadge.font                = AppFont.UI.labelSM
        sourceBadge.textColor           = AppColor.UI.textSecondary
        sourceBadge.backgroundColor     = AppColor.UI.backgroundTertiary.withAlphaComponent(0.95)
        sourceBadge.layer.cornerRadius  = 14
        sourceBadge.layer.masksToBounds = true
        sourceBadge.textAlignment       = .center
        sourceBadge.layer.borderWidth   = 1
        sourceBadge.layer.borderColor   = AppColor.UI.border.withAlphaComponent(0.8).cgColor
        sourceBadge.isHidden            = true

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
        durationLabel.text      = "00:00"
        avgPaceLabel.text       = "--'--\""
        currPaceLabel.text      = "--'--\""
        avgHeartRateLabel.text  = "--"
        currHeartRateLabel.text = "--"

        statsPanel.alpha         = 1
        buttonContainer.isHidden = true
    }

    private func configureButton(_ button: UIButton, systemName: String, color: UIColor) {
        button.setImage(UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)), for: .normal)
        button.tintColor          = AppColor.UI.textInverse
        button.backgroundColor    = color
        button.layer.cornerRadius = 38
    }

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

        if valueLabel === lapDistanceLabel {
            valueLabel.font      = UIFont.systemFont(ofSize: 34, weight: .black)
            valueLabel.textColor = RunningLevelManager.shared.accentUIColor
        } else if valueLabel === currPaceLabel || valueLabel === currHeartRateLabel {
            valueLabel.font      = AppFont.UI.metricTitle
            valueLabel.textColor = AppColor.UI.textPrimary
        } else {
            valueLabel.font      = AppFont.UI.metricBody
            valueLabel.textColor = AppColor.UI.textPrimary
        }
        valueLabel.textAlignment             = .left
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor        = 0.7

        let stack     = UIStackView(arrangedSubviews: [lLabel, valueLabel])
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

}

// MARK: - SwiftUI Wrapper

struct IntervalRunView: UIViewControllerRepresentable {
    let sets        : Int
    let lapDistance : Double
    let restDuration: TimeInterval
    var isIndoor      : Bool = false
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

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

final class FreeRunViewController: HTViewController, CLLocationManagerDelegate {

    // MARK: - Properties
    private let locationManager = CLLocationManager()
    private var allLocations    : [CLLocation] = []
    private var recentLocations : [CLLocation] = []
    private var routeCoordinates: [CLLocationCoordinate2D] = []

    private var elapsed: TimeInterval = 0
    private var timer  : Timer?
    
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

    // MARK: - Layout Helpers
    private let paceStack = UIStackView()
    private let hrStack   = UIStackView()
    private let d1        = UIView()
    private let d2        = UIView()
    
    //MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()


    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func configHierarchy() {
        view.addSubview(mapView)
        view.addSubview(statsPanel)
        view.addSubview(buttonContainer)
        view.addSubview(countdownContainer)
        view.addSubview(pausedOverlay)

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
    }
    
    override func configView() {
        view.backgroundColor = AppColor.UI.workoutBg
        
        mapView.delegate                 = self
        mapView.isUserInteractionEnabled = false
        mapView.showsUserLocation        = true
        mapView.mapType                  = .mutedStandard
        let config = MKStandardMapConfiguration()
        config.emphasisStyle = .muted
        config.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = config
    }
    
    private func createStatRow(label: String, valueLabel: UILabel) -> UIView {
        let container = UIView()
        container.backgroundColor = AppColor.UI.workoutBg

        let lLabel = UILabel()
        lLabel.text = label
        lLabel.font = .systemFont(ofSize: 10, weight: .regular)
        lLabel.textColor = AppColor.UI.textSecondary
        lLabel.textAlignment = .center

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        valueLabel.textColor = AppColor.UI.textPrimary
        valueLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [lLabel, valueLabel])
        stack.axis = .vertical
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
}

extension FreeRunViewController: MKMapViewDelegate {
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
        guard annotation is MKUserLocation else { return nil }
        let id = "userLocationDot"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: id)
        if annotationView == nil {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: id)

            let outerSize: CGFloat = 30
            let innerSize: CGFloat = 14

            let container = UIView(frame: CGRect(x: 0, y: 0, width: outerSize, height: outerSize))

            // 반투명 외부 링
            let outerRing = UIView(frame: container.bounds)
            outerRing.backgroundColor = AppColor.UI.workoutRoute.withAlphaComponent(0.2)
            outerRing.layer.cornerRadius = outerSize / 2
            container.addSubview(outerRing)

            // 내부 solid dot
            let offset = (outerSize - innerSize) / 2
            let innerDot = UIView(frame: CGRect(x: offset, y: offset, width: innerSize, height: innerSize))
            innerDot.backgroundColor = AppColor.UI.workoutRoute
            innerDot.layer.cornerRadius = innerSize / 2
            innerDot.layer.borderColor = UIColor.white.cgColor
            innerDot.layer.borderWidth = 2.5
            innerDot.layer.shadowColor = UIColor.black.cgColor
            innerDot.layer.shadowOpacity = 0.25
            innerDot.layer.shadowRadius = 4
            innerDot.layer.shadowOffset = CGSize(width: 0, height: 2)
            container.addSubview(innerDot)

            annotationView?.addSubview(container)
            annotationView?.frame = container.frame
        } else {
            annotationView?.annotation = annotation
        }
        return annotationView
    }
}

// MARK: - SwiftUI Wrapper

struct FreeRunView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> FreeRunViewController {
        return FreeRunViewController()
    }

    func updateUIViewController(_ uiViewController: FreeRunViewController, context: Context) {}
}

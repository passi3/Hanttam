//
//  LocationServiece.swift
//  Hanttam
//
//  Created by passi on 3/31/26.
//

import Foundation
import CoreLocation
import Combine

class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var periodicTimer: Timer?

    @Published var userLocation: CLLocationCoordinate2D?
    @Published var locationUpdated: Int = 0

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let coord = locations.last?.coordinate {
            userLocation = coord
            locationUpdated += 1
        }
    }

    func startPeriodicUpdates(interval: TimeInterval = 3.0) {
        stopPeriodicUpdates()
        start()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.manager.requestLocation()
        }
    }

    func stopPeriodicUpdates() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { }
}


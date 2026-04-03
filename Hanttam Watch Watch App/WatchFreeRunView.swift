//
//  WatchFreeRunView.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/2/26.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Run Session

final class WatchRunSession: NSObject, ObservableObject {

    @Published var phase: WorkoutPhase = .preparing
    @Published var countdown: Int = 3
    @Published var elapsed: TimeInterval = 0
    @Published var totalDistance: Double = 0       // meters
    @Published var avgPace: TimeInterval?           // sec/km
    @Published var currentPace: TimeInterval?       // sec/km
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var route: [CLLocationCoordinate2D] = []

    private let locationManager = CLLocationManager()
    private var allLocations: [CLLocation] = []
    private var recentLocations: [CLLocation] = []
    private var timer: Timer?
    private var countdownTimer: Timer?
    private var didNotifyStarted = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
    }

    func beginCountdown() {
        phase = .preparing
        countdown = 3
        locationManager.requestWhenInUseAuthorization()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.countdown -= 1
            if self.countdown <= 0 {
                t.invalidate()
                self.startRunning()
            }
        }
    }

    private func startRunning() {
        phase = .running
        if !didNotifyStarted {
            WatchBridge.shared.sendWorkoutStarted(kind: .freeRun)
            didNotifyStarted = true
        }
        locationManager.startUpdatingLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.phase == .running else { return }
            self.elapsed += 1
            self.recalcPace()
        }
    }

    func pause() {
        phase = .paused
        locationManager.stopUpdatingLocation()
    }

    func resume() {
        phase = .running
        locationManager.startUpdatingLocation()
    }

    func stop() {
        phase = .finished
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        if didNotifyStarted {
            WatchBridge.shared.sendWorkoutStopped(kind: .freeRun)
        }
    }

    private func recalcPace() {
        if totalDistance > 10 {
            avgPace = elapsed / (totalDistance / 1000)
        }
        guard recentLocations.count >= 2 else { return }
        var d = 0.0
        for i in 0..<recentLocations.count - 1 {
            d += recentLocations[i+1].distance(from: recentLocations[i])
        }
        guard d > 5 else { return }
        let t = recentLocations.last!.timestamp.timeIntervalSince(recentLocations.first!.timestamp)
        currentPace = t / (d / 1000)
    }

    // MARK: - Formatted Strings

    var durationText: String {
        let h = Int(elapsed) / 3600
        let m = Int(elapsed) % 3600 / 60
        let s = Int(elapsed) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%02d:%02d", m, s)
    }

    var distanceText: String { String(format: "%.2f KM", totalDistance / 1000) }

    func paceText(_ secPerKm: TimeInterval?) -> String {
        guard let p = secPerKm, p.isFinite, p > 0, p < 3600 else { return "--'--\"" }
        return String(format: "%d'%02d\"", Int(p) / 60, Int(p) % 60)
    }
}

// MARK: - CLLocationManagerDelegate

extension WatchRunSession: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            allLocations.append(loc)
            route.append(loc.coordinate)
            recentLocations.append(loc)
            if recentLocations.count > 8 { recentLocations.removeFirst() }
            totalDistance = zip(allLocations, allLocations.dropFirst())
                .reduce(0.0) { $0 + $1.1.distance(from: $1.0) }
            cameraPosition = .region(
                MKCoordinateRegion(center: loc.coordinate,
                                   latitudinalMeters: 300,
                                   longitudinalMeters: 300)
            )
            recalcPace()
        }
    }
}

// MARK: - View

struct WatchFreeRunView: View {

    @StateObject private var session = WatchRunSession()
    @ObservedObject private var levelManager = RunningLevelManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VStack(spacing: 0) {

                // Map
                Map(position: $session.cameraPosition) {
                    if session.route.count >= 2 {
                        MapPolyline(coordinates: session.route)
                            .stroke(AppColor.blue, lineWidth: 5)
                    }
                    if let last = session.route.last {
                        Annotation("", coordinate: last) {
                            Circle()
                                .fill(AppColor.blue)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 80)
                .allowsHitTesting(false)
                .opacity(session.phase == .preparing ? 0.3 : 1)

                // Stats
                VStack(spacing: 0) {
                    statsRow(
                        ("DURATION", session.durationText),
                        ("DISTANCE", session.distanceText)
                    )
                    Divider()
                    statsRow(
                        ("AVG PACE",  session.paceText(session.avgPace)),
                        ("CURR PACE", session.paceText(session.currentPace))
                    )
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .opacity(session.phase == .preparing ? 0.3 : 1)

                Spacer(minLength: 4)

                // Buttons
                switch session.phase {
                case .preparing:
                    EmptyView()
                case .running:
                    Button {
                        session.pause()
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(AppColor.orange, in: Circle())

                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                case .paused:
                    HStack(spacing: 20) {
                        Button {
                            session.resume()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(AppColor.green, in: Circle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            session.stop()
                            dismiss()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(AppColor.red, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 8)
                case .finished:
                    EmptyView()
                }
            }

            // Countdown overlay
            if session.phase == .preparing {
                VStack(spacing: 4) {
                    Text("\(session.countdown)")
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColor.orange)
                        .contentTransition(.numericText())
                    Text("준비하세요")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Paused overlay
            if session.phase == .paused {
                Color.black.opacity(0.4)
                    .frame(height: 80)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .overlay(alignment: .top) {
                        Text("일시정지")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppColor.yellow)
                            .padding(.top, 30)
                    }
                    .allowsHitTesting(false)
            }
        }
        .onAppear { session.beginCountdown() }
        .onDisappear { session.stop() }
    }

    // MARK: - Helpers

    private func statsRow(_ left: (String, String), _ right: (String, String)) -> some View {
        HStack(spacing: 0) {
            statItem(left.0, left.1)
            Divider()
            statItem(right.0, right.1)
        }
        .frame(height: 44)
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

//
//  WatchIntervalRunView.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/2/26.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine
import WatchKit

// MARK: - Interval Session

final class WatchIntervalSession: NSObject, ObservableObject {

    enum Phase: Equatable {
        case preparing
        case runningLap
        case resting
        case paused(prior: PriorPhase)
        case finished

        enum PriorPhase: Equatable {
            case runningLap, resting
        }
    }

    // Config
    let totalSets: Int
    let lapDistance: Double
    let restDuration: TimeInterval

    // Published state
    @Published var phase: Phase = .preparing
    @Published var countdown: Int = 3
    @Published var elapsed: TimeInterval = 0
    @Published var currentSet: Int = 1
    @Published var lapDistanceCurrent: Double = 0
    @Published var restRemaining: TimeInterval = 0
    @Published var avgPace: TimeInterval?
    @Published var currentPace: TimeInterval?
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var route: [CLLocationCoordinate2D] = []

    // Internal
    private let locationManager = CLLocationManager()
    private var allLocations: [CLLocation] = []
    private var lapLocations: [CLLocation] = []
    private var recentLocations: [CLLocation] = []
    private var timer: Timer?
    private var countdownTimer: Timer?
    private var didNotifyStarted = false

    private var lapElapsed: TimeInterval = 0
    private var lapStartDate = Date()
    private var laps: [IntervalLap] = []
    private var totalRunDistance: Double = 0
    private var totalRunTime: TimeInterval = 0

    init(sets: Int, lapDistance: Double, restDuration: TimeInterval) {
        self.totalSets = sets
        self.lapDistance = lapDistance
        self.restDuration = restDuration
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
    }

    // MARK: - Lifecycle

    func beginCountdown() {
        phase = .preparing
        countdown = 3
        locationManager.requestWhenInUseAuthorization()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.countdown -= 1
            if self.countdown <= 0 {
                t.invalidate()
                self.startRunningLap()
            }
        }
    }

    private func startRunningLap() {
        phase = .runningLap
        lapElapsed = 0
        lapDistanceCurrent = 0
        lapLocations = []
        recentLocations = []
        lapStartDate = Date()
        if !didNotifyStarted {
            WatchBridge.shared.sendWorkoutStarted(kind: .intervalRun)
            didNotifyStarted = true
        }
        locationManager.startUpdatingLocation()
        startTimer()
        WKInterfaceDevice.current().play(.start)
    }

    private func startResting() {
        recordLap(type: .run)
        phase = .resting
        restRemaining = restDuration
        lapStartDate = Date()
        locationManager.stopUpdatingLocation()
        WKInterfaceDevice.current().play(.success)
    }

    private func restFinished() {
        recordLap(type: .rest)
        currentSet += 1
        if currentSet > totalSets {
            finishWorkout()
        } else {
            startRunningLap()
        }
    }

    func pause() {
        let prior: Phase.PriorPhase = phase == .resting ? .resting : .runningLap
        phase = .paused(prior: prior)
        timer?.invalidate()
        locationManager.stopUpdatingLocation()
    }

    func resume() {
        guard case .paused(let prior) = phase else { return }
        switch prior {
        case .runningLap:
            phase = .runningLap
            locationManager.startUpdatingLocation()
        case .resting:
            phase = .resting
        }
        startTimer()
    }

    func stop() {
        // record in-progress lap
        if case .paused(let prior) = phase {
            switch prior {
            case .runningLap: recordLap(type: .run)
            case .resting: recordLap(type: .rest)
            }
        } else if phase == .runningLap {
            recordLap(type: .run)
        } else if phase == .resting {
            recordLap(type: .rest)
        }
        finishWorkout()
    }

    func manualLap() {
        guard phase == .runningLap else { return }
        if currentSet >= totalSets {
            recordLap(type: .run)
            finishWorkout()
        } else {
            startResting()
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
                self.recalcPace()
            case .resting:
                self.elapsed += 1
                self.restRemaining -= 1
                if self.restRemaining <= 3 && self.restRemaining > 0 {
                    WKInterfaceDevice.current().play(.notification)
                }
                if self.restRemaining <= 0 {
                    self.restFinished()
                }
            default:
                break
            }
        }
    }

    // MARK: - Recording

    private func recordLap(type: IntervalLap.LapType) {
        let now = Date()
        let lapNumber = laps.count + 1
        let dist = type == .run ? lapDistanceCurrent : 0
        let dur = type == .run ? lapElapsed : (restDuration - restRemaining)
        let pace: TimeInterval? = (type == .run && dist > 10) ? (dur / (dist / 1000.0)) : nil

        let lap = IntervalLap(
            id: lapNumber, type: type, duration: dur, distance: dist,
            startDate: lapStartDate, endDate: now, avgPace: pace
        )
        laps.append(lap)

        if type == .run {
            totalRunDistance += dist
            totalRunTime += dur
        }
    }

    private func finishWorkout() {
        phase = .finished
        timer?.invalidate()
        timer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        locationManager.stopUpdatingLocation()
        if didNotifyStarted {
            WatchBridge.shared.sendWorkoutStopped(kind: .intervalRun)
        }

        // 인터벌 기록은 iPhone 측 HealthKit에 저장됨
    }

    // MARK: - Pace

    private func recalcPace() {
        let runDist = totalRunDistance + lapDistanceCurrent
        let runTime = totalRunTime + lapElapsed
        if runDist > 10 {
            avgPace = runTime / (runDist / 1000)
        }
        guard recentLocations.count >= 2 else { return }
        var d = 0.0
        for i in 0..<recentLocations.count - 1 {
            d += recentLocations[i + 1].distance(from: recentLocations[i])
        }
        guard d > 5 else { return }
        let t = recentLocations.last!.timestamp.timeIntervalSince(recentLocations.first!.timestamp)
        currentPace = t / (d / 1000)
    }

    // MARK: - Formatted

    var durationText: String {
        let h = Int(elapsed) / 3600, m = Int(elapsed) % 3600 / 60, s = Int(elapsed) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    var lapText: String {
        if phase == .resting || (phase != .runningLap && restRemaining > 0) {
            return "REST \(Int(max(0, restRemaining)))s"
        }
        return "\(Int(lapDistanceCurrent))m/\(Int(lapDistance))m"
    }

    var setText: String { "\(currentSet)/\(totalSets)" }

    func paceText(_ secPerKm: TimeInterval?) -> String {
        guard let p = secPerKm, p.isFinite, p > 0, p < 3600 else { return "--'--\"" }
        return String(format: "%d'%02d\"", Int(p) / 60, Int(p) % 60)
    }
}

// MARK: - CLLocationManagerDelegate

extension WatchIntervalSession: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self, self.phase == .runningLap else { return }

            if let prev = self.lapLocations.last {
                self.lapDistanceCurrent += loc.distance(from: prev)
            }
            self.lapLocations.append(loc)

            self.allLocations.append(loc)
            self.route.append(loc.coordinate)
            self.recentLocations.append(loc)
            if self.recentLocations.count > 8 { self.recentLocations.removeFirst() }

            self.cameraPosition = .region(
                MKCoordinateRegion(center: loc.coordinate,
                                   latitudinalMeters: 300,
                                   longitudinalMeters: 300)
            )
            self.recalcPace()

            // Auto-complete lap
            if self.lapDistanceCurrent >= self.lapDistance {
                if self.currentSet >= self.totalSets {
                    self.recordLap(type: .run)
                    self.finishWorkout()
                } else {
                    self.startResting()
                }
            }
        }
    }
}

// MARK: - View

struct WatchIntervalRunView: View {

    let sets: Int
    let lapDistance: Double
    let restDuration: TimeInterval

    @StateObject private var session: WatchIntervalSession
    @ObservedObject private var levelManager = RunningLevelManager.shared
    @Environment(\.dismiss) private var dismiss

    init(sets: Int, lapDistance: Double, restDuration: TimeInterval) {
        self.sets = sets
        self.lapDistance = lapDistance
        self.restDuration = restDuration
        _session = StateObject(wrappedValue: WatchIntervalSession(
            sets: sets, lapDistance: lapDistance, restDuration: restDuration
        ))
    }

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
                        ("TIME", session.durationText),
                        ("SET", session.setText)
                    )
                    Divider()
                    statsRow(
                        ("LAP", session.lapText),
                        ("PACE", session.paceText(session.avgPace))
                    )
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .opacity(session.phase == .preparing ? 0.3 : 1)

                Spacer(minLength: 4)

                // Buttons
                buttonSection
            }

            // Countdown
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

            // Rest overlay
            if session.phase == .resting {
                Color.black.opacity(0.5)
                    .frame(height: 80)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .overlay(alignment: .top) {
                        VStack(spacing: 2) {
                            Text("REST")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("\(Int(max(0, session.restRemaining)))")
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 16)
                    }
                    .allowsHitTesting(false)
            }

            // Paused overlay
            if case .paused = session.phase {
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
        .onDisappear { if session.phase != .finished { session.stop() } }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttonSection: some View {
        switch session.phase {
        case .preparing, .finished:
            EmptyView()
        case .runningLap:
            HStack(spacing: 16) {
                Button { session.pause() } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(AppColor.orange, in: Circle())
                }
                .buttonStyle(.plain)

                Button { session.manualLap() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(AppColor.blue, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
        case .resting:
            Button { session.pause() } label: {
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
                Button { session.resume() } label: {
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
        }
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

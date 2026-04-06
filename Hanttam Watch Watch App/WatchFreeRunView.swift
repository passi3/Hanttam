//
//  WatchFreeRunView.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/2/26.
//

import SwiftUI
import CoreLocation
import Combine
import _WatchKit_SwiftUI

// MARK: - Run Session

final class WatchRunSession: NSObject, ObservableObject {

    @Published var phase: WorkoutPhase = .preparing
    @Published var countdown: Int = 3
    @Published var elapsed: TimeInterval = 0
    @Published var totalDistance: Double = 0       // meters
    @Published var avgPace: TimeInterval?           // sec/km
    @Published var currentPace: TimeInterval?       // sec/km
    @Published var heartRate: Double?
    @Published var avgHeartRate: Double?
    @Published var segmentPace: TimeInterval?
    @Published var segmentAvgHeartRate: Double?
    @Published var route: [CLLocationCoordinate2D] = []

    private let locationManager = CLLocationManager()
    private let hkManager = WatchWorkoutSessionManager.shared
    private var allLocations: [CLLocation] = []
    private var recentLocations: [CLLocation] = []
    private var timer: Timer?
    private var countdownTimer: Timer?
    private var didNotifyStarted = false
    private var cancellables = Set<AnyCancellable>()
    private var nextSegmentBoundary: Double = 1000
    private var segmentStartDistance: Double = 0
    private var segmentStartElapsed: TimeInterval = 0
    private var segmentHeartRateSamples: [HeartRateSample] = []

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5

        hkManager.$heartRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bpm in
                guard let self else { return }
                self.heartRate = bpm
                self.captureSegmentHeartRateSample(bpm)
            }
            .store(in: &cancellables)
        hkManager.$avgHeartRate
            .receive(on: DispatchQueue.main)
            .assign(to: \.avgHeartRate, on: self)
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: WatchBridge.remoteCommandNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, let cmd = note.userInfo?["command"] as? String else { return }
                switch cmd {
                case WorkoutStreamKey.commandPause:  self.pause()
                case WorkoutStreamKey.commandResume: self.resume()
                case WorkoutStreamKey.commandStop:   self.stop()
                default: break
                }
            }
            .store(in: &cancellables)
    }

    func beginCountdown(skip: Bool = false) {
        if skip {
            startRunning()
            return
        }
        phase = .preparing
        countdown = 3
        locationManager.requestWhenInUseAuthorization()
        Task { await hkManager.requestAuthorization() }

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
        resetSegmentState()
        if !didNotifyStarted {
            // 폰이 startWatchApp으로 앱을 실행했으면 해당 설정을 재사용, 아니면 기본 설정으로 시작
            if let config = WatchBridge.shared.consumePendingWorkoutConfiguration() {
                hkManager.startSession(with: config)
            } else {
                hkManager.startSession()
            }
            WatchBridge.shared.sendWorkoutStarted(kind: .freeRun)
            WatchBridge.shared.sendSessionEvent(WorkoutStreamKey.sessionStarted)
            didNotifyStarted = true
        }
        locationManager.startUpdatingLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.phase == .running else { return }
            self.elapsed += 1
            self.recalcPace()
            self.sendSnapshot()
        }
    }

    func pause() {
        guard phase == .running else { return }
        phase = .paused
        hkManager.pauseSession()
        locationManager.stopUpdatingLocation()
        sendSnapshot()
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .running
        hkManager.resumeSession()
        locationManager.startUpdatingLocation()
        sendSnapshot()
    }

    func stop() {
        guard phase != .finished else { return }
        phase = .finished
        hkManager.endSession()
        locationManager.stopUpdatingLocation()
        timer?.invalidate(); timer = nil
        countdownTimer?.invalidate(); countdownTimer = nil
        if didNotifyStarted {
            WatchBridge.shared.sendWorkoutStopped(kind: .freeRun)
            WatchBridge.shared.sendSessionEvent(WorkoutStreamKey.sessionEnded)
        }
        sendSnapshot()
    }

    private func sendSnapshot() {
        let snapshot = WorkoutDataSnapshot(
            elapsed: elapsed,
            totalDistance: totalDistance,
            avgPace: avgPace,
            currentPace: segmentPace,
            heartRate: heartRate,
            avgHeartRate: avgHeartRate,
            segmentPace: segmentPace,
            segmentAvgHeartRate: segmentAvgHeartRate,
            activeCalories: hkManager.activeCalories,
            currentLatitude: route.last?.latitude,
            currentLongitude: route.last?.longitude,
            phase: phase.rawValue
        )
        // HK 미러링 경로로 전송 (WCSession은 내부에서 폴백으로 사용)
        hkManager.sendSnapshot(snapshot)
    }

    private func recalcPace() {
        if totalDistance > 10 {
            avgPace = elapsed / (totalDistance / 1000)
        }
        let currentSegmentDistance = totalDistance - segmentStartDistance
        let currentSegmentElapsed = elapsed - segmentStartElapsed
        if currentSegmentDistance > 10, currentSegmentElapsed > 0 {
            segmentPace = currentSegmentElapsed / (currentSegmentDistance / 1000)
        } else {
            segmentPace = nil
        }
        currentPace = segmentPace
        if !segmentHeartRateSamples.isEmpty {
            segmentAvgHeartRate = segmentHeartRateSamples.reduce(0) { $0 + $1.bpm } / Double(segmentHeartRateSamples.count)
        } else {
            segmentAvgHeartRate = nil
        }
    }

    private func resetSegmentState() {
        nextSegmentBoundary = 1000
        segmentStartDistance = 0
        segmentStartElapsed = 0
        segmentHeartRateSamples.removeAll()
        segmentPace = nil
        segmentAvgHeartRate = nil
        currentPace = nil
    }

    private func advanceSegmentBoundaryIfNeeded() {
        while totalDistance >= nextSegmentBoundary {
            nextSegmentBoundary += 1000
            segmentStartDistance = totalDistance
            segmentStartElapsed = elapsed
            segmentHeartRateSamples.removeAll()
            segmentAvgHeartRate = nil
            segmentPace = nil
            currentPace = nil
        }
    }

    private func captureSegmentHeartRateSample(_ bpm: Double?) {
        guard phase == .running, let bpm else { return }
        segmentHeartRateSamples.append(HeartRateSample(date: Date(), bpm: bpm))
        segmentAvgHeartRate = segmentHeartRateSamples.reduce(0) { $0 + $1.bpm } / Double(segmentHeartRateSamples.count)
    }

    // MARK: - Formatted

    var durationText: String {
        let h = Int(elapsed) / 3600
        let m = Int(elapsed) % 3600 / 60
        let s = Int(elapsed) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%02d:%02d", m, s)
    }

    var distanceText: String { String(format: "%.2f", totalDistance / 1000) }

    func paceText(_ secPerKm: TimeInterval?) -> String {
        guard let p = secPerKm, p.isFinite, p > 0, p < 3600 else { return "--'--\"" }
        return String(format: "%d'%02d\"", Int(p) / 60, Int(p) % 60)
    }

    func hrText(_ bpm: Double?) -> String {
        guard let bpm else { return "--" }
        return String(format: "%.0f", bpm)
    }

    func makeSummaryData() -> WatchWorkoutSummaryData {
        WatchWorkoutSummaryBuilder.freeRun(
            route: allLocations,
            elapsed: elapsed,
            totalDistance: totalDistance,
            avgPace: avgPace,
            avgHeartRate: avgHeartRate,
            calories: hkManager.activeCalories
        )
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
            advanceSegmentBoundaryIfNeeded()
            recalcPace()
        }
    }
}

// MARK: - View

struct WatchFreeRunView: View {

    @StateObject private var session = WatchRunSession()
    @State private var selection: Int = 1
    @State private var showingAveragePace = false
    @State private var showingAverageHeartRate = false
    var skipCountdown: Bool = false
    var onFinish: (WatchWorkoutSummaryData) -> Void = { _ in }

    var body: some View {
        Group {
            if session.phase == .preparing {
                ZStack {
                    Color.black.ignoresSafeArea()
                    countdownOverlay
                }
            } else {
                TabView(selection: $selection) {
                    controlsTab
                        .tag(0)

                    metricsTab
                        .tag(1)

                    nowPlayingTab
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .background(Color.black)
            }
        }
        .onAppear { session.beginCountdown(skip: skipCountdown) }
        .onChange(of: session.phase) { _, newPhase in
            guard newPhase == .finished else { return }
            onFinish(session.makeSummaryData())
        }
        .onDisappear { session.stop() }
    }

    // MARK: - Tabs

    private var controlsTab: some View {
        VStack(spacing: 20) {
            if session.phase == .paused {
                Button { session.resume() } label: {
                    VStack {
                        Image(systemName: "play.fill")
                            .font(.title2)
                        Text("재개")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
            } else {
                Button { session.pause() } label: {
                    VStack {
                        Image(systemName: "pause.fill")
                            .font(.title2)
                        Text("일시정지")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
            }

            Button {
                session.stop()
            } label: {
                VStack {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                    Text("종료")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.red.opacity(0.2), in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    private var metricsTab: some View {
        WatchWorkoutDashboardPage(
            topIcon: "figure.run",
            topLeading: "SESSION",
            topTrailingText: session.phase == .paused ? "PAUSED" : nil,
            accentColor: RunningLevelManager.shared.accentColor,
            primaryValue: session.distanceText,
            primaryUnit: "KM",
            leftMetricTitle: "TIME",
            leftMetricValue: session.durationText,
            rightMetricTitle: showingAveragePace ? "AVG PACE" : "SEGMENT PACE",
            rightMetricValue: showingAveragePace ? averagePaceText : currentPaceText,
            rightMetricAction: { showingAveragePace.toggle() },
            bottomIcon: "heart.fill",
            bottomTint: showingAverageHeartRate ? .pink : .red,
            bottomLabel: showingAverageHeartRate ? "AVERAGE BPM" : "SEGMENT BPM",
            bottomValue: showingAverageHeartRate
                ? session.hrText(session.avgHeartRate)
                : session.hrText(session.segmentAvgHeartRate),
            bottomUnit: "BPM",
            bottomProgress: heartRateProgress(
                showingAverageHeartRate ? session.avgHeartRate : session.segmentAvgHeartRate
            ),
            bottomAction: { showingAverageHeartRate.toggle() }
        )
    }

    private var nowPlayingTab: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            NowPlayingView()
        }
    }

    private var currentPaceText: String {
        session.paceText(session.segmentPace ?? session.avgPace)
    }

    private var averagePaceText: String {
        session.paceText(session.avgPace ?? session.currentPace)
    }

    private func heartRateProgress(_ bpm: Double?) -> Double? {
        guard let bpm else { return nil }
        return min(max((bpm - 80) / 90, 0), 1)
    }

    // MARK: - Overlays

    private var countdownOverlay: some View {
        VStack(spacing: 4) {
            Text("\(session.countdown)")
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundStyle(RunningLevelManager.shared.accentColor)
            Text("준비하세요")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    WatchFreeRunView()
}

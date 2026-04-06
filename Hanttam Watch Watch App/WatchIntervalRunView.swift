//
//  WatchIntervalRunView.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/2/26.
//

import SwiftUI
import CoreLocation
import Combine
import WatchKit
import _WatchKit_SwiftUI
internal import HealthKit

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
    @Published var heartRate: Double?
    @Published var avgHeartRate: Double?
    @Published var lapPace: TimeInterval?
    @Published var lapAvgHeartRate: Double?
    @Published var currentLapSummary: WatchLapSummarySnapshot?
    @Published var route: [CLLocationCoordinate2D] = []

    // Internal
    private let locationManager = CLLocationManager()
    private let hkManager = WatchWorkoutSessionManager.shared
    private var allLocations: [CLLocation] = []
    private var lapLocations: [CLLocation] = []
    private var recentLocations: [CLLocation] = []
    private var timer: Timer?
    private var countdownTimer: Timer?
    private var didNotifyStarted = false
    private var cancellables = Set<AnyCancellable>()

    private var lapElapsed: TimeInterval = 0
    private var lapStartDate = Date()
    private var laps: [IntervalLap] = []
    var totalRunDistance: Double = 0
    private var totalRunTime: TimeInterval = 0
    private var lapHeartRateSamples: [HeartRateSample] = []
    private(set) var lastRunLapPace: TimeInterval?
    private(set) var lastRunLapAvgHeartRate: Double?
    private var pendingRestTransition = false
    private var pendingFinishAfterOverlay = false
    private var lapSummaryDismissWorkItem: DispatchWorkItem?
    private var countdownEndsAt: Date?

    init(sets: Int, lapDistance: Double, restDuration: TimeInterval) {
        self.totalSets = sets
        self.lapDistance = lapDistance
        self.restDuration = restDuration
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5

        hkManager.$heartRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bpm in
                guard let self else { return }
                self.heartRate = bpm
                self.captureLapHeartRateSample(bpm)
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
                case WorkoutStreamKey.commandPause: self.pause()
                case WorkoutStreamKey.commandResume: self.resume()
                case WorkoutStreamKey.commandStop: self.stop()
                default: break
                }
            }
            .store(in: &cancellables)

    }

    // MARK: - Lifecycle

    func beginCountdown(skip: Bool = false) {
        if skip {
            startRunningLap()
            return
        }
        phase = .preparing
        countdown = 3
        countdownEndsAt = Date().addingTimeInterval(Double(countdown))
        sendSnapshot()
        locationManager.requestWhenInUseAuthorization()
        Task { await hkManager.requestAuthorization() }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.countdown -= 1
            self.sendSnapshot()
            if self.countdown <= 0 {
                t.invalidate()
                self.startRunningLap()
            }
        }
    }

    private func startRunningLap() {
        pendingRestTransition = false
        pendingFinishAfterOverlay = false
        countdownEndsAt = nil
        phase = .runningLap
        lapElapsed = 0
        lapDistanceCurrent = 0
        lapLocations = []
        recentLocations = []
        lapStartDate = Date()
        lapHeartRateSamples.removeAll()
        lapPace = nil
        lapAvgHeartRate = nil
        currentPace = nil

        if !didNotifyStarted {
            if let config = WatchBridge.shared.consumePendingWorkoutConfiguration() {
                hkManager.startSession(with: config)
            } else {
                let config = HKWorkoutConfiguration()
                config.activityType = .running
                config.locationType = .indoor
                hkManager.startSession(with: config)
            }
            WatchBridge.shared.sendWorkoutStarted(
                kind: .intervalRun,
                extraInfo: [
                    "sets": totalSets,
                    "lapDistance": lapDistance,
                    "restDuration": restDuration
                ]
            )
            WatchBridge.shared.sendSessionEvent(WorkoutStreamKey.sessionStarted)
            didNotifyStarted = true
        }

        locationManager.startUpdatingLocation()
        startTimer()
        WKInterfaceDevice.current().play(.success)
    }

    private func startResting() {
        pendingRestTransition = false
        phase = .resting
        restRemaining = restDuration
        lapStartDate = Date()
        locationManager.stopUpdatingLocation()
        startTimer()
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
        dismissLapSummary(callCompletion: false)
        let prior: Phase.PriorPhase = phase == .resting ? .resting : .runningLap
        phase = .paused(prior: prior)

        timer?.invalidate()
        hkManager.pauseSession()
        locationManager.stopUpdatingLocation()
        sendSnapshot()
    }

    func resume() {
        guard case .paused(let prior) = phase else { return }

        switch prior {
        case .runningLap:
            phase = .runningLap
            hkManager.resumeSession()
            locationManager.startUpdatingLocation()
        case .resting:
            phase = .resting
            hkManager.resumeSession()
        }
        startTimer()
        sendSnapshot()
    }

    func stop() {
        guard phase != .finished else { return }
        dismissLapSummary(callCompletion: false)
        pendingRestTransition = false
        pendingFinishAfterOverlay = false
        // record in-progress lap
        if case .paused(let prior) = phase {
            switch prior {
            case .runningLap: recordLap(type: .run)
            case .resting: recordLap(type: .rest)
            }
        } else if phase == .runningLap, !currentRunLapAlreadyRecorded {
            recordLap(type: .run)
        } else if phase == .resting {
            recordLap(type: .rest)
        }
        finishWorkout()
    }

    func manualLap() {
        guard phase == .runningLap else { return }
        completeRunLapTransition(isFinalRunLap: currentSet >= totalSets)
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
                self.sendSnapshot()
            case .resting:
                self.elapsed += 1
                self.restRemaining -= 1
                if self.restRemaining <= 3 && self.restRemaining > 0 {
                    WKInterfaceDevice.current().play(.notification)
                }
                if self.restRemaining <= 0 {
                    self.restFinished()
                }
                self.sendSnapshot()
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
            lastRunLapPace = pace
            lastRunLapAvgHeartRate = lapAvgHeartRate
            currentPace = pace
        }
    }

    private var currentRunLapAlreadyRecorded: Bool {
        guard let last = laps.last else { return false }
        return last.type == .run && last.endDate >= lapStartDate
    }

    private func makeRunLapSummary() -> WatchLapSummarySnapshot {
        WatchLapSummarySnapshot(
            totalDistance: totalRunDistance,
            lapDisplayDistance: totalRunDistance,
            avgPace: avgPace,
            lapPace: lastRunLapPace,
            avgHeartRate: avgHeartRate,
            lapHeartRate: lastRunLapAvgHeartRate
        )
    }

    private func completeRunLapTransition(isFinalRunLap: Bool) {
        guard phase == .runningLap else { return }

        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()

        recordLap(type: .run)
        recalcPace()

        pendingRestTransition = !isFinalRunLap
        pendingFinishAfterOverlay = isFinalRunLap

        showLapSummary(makeRunLapSummary()) { [weak self] in
            guard let self, self.phase != .finished else { return }
            if self.pendingFinishAfterOverlay {
                self.pendingFinishAfterOverlay = false
                self.finishWorkout()
            } else if self.pendingRestTransition {
                self.startResting()
            }
        }
    }

    private func finishWorkout() {
        dismissLapSummary(callCompletion: false)
        pendingRestTransition = false
        pendingFinishAfterOverlay = false
        countdownEndsAt = nil
        phase = .finished
  
        timer?.invalidate()
        timer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        locationManager.stopUpdatingLocation()
        hkManager.endSession(
            shouldSave: WatchWorkoutSessionManager.shouldSaveWorkout(
                duration: elapsed,
                distance: totalRunDistance + lapDistanceCurrent
            )
        )
        if didNotifyStarted {
            WatchBridge.shared.sendWorkoutStopped(kind: .intervalRun)
            WatchBridge.shared.sendSessionEvent(WorkoutStreamKey.sessionEnded)
        }

        sendSnapshot()
    }

    // MARK: - Pace

    private func recalcPace() {
        let runDist = totalRunDistance + lapDistanceCurrent
        let runTime = totalRunTime + lapElapsed
        if runDist > 10 {
            avgPace = runTime / (runDist / 1000)
        }
        if lapDistanceCurrent > 10, lapElapsed > 0 {
            lapPace = lapElapsed / (lapDistanceCurrent / 1000)
        } else {
            lapPace = nil
        }
        currentPace = displayedLapPace
        if !lapHeartRateSamples.isEmpty {
            lapAvgHeartRate = lapHeartRateSamples.reduce(0) { $0 + $1.bpm } / Double(lapHeartRateSamples.count)
        } else if phase == .runningLap {
            lapAvgHeartRate = nil
        }
    }

    private var displayedLapPace: TimeInterval? {
        phase == .runningLap ? lapPace : lastRunLapPace
    }

    private var displayedLapAvgHeartRate: Double? {
        phase == .runningLap ? lapAvgHeartRate : lastRunLapAvgHeartRate
    }

    private func captureLapHeartRateSample(_ bpm: Double?) {
        guard phase == .runningLap, let bpm else { return }
        lapHeartRateSamples.append(HeartRateSample(date: Date(), bpm: bpm))
        lapAvgHeartRate = lapHeartRateSamples.reduce(0) { $0 + $1.bpm } / Double(lapHeartRateSamples.count)
    }

    private func showLapSummary(
        _ summary: WatchLapSummarySnapshot,
        duration: TimeInterval = 2.2,
        onDismiss: (() -> Void)? = nil
    ) {
        dismissLapSummary(callCompletion: false)
        currentLapSummary = summary
        WKInterfaceDevice.current().play(.notification)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.currentLapSummary = nil
            self.lapSummaryDismissWorkItem = nil
            onDismiss?()
        }
        lapSummaryDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func dismissLapSummary(callCompletion: Bool) {
        let workItem = lapSummaryDismissWorkItem
        lapSummaryDismissWorkItem = nil
        workItem?.cancel()
        currentLapSummary = nil
        if callCompletion {
            workItem?.perform()
        }
    }

    // MARK: - Snapshot

    private func sendSnapshot() {
        let phaseString: String
        switch phase {
        case .preparing: phaseString = "preparing"
        case .runningLap: phaseString = "running"
        case .resting: phaseString = "running"
        case .paused: phaseString = "paused"
        case .finished: phaseString = "finished"
        }

        let intervalPhaseStr: String?
        switch phase {
        case .runningLap: intervalPhaseStr = "runningLap"
        case .resting: intervalPhaseStr = "resting"
        default: intervalPhaseStr = nil
        }

        let snapshot = WorkoutDataSnapshot(
            elapsed: elapsed,
            totalDistance: totalRunDistance + lapDistanceCurrent,
            avgPace: avgPace,
            currentPace: displayedLapPace,
            heartRate: heartRate,
            avgHeartRate: avgHeartRate,
            segmentPace: displayedLapPace,
            segmentAvgHeartRate: displayedLapAvgHeartRate,
            activeCalories: hkManager.activeCalories,
            currentLatitude: route.last?.latitude,
            currentLongitude: route.last?.longitude,
            phase: phaseString,
            prestartPhase: phase == .preparing ? "countdown" : nil,
            countdownValue: phase == .preparing ? countdown : nil,
            countdownEndsAt: phase == .preparing ? countdownEndsAt?.timeIntervalSince1970 : nil,
            currentSet: currentSet,
            totalSets: totalSets,
            lapDistanceCurrent: lapDistanceCurrent,
            restRemaining: restRemaining,
            intervalPhase: intervalPhaseStr
        )
        hkManager.sendSnapshot(snapshot)
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

    func makeSummaryData() -> WatchWorkoutSummaryData {
        WatchWorkoutSummaryBuilder.interval(
            route: route,
            elapsed: elapsed,
            totalDistance: totalRunDistance + lapDistanceCurrent,
            avgHeartRate: avgHeartRate,
            calories: hkManager.activeCalories,
            laps: laps
        )
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
            self.recalcPace()

            // Auto-complete lap
            if self.lapDistanceCurrent >= self.lapDistance {
                self.completeRunLapTransition(isFinalRunLap: self.currentSet >= self.totalSets)
            }
        }
    }
}

// MARK: - View

struct WatchIntervalRunView: View {

    let sets: Int
    let lapDistance: Double
    let restDuration: TimeInterval
    var skipCountdown: Bool = false

    @StateObject private var session: WatchIntervalSession
    @State private var selection: Int = 1
    @State private var showingAveragePace = false
    @State private var showingAverageHeartRate = false
    var onFinish: (WatchWorkoutSummaryData) -> Void = { _ in }

    init(
        sets: Int,
        lapDistance: Double,
        restDuration: TimeInterval,
        skipCountdown: Bool = false,
        onFinish: @escaping (WatchWorkoutSummaryData) -> Void = { _ in }
    ) {
        self.sets = sets
        self.lapDistance = lapDistance
        self.restDuration = restDuration
        self.skipCountdown = skipCountdown
        self.onFinish = onFinish
        _session = StateObject(wrappedValue: WatchIntervalSession(
            sets: sets, lapDistance: lapDistance, restDuration: restDuration
        ))
    }

    var body: some View {
        Group {
            if session.phase == .preparing {
                ZStack {
                    Color.black.ignoresSafeArea()
                    countdownOverlay
                }
            } else {
                ZStack {
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

                    if let lapSummary = session.currentLapSummary {
                        WatchLapSummaryOverlay(
                            summary: lapSummary,
                            accentColor: RunningLevelManager.shared.accentColor
                        )
                        .zIndex(1)
                    }
                }
            }
        }
        .onAppear { session.beginCountdown(skip: skipCountdown) }
        .onChange(of: session.phase) { _, newPhase in
            guard newPhase == .finished else { return }
            onFinish(session.makeSummaryData())
        }
        .onDisappear { if session.phase != .finished { session.stop() } }
    }

    // MARK: - Interval Header

    private var metricsTab: some View {
        WatchWorkoutDashboardPage(
            topIcon: session.phase == .resting ? "pause.circle.fill" : "repeat",
            topLeading: session.phase == .resting ? "REST" : "CURRENT LAP",
            accentColor: RunningLevelManager.shared.accentColor,
            primaryValue: totalDistText,
            primaryUnit: "KM",
            leftMetricTitle: "TIME",
            leftMetricValue: session.durationText,
            rightMetricTitle: showingAveragePace ? "AVG PACE" : "LAP PACE",
            rightMetricValue: showingAveragePace ? averagePaceText : currentPaceText,
            rightMetricAction: { showingAveragePace.toggle() },
            bottomIcon: showingAverageHeartRate ? "heart.circle.fill" : "heart.fill",
            bottomTint: showingAverageHeartRate ? .pink : .red,
            bottomLabel: showingAverageHeartRate ? "AVERAGE BPM" : "LAP BPM",
            bottomValue: showingAverageHeartRate
                ? hrText(session.avgHeartRate)
                : hrText(session.phase == .runningLap ? session.lapAvgHeartRate : session.lastRunLapAvgHeartRate),
            bottomUnit: "BPM",
            bottomAction: { showingAverageHeartRate.toggle() }
        )
    }

    private var nowPlayingTab: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            NowPlayingView()
        }
    }

    private var totalDistText: String {
        let m = session.totalRunDistance + session.lapDistanceCurrent
        return String(format: "%.2f", m / 1000)
    }

    private func hrText(_ bpm: Double?) -> String {
        guard let bpm else { return "--" }
        return String(format: "%.0f", bpm)
    }

    private var currentPaceText: String {
        session.paceText(session.phase == .runningLap ? session.lapPace ?? session.avgPace : session.lastRunLapPace ?? session.avgPace)
    }

    private var averagePaceText: String {
        session.paceText(session.avgPace ?? session.currentPace)
    }

    private func heartRateProgress(_ bpm: Double?) -> Double? {
        guard let bpm else { return nil }
        return min(max((bpm - 80) / 90, 0), 1)
    }

    // MARK: - Buttons

    private var controlsTab: some View {
        VStack(spacing: 8) {
            Label(session.phase == .resting ? "REST" : "SET \(session.setText)", systemImage: "repeat")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(RunningLevelManager.shared.accentColor)
            Text(session.lapText)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            buttonSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

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
                        .frame(width: 34, height: 34)
                        .background(AppColor.orange, in: Circle())
                }
                .buttonStyle(.plain)

                Button { session.manualLap() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(AppColor.blue, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)
        case .resting:
            Button { session.pause() } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(AppColor.orange, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
        case .paused:
            HStack(spacing: 20) {
                Button { session.resume() } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(AppColor.green, in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    session.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(AppColor.red, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Overlays

    private var countdownOverlay: some View {
        VStack(spacing: 4) {
            Text("\(session.countdown)")
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColor.orange)
                .contentTransition(.numericText())
                .onChange(of: session.countdown) { oldValue, newValue in
                    WKInterfaceDevice.current().play(.click)
                }
            Text("준비하세요")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var pausedBanner: some View {
        Text("일시정지")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppColor.yellow)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.7), in: Capsule())
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 6)
            .allowsHitTesting(false)
    }
}

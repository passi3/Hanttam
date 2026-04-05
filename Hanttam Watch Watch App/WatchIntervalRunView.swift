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
            .assign(to: \.heartRate, on: self)
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
        locationManager.requestWhenInUseAuthorization()
        Task { await hkManager.requestAuthorization() }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] t in
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
        }
    }

    private func finishWorkout() {
        phase = .finished
  
        timer?.invalidate()
        timer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        locationManager.stopUpdatingLocation()
        hkManager.endSession()
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
        guard recentLocations.count >= 2 else { return }
        var d = 0.0
        for i in 0..<recentLocations.count - 1 {
            d += recentLocations[i + 1].distance(from: recentLocations[i])
        }
        guard d > 5 else { return }
        let t = recentLocations.last!.timestamp.timeIntervalSince(recentLocations.first!.timestamp)
        currentPace = t / (d / 1000)
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
            currentPace: currentPace,
            heartRate: heartRate,
            activeCalories: hkManager.activeCalories,
            currentLatitude: route.last?.latitude,
            currentLongitude: route.last?.longitude,
            phase: phaseString,
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
    var skipCountdown: Bool = false

    @StateObject private var session: WatchIntervalSession
    var onClose: () -> Void = {}

    init(
        sets: Int,
        lapDistance: Double,
        restDuration: TimeInterval,
        skipCountdown: Bool = false,
        onClose: @escaping () -> Void = {}
    ) {
        self.sets = sets
        self.lapDistance = lapDistance
        self.restDuration = restDuration
        self.skipCountdown = skipCountdown
        self.onClose = onClose
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
                VStack(spacing: 0) {
                    // 인터벌 상태 헤더 (세트 + 랩/휴식)
                    intervalHeader

                    // 스탯 화면
                    statsGrid

                    Spacer(minLength: 2)

                    // 버튼
                    buttonSection
                }
            }
        }
        .onAppear { session.beginCountdown(skip: skipCountdown) }
        .onDisappear { if session.phase != .finished { session.stop() } }
    }

    // MARK: - Interval Header

    private var intervalHeader: some View {
        HStack(spacing: 8) {
            // 세트
            Label(session.setText, systemImage: "repeat")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.orange)

            Spacer()

            // 랩 진행 or 휴식 카운트다운
            if session.phase == .resting {
                Label("REST \(Int(max(0, session.restRemaining)))s", systemImage: "pause.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.blue)
            } else {
                Text(session.lapText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        VStack(alignment: .center, spacing: 4) {
            // 거리
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(totalDistText)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                Text("km")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            // 시간
            Text(session.durationText)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)

            // 평균 심박 | 평균 페이스
            HStack(spacing: 0) {
                // 평균 심박
                VStack(spacing: 0) {
                    Text("평균 심박")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.gray)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(hrText(session.avgHeartRate))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        Text("bpm")
                            .font(.system(size: 7))
                            .foregroundStyle(.gray)
                    }
                    .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 20)

                // 평균 페이스
                VStack(spacing: 0) {
                    Text("평균 페이스")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.gray)
                    Text(session.paceText(session.avgPace))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var totalDistText: String {
        let m = session.totalRunDistance + session.lapDistanceCurrent
        return String(format: "%.2f", m / 1000)
    }

    private func hrText(_ bpm: Double?) -> String {
        guard let bpm else { return "--" }
        return String(format: "%.0f", bpm)
    }

    private func statRow(label1: String, value1: String,
                         label2: String, value2: String) -> some View {
        HStack(spacing: 0) {
            statCell(label: label1, value: value1)
            Divider()
            statCell(label: label2, value: value2)
        }
        .frame(height: 40)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
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
                    onClose()
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

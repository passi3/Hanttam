//
//  Hanttam_WatchApp.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/1/26.
//

import SwiftUI
internal import HealthKit
import WatchConnectivity
import Combine
import WatchKit

// MARK: - App

@main
struct Hanttam_Watch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchBridge.shared.stageWorkoutConfiguration(workoutConfiguration)
        // 백그라운드에서도 앱을 살려두기 위해 즉시 HK 세션 시작
        Task {
            await WatchWorkoutSessionManager.shared.requestAuthorization()
            WatchWorkoutSessionManager.shared.startSession(with: workoutConfiguration)
        }
    }
}

final class WatchBridge: NSObject, ObservableObject {
    enum WorkoutKind: String {
        case freeRun
        case intervalRun
    }

    struct PendingStartRequest {
        let requestID: String
        let kind: WorkoutKind
        let sets: Int?
        let lapDistance: Double?
        let restDuration: Double?
        let skipCountdown: Bool

        var isReadyForPresentation: Bool {
            switch kind {
            case .freeRun:
                true
            case .intervalRun:
                sets != nil && lapDistance != nil && restDuration != nil
            }
        }
    }

    static let shared = WatchBridge()
    static let workoutStartedNotification = Notification.Name("WatchBridgeWorkoutStarted")
    static let workoutStoppedNotification = Notification.Name("WatchBridgeWorkoutStopped")
    static let workoutLaunchRequestedNotification = Notification.Name("WatchBridgeWorkoutLaunchRequested")
    static let remoteCommandNotification = Notification.Name("WatchBridgeRemoteCommand")

    private enum AppContextKey {
        static let startRequestID = "pendingStartRequestID"
        static let startKind = "pendingStartKind"
        static let startSets = "pendingStartSets"
        static let startLapDistance = "pendingStartLapDistance"
        static let startRestDuration = "pendingStartRestDuration"
        static let voiceAnnouncementsEnabled = "voiceAnnouncementsEnabled"
    }

    var pendingWorkoutConfiguration: HKWorkoutConfiguration?
    private var pendingStartRequest: PendingStartRequest?
    private var consumedStartRequestIDs = Set<String>()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func consumePendingWorkoutConfiguration() -> HKWorkoutConfiguration? {
        let config = pendingWorkoutConfiguration
        pendingWorkoutConfiguration = nil
        return config
    }

    func consumePendingStartRequest() -> PendingStartRequest? {
        guard let request = pendingStartRequest, request.isReadyForPresentation else { return nil }
        guard consumedStartRequestIDs.insert(request.requestID).inserted else {
            pendingStartRequest = nil
            return nil
        }
        pendingStartRequest = nil
        return request
    }

    func stageWorkoutConfiguration(_ configuration: HKWorkoutConfiguration) {
        pendingWorkoutConfiguration = configuration
        let kind = configuration.locationType == .indoor ? WorkoutKind.intervalRun : .freeRun
        if pendingStartRequest == nil || pendingStartRequest?.kind != kind {
            pendingStartRequest = PendingStartRequest(
                requestID: UUID().uuidString,
                kind: kind,
                sets: nil,
                lapDistance: nil,
                restDuration: nil,
                skipCountdown: true
            )
        }
        notifyPendingStartIfReady()
    }

    func applyPendingStartContext(_ context: [String: Any]) {
        applyVoiceAnnouncementPreference(context)

        guard let requestID = context[AppContextKey.startRequestID] as? String,
              let kindRaw = context[AppContextKey.startKind] as? String,
              let kind = WorkoutKind(rawValue: kindRaw) else { return }

        pendingStartRequest = PendingStartRequest(
            requestID: requestID,
            kind: kind,
            sets: context[AppContextKey.startSets] as? Int,
            lapDistance: context[AppContextKey.startLapDistance] as? Double,
            restDuration: context[AppContextKey.startRestDuration] as? Double,
            skipCountdown: true
        )
        notifyPendingStartIfReady()
    }

    private func applyVoiceAnnouncementPreference(_ context: [String: Any]) {
        guard let isEnabled = context[AppContextKey.voiceAnnouncementsEnabled] as? Bool else { return }
        WorkoutVoiceAnnouncementPreferences.isEnabled = isEnabled
    }

    private func notifyPendingStartIfReady() {
        guard let request = pendingStartRequest, request.isReadyForPresentation else { return }
        guard !consumedStartRequestIDs.contains(request.requestID) else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.workoutLaunchRequestedNotification, object: nil)
        }
    }

    func sendWorkoutStarted(kind: WorkoutKind = .freeRun, extraInfo: [String: Any] = [:]) {
        sendWorkoutMessage("started", kind: kind, extraInfo: extraInfo)
    }

    func sendWorkoutStopped(kind: WorkoutKind = .freeRun) {
        sendWorkoutMessage("stopped", kind: kind)
    }

    func sendWorkoutSnapshot(_ snapshot: WorkoutDataSnapshot) {
        guard WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        let message: [String: Any] = [WorkoutStreamKey.snapshot: data]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    func sendSessionEvent(_ event: String) {
        guard WCSession.default.activationState == .activated else { return }
        let message: [String: Any] = [event: true]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    private func sendWorkoutMessage(_ state: String, kind: WorkoutKind, extraInfo: [String: Any] = [:]) {
        guard WCSession.default.activationState == .activated else { return }
        var message: [String: Any] = ["workout": state, "kind": kind.rawValue]
        extraInfo.forEach { message[$0.key] = $0.value }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let command = message[WorkoutStreamKey.command] as? String {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.remoteCommandNotification,
                    object: nil,
                    userInfo: ["command": command]
                )
            }
            return
        }

        if let command = message["command"] as? String, command == "startWorkout" {
            applyPendingStartContext(message)
            return
        }
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        if let command = message["command"] as? String, command == "startWorkout" {
            applyPendingStartContext(message)
            replyHandler(["accepted": true])
            return
        }

        replyHandler([:])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyPendingStartContext(applicationContext)
    }
}

final class WatchWorkoutSessionManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutSessionManager()
    static let minimumWorkoutDurationToSave: TimeInterval = 5
    static let minimumWorkoutDistanceToSave: Double = 50

    @Published var heartRate: Double?
    @Published var avgHeartRate: Double?
    @Published var activeCalories: Double = 0
    @Published var isSessionActive: Bool = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    static func shouldSaveWorkout(duration: TimeInterval, distance: Double) -> Bool {
        duration >= minimumWorkoutDurationToSave && distance >= minimumWorkoutDistanceToSave
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let shareTypes: Set = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]
        let readTypes: Set = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.workoutType()
        ]

        try? await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func startSession(with configuration: HKWorkoutConfiguration? = nil) {
        guard !isSessionActive else { return }

        let config = configuration ?? defaultConfiguration()

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            builder.delegate = self

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { _, _ in }

            self.session = session
            self.builder = builder
            self.isSessionActive = true
        } catch {
            print("[WatchHK] startSession failed: \(error.localizedDescription)")
            WatchBridge.shared.sendSessionEvent(WorkoutStreamKey.sessionError)
        }
    }

    func pauseSession() {
        session?.pause()
    }

    func resumeSession() {
        session?.resume()
    }

    func endSession(shouldSave: Bool = true) {
        session?.end()

        guard let builder else {
            DispatchQueue.main.async {
                self.session = nil
                self.isSessionActive = false
            }
            return
        }

        if !shouldSave {
            builder.discardWorkout()
            DispatchQueue.main.async {
                self.session = nil
                self.builder = nil
                self.isSessionActive = false
            }
            return
        }

        builder.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in
                DispatchQueue.main.async {
                    self?.session = nil
                    self?.builder = nil
                    self?.isSessionActive = false
                }
            }
        }
    }

    func sendSnapshot(_ snapshot: WorkoutDataSnapshot) {
        WatchBridge.shared.sendWorkoutSnapshot(snapshot)
    }

    private func defaultConfiguration() -> HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor
        return config
    }
}

extension WatchWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for sampleType in collectedTypes {
            guard let quantityType = sampleType as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }

            DispatchQueue.main.async {
                switch quantityType {
                case HKQuantityType.quantityType(forIdentifier: .heartRate):
                    let unit = HKUnit.count().unitDivided(by: .minute())
                    if let value = statistics.mostRecentQuantity()?.doubleValue(for: unit) {
                        self.heartRate = value
                    }
                    if let avg = statistics.averageQuantity()?.doubleValue(for: unit) {
                        self.avgHeartRate = avg
                    }

                case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                    let unit = HKUnit.kilocalorie()
                    if let value = statistics.sumQuantity()?.doubleValue(for: unit) {
                        self.activeCalories = value
                    }

                default:
                    break
                }
            }
        }
    }
}

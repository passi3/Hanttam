//
//  WatchBridge.swift
//  Hanttam
//
//  Created by passi on 4/2/26.
//

import WatchConnectivity
import Combine
import Foundation
internal import HealthKit

final class WatchBridge: NSObject, ObservableObject {

    enum WorkoutKind: String {
        case freeRun
        case intervalRun
    }

    enum CollectionState: Equatable {
        case idle
        case requesting(WorkoutKind)
        case collectingOnWatch(WorkoutKind)
        case phoneOnly(WorkoutKind)
    }

    static let shared                             = WatchBridge()
    static let workoutStartedNotification         = Notification.Name("WatchBridgeWorkoutStarted")
    static let workoutStoppedNotification         = Notification.Name("WatchBridgeWorkoutStopped")
    static let workoutLaunchRequestedNotification = Notification.Name("WatchBridgeWorkoutLaunchRequested")
    static let workoutSnapshotNotification        = Notification.Name("WatchBridgeWorkoutSnapshot")
    static let remoteCommandNotification          = Notification.Name("WatchBridgeRemoteCommand")

#if os(iOS)
    struct WatchConnectionInfo {
        let isPaired: Bool
        let isAppInstalled: Bool
        let isReachable: Bool
    }

    private var pendingLevel: UserRunningLevel?
    private var watchStartTimeout: DispatchWorkItem?
    private let healthStore = HKHealthStore()
    @Published private(set) var mirroredSession: HKWorkoutSession?
    @Published private(set) var watchConnectionInfo = WatchConnectionInfo(
        isPaired: false, isAppInstalled: false, isReachable: false
    )
#endif

#if os(watchOS)
    /// `handle(_:workoutConfiguration:)` 에서 받은 설정을 보관.
    /// WatchRunSession / WatchIntervalSession 이 세션 시작 시 소비한다.
    var pendingWorkoutConfiguration: HKWorkoutConfiguration?
#endif

    @Published private(set) var collectionState: CollectionState = .idle
    @Published private(set) var isWatchConnected: Bool = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        updateReachability()
#if os(iOS)
        setupMirroringHandler()
#endif
    }

    private func updateReachability() {
#if os(iOS)
        let session = WCSession.default
        // startWatchApp은 isReachable이 불필요하며 isPaired + isAppInstalled이면 워치 기동 가능
        let connected = session.isPaired && session.isWatchAppInstalled
        if isWatchConnected != connected { isWatchConnected = connected }
        watchConnectionInfo = WatchConnectionInfo(
            isPaired: session.isPaired,
            isAppInstalled: session.isWatchAppInstalled,
            isReachable: session.isReachable
        )
#else
        let connected = WCSession.default.isReachable
        if isWatchConnected != connected { isWatchConnected = connected }
#endif
    }

    // MARK: - Level (iOS → Watch)

#if os(iOS)
    func sendLevel(_ level: UserRunningLevel) {
        guard WCSession.default.isWatchAppInstalled else { return }
        if WCSession.default.activationState == .activated {
            try? WCSession.default.updateApplicationContext(["level": level.rawValue])
        } else {
            pendingLevel = level
        }
    }
#endif

    // MARK: - Workout Mirroring

    func sendWorkoutStarted(kind: WorkoutKind = .freeRun, extraInfo: [String: Any] = [:]) {
        sendWorkoutMessage("started", kind: kind, extraInfo: extraInfo)
    }
    func sendWorkoutStopped(kind: WorkoutKind = .freeRun) { sendWorkoutMessage("stopped", kind: kind) }

    static let workoutActivityType = "com.passi3.hanttam.startWorkout"

#if os(iOS)
    var canStartWorkoutOnWatch: Bool {
        guard WCSession.isSupported() else { return false }
        // startWatchApp does not require active reachability — only app installed
        return WCSession.default.isWatchAppInstalled
    }

    @discardableResult
    func requestWorkoutStartOnWatch(
        kind: WorkoutKind,
        payload: [String: Any] = [:]
    ) -> Bool {
        guard canStartWorkoutOnWatch else {
            collectionState = .phoneOnly(kind)
            return false
        }

        collectionState = .requesting(kind)

        // 15초 타임아웃: 워치 응답이 없으면 phoneOnly로 폴백
        watchStartTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .requesting = self.collectionState else { return }
            self.collectionState = .phoneOnly(kind)
        }
        watchStartTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)

        // Primary path: HKHealthStore.startWatchApp — auto-launches watch app
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = kind == .intervalRun ? .indoor : .outdoor

        healthStore.startWatchApp(with: config) { (success, error) in
            if !success {
                print("[WatchBridge] startWatchApp failed: \(error?.localizedDescription ?? ""), fallback WCSession")
                DispatchQueue.main.async { 
                    WatchBridge.shared.sendStartViaWCSession(kind: kind, payload: payload) 
                }
            } else {
                print("[WatchBridge] startWatchApp succeeded")
                // Watch is running via HK. Send WCSession command only if reachable,
                // but do NOT fall back to phoneOnly — trust HK mirroring to establish.
                DispatchQueue.main.async {
                    if WCSession.default.activationState == .activated,
                       WCSession.default.isReachable {
                        WatchBridge.shared.sendStartViaWCSession(kind: kind, payload: payload)
                    }
                    // If not reachable, watch handle(_:workoutConfiguration:) already fired
                    // and will report back via workoutStartedNotification when running
                }
            }
        }

        return true
    }

    /// WCSession 경로로 startWorkout 커맨드 전송 (폴백 또는 인터벌 파라미터 전달용)
    private func sendStartViaWCSession(kind: WorkoutKind, payload: [String: Any]) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else {
            collectionState = .phoneOnly(kind)
            return
        }
        var message = payload
        message["command"] = "startWorkout"
        message["kind"] = kind.rawValue
        WCSession.default.sendMessage(message) { [weak self] reply in
            guard let self else { return }
            DispatchQueue.main.async {
                let accepted = (reply["accepted"] as? Bool) ?? false
                if !accepted { self.collectionState = .phoneOnly(kind) }
            }
        } errorHandler: { [weak self] _ in
            DispatchQueue.main.async { self?.collectionState = .phoneOnly(kind) }
        }
    }

    func markPhoneOnly(for kind: WorkoutKind) {
        collectionState = .phoneOnly(kind)
    }

    func sendWorkoutCommand(_ command: String) {
        let wcMessage: [String: Any] = [WorkoutStreamKey.command: command]

        // Primary: HK mirrored session (watchOS 10+ / iOS 17+)
        if #available(iOS 17.0, *), let mirroredSession = mirroredSession,
           let data = try? JSONEncoder().encode([WorkoutStreamKey.command: command]) {
            mirroredSession.sendToRemoteWorkoutSession(data: data) { _, error in
                if let error {
                    print("[WatchBridge] sendToRemote failed, fallback WCSession: \(error)")
                }
            }
        }
        
        // Parallel / Fallback: WCSession
        // 운동이 일시정지된 상태 등에서는 HK 채널이 지연되거나 무시될 수 있으므로, 항상 WCSession으로도 명령을 보냅니다.
        DispatchQueue.main.async {
            guard WCSession.default.activationState == .activated,
                  WCSession.default.isReachable else { return }
            WCSession.default.sendMessage(wcMessage, replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: - HK Mirroring Setup

    private func setupMirroringHandler() {
        if #available(iOS 17.0, *) {
            healthStore.workoutSessionMirroringStartHandler = { [weak self] mirroredSession in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.mirroredSession = mirroredSession
                    mirroredSession.delegate = self
                    let kind: WorkoutKind = mirroredSession.workoutConfiguration.locationType == .indoor
                        ? .intervalRun : .freeRun
                    self.watchStartTimeout?.cancel()
                    self.watchStartTimeout = nil
                    self.collectionState = .collectingOnWatch(kind)
                    print("[WatchBridge] mirroredSession received, kind=\(kind)")
                    NotificationCenter.default.post(
                        name: Self.workoutStartedNotification,
                        object: nil,
                        userInfo: ["kind": kind.rawValue]
                    )
                }
            }
        }
    }
#endif

#if os(watchOS)
    /// pendingWorkoutConfiguration 을 소비(한 번만 사용)하고 반환.
    func consumePendingWorkoutConfiguration() -> HKWorkoutConfiguration? {
        let config = pendingWorkoutConfiguration
        pendingWorkoutConfiguration = nil
        return config
    }

    func sendWorkoutSnapshot(_ snapshot: WorkoutDataSnapshot) {
        guard WCSession.default.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
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
        }
    }
#endif

    private func sendWorkoutMessage(_ state: String, kind: WorkoutKind, extraInfo: [String: Any] = [:]) {
        guard WCSession.default.activationState == .activated else { return }
#if os(iOS)
        guard WCSession.default.isWatchAppInstalled else { return }
        var message: [String: Any] = ["workout": state, "kind": kind.rawValue]
        extraInfo.forEach { message[$0.key] = $0.value }
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
#else
        var message: [String: Any] = ["workout": state, "kind": kind.rawValue]
        extraInfo.forEach { message[$0.key] = $0.value }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }
#endif
    }
}

// MARK: - WCSessionDelegate

extension WatchBridge: WCSessionDelegate {

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            self.updateReachability()
        }
        guard activationState == .activated else { return }

#if os(iOS)
        if let level = pendingLevel {
            try? session.updateApplicationContext(["level": level.rawValue])
            pendingLevel = nil
        } else {
            let current = RunningLevelManager.shared.level
            try? session.updateApplicationContext(["level": current.rawValue])
        }
#endif

#if os(watchOS)
        if !session.receivedApplicationContext.isEmpty {
            applyContext(session.receivedApplicationContext)
        } else {
            requestLevelFromPhone(session)
        }
#endif
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.updateReachability()
        }
    }

    // replyHandler 없는 메시지 수신
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // 워치 → 폰: 스냅샷 수신 (WCSession 폴백 경로)
#if os(iOS)
        if let snapshotData = message[WorkoutStreamKey.snapshot] as? Data,
           let snapshot = try? JSONDecoder().decode(WorkoutDataSnapshot.self, from: snapshotData) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.workoutSnapshotNotification,
                    object: nil,
                    userInfo: ["snapshot": snapshot]
                )
            }
            return
        }
        if message[WorkoutStreamKey.sessionStarted] != nil { return }
        if message[WorkoutStreamKey.sessionEnded] != nil {
            DispatchQueue.main.async {
                self.collectionState = .idle
                NotificationCenter.default.post(name: Self.workoutStoppedNotification, object: nil)
            }
            return
        }
        if message[WorkoutStreamKey.sessionError] != nil {
            DispatchQueue.main.async {
                if case .requesting(let kind) = self.collectionState {
                    self.collectionState = .phoneOnly(kind)
                } else if case .collectingOnWatch(let kind) = self.collectionState {
                    self.collectionState = .phoneOnly(kind)
                }
            }
            return
        }
#endif

        // 폰 → 워치: 리모트 커맨드 (WCSession 폴백 경로)
#if os(watchOS)
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
#endif

        if let command = message["command"] as? String, command == "startWorkout" {
#if os(watchOS)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.workoutLaunchRequestedNotification,
                    object: nil,
                    userInfo: message
                )
            }
#endif
            return
        }

        guard let workout = message["workout"] as? String else { return }
        let kind = WorkoutKind(rawValue: (message["kind"] as? String) ?? "") ?? .freeRun
        let name = workout == "started" ? Self.workoutStartedNotification : Self.workoutStoppedNotification
        DispatchQueue.main.async {
#if os(iOS)
            switch workout {
            case "started":
                self.watchStartTimeout?.cancel()
                self.watchStartTimeout = nil
                self.collectionState = .collectingOnWatch(kind)
            case "stopped": self.collectionState = .idle
            default: break
            }
#endif
            var userInfo: [String: Any] = ["kind": kind.rawValue]
            if let sets = message["sets"] as? Int { userInfo["sets"] = sets }
            if let lapDistance = message["lapDistance"] as? Double { userInfo["lapDistance"] = lapDistance }
            if let restDuration = message["restDuration"] as? Double { userInfo["restDuration"] = restDuration }
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        }
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
#if os(watchOS)
        if let command = message["command"] as? String, command == "startWorkout" {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.workoutLaunchRequestedNotification,
                    object: nil,
                    userInfo: message
                )
            }
            replyHandler(["accepted": true])
            return
        }
#endif

#if os(iOS)
        if message["request"] as? String == "level" {
            replyHandler(["level": RunningLevelManager.shared.level.rawValue])
            return
        }
#endif

        replyHandler([:])
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
#if os(watchOS)
        applyContext(applicationContext)
#endif
    }

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let snapshotData = userInfo[WorkoutStreamKey.snapshot] as? Data,
           let snapshot = try? JSONDecoder().decode(WorkoutDataSnapshot.self, from: snapshotData) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.workoutSnapshotNotification,
                    object: nil,
                    userInfo: ["snapshot": snapshot]
                )
            }
        }
    }
#endif

#if os(watchOS)
    private func requestLevelFromPhone(_ session: WCSession) {
        guard session.isReachable else { return }
        session.sendMessage(["request": "level"]) { reply in
            self.applyContext(reply)
        }
    }

    private func applyContext(_ context: [String: Any]) {
        guard let rawValue = context["level"] as? String,
              let level = UserRunningLevel(rawValue: rawValue) else { return }
        DispatchQueue.main.async {
            RunningLevelManager.shared.level = level
        }
    }
#endif
}

// MARK: - HKWorkoutSessionDelegate (iOS — mirrored session events)

#if os(iOS)
extension WatchBridge: HKWorkoutSessionDelegate {

    @available(iOS 17.0, *)
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        guard toState == .ended else { return }
        DispatchQueue.main.async {
            self.mirroredSession = nil
            self.collectionState = .idle
            NotificationCenter.default.post(name: Self.workoutStoppedNotification, object: nil)
        }
    }

    @available(iOS 17.0, *)
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        print("[WatchBridge] Mirrored session error: \(error)")
        DispatchQueue.main.async {
            if case .requesting(let kind) = self.collectionState {
                self.collectionState = .phoneOnly(kind)
            } else if case .collectingOnWatch(let kind) = self.collectionState {
                self.collectionState = .phoneOnly(kind)
            }
            self.mirroredSession = nil
        }
    }

    /// 워치에서 `sendToRemoteWorkoutSession`으로 보낸 GPS·페이스 스냅샷 수신
    @available(iOS 17.0, *)
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for d in data {
            guard let snapshot = try? JSONDecoder().decode(WorkoutDataSnapshot.self, from: d) else { continue }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.workoutSnapshotNotification,
                    object: nil,
                    userInfo: ["snapshot": snapshot]
                )
            }
        }
    }
}
#endif

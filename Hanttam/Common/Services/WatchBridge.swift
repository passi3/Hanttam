//
//  WatchBridge.swift
//  Hanttam
//
//  Created by passi on 4/2/26.
//

import Foundation
import WatchConnectivity
import Combine

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
    
#if os(iOS)
    private var pendingLevel: UserRunningLevel?
#endif
    
    @Published private(set) var collectionState: CollectionState = .idle
    
    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
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
    
    func sendWorkoutStarted(kind: WorkoutKind = .freeRun) { sendWorkoutMessage("started", kind: kind) }
    func sendWorkoutStopped(kind: WorkoutKind = .freeRun) { sendWorkoutMessage("stopped", kind: kind) }
    
#if os(iOS)
    var canStartWorkoutOnWatch: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.isWatchAppInstalled && session.activationState == .activated && session.isReachable
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
        
        var message = payload
        message["command"] = "startWorkout"
        message["kind"] = kind.rawValue
        
        WCSession.default.sendMessage(message) { [weak self] reply in
            guard let self else { return }
            DispatchQueue.main.async {
                let accepted = (reply["accepted"] as? Bool) ?? false
                if !accepted {
                    self.collectionState = .phoneOnly(kind)
                }
            }
        } errorHandler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.collectionState = .phoneOnly(kind)
            }
        }
        
        return true
    }
    
    func markPhoneOnly(for kind: WorkoutKind) {
        collectionState = .phoneOnly(kind)
    }
#endif
    
    private func sendWorkoutMessage(_ state: String, kind: WorkoutKind) {
        guard WCSession.default.activationState == .activated else { return }
#if os(iOS)
        guard WCSession.default.isWatchAppInstalled else { return }
#endif
        WCSession.default.sendMessage(
            ["workout": state, "kind": kind.rawValue],
            replyHandler: nil,
            errorHandler: nil
        )
    }
}

// MARK: - WCSessionDelegate

extension WatchBridge: WCSessionDelegate {
    
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
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
    
    // replyHandler 없는 메시지 수신 (workout 미러링)
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
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
                self.collectionState = .collectingOnWatch(kind)
            case "stopped":
                self.collectionState = .idle
            default:
                break
            }
#endif
            NotificationCenter.default.post(name: name, object: nil, userInfo: ["kind": kind.rawValue])
        }
    }
    
    func session(_ session: WCSession,
                 didReceiveMessage message: [String : Any],
                 replyHandler: @escaping ([String : Any]) -> Void) {
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

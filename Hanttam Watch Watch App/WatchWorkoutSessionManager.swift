//
//  WatchWorkoutSessionManager.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/3/26.
//

import Foundation
internal import HealthKit
import Combine

final class WatchWorkoutSessionManager: NSObject, ObservableObject {

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    @Published var heartRate: Double?
    @Published var avgHeartRate: Double?
    @Published var activeCalories: Double = 0
    @Published var totalDistance: Double = 0
    @Published var isSessionActive: Bool = false
    private var isMirroringReady = false

    override init() {
        super.init()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .runningSpeed)!,
            HKObjectType.quantityType(forIdentifier: .runningStrideLength)!,
            HKObjectType.quantityType(forIdentifier: .runningPower)!,
            HKObjectType.quantityType(forIdentifier: .runningGroundContactTime)!,
            HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation)!,
            HKObjectType.workoutType()
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            return true
        } catch {
            print("[WatchHK] Authorization failed: \(error)")
            return false
        }
    }

    // MARK: - Session Lifecycle

    func startSession(indoor: Bool = false) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = indoor ? .indoor : .outdoor
        startSession(with: configuration)
    }

    func startSession(with configuration: HKWorkoutConfiguration) {
        isMirroringReady = false
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

            session?.delegate = self
            builder?.delegate = self

            let startDate = Date()
            session?.startActivity(with: startDate)
            builder?.beginCollection(withStart: startDate) { [weak self] (success, error) in
                DispatchQueue.main.async {
                    if success {
                        self?.isSessionActive = true
                        self?.startMirroring()
                    } else {
                        print("[WatchHK] beginCollection failed: \(error?.localizedDescription ?? "")")
                    }
                }
            }
        } catch {
            print("[WatchHK] Session creation failed: \(error)")
        }
    }

    private func startMirroring() {
        guard let session else { return }
        if #available(watchOS 10.0, *) {
            session.startMirroringToCompanionDevice { (success, error) in
                DispatchQueue.main.async {
                    if success {
                        print("[WatchHK] Mirroring to companion started")
                        self.isMirroringReady = true
                    } else {
                        print("[WatchHK] Mirroring failed: \(error?.localizedDescription ?? "")")
                    }
                }
            }
        }
    }

    func pauseSession() {
        session?.pause()
    }

    func resumeSession() {
        session?.resume()
    }

    func endSession() {
        isMirroringReady = false
        session?.end()
    }

    // MARK: - Snapshot Sending (HK primary, WCSession fallback)

    func sendSnapshot(_ snapshot: WorkoutDataSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if #available(watchOS 10.0, *), let session, isMirroringReady {
            session.sendToRemoteWorkoutSession(data: data) { _, error in
                if let error {
                    print("[WatchHK] sendToRemote failed, fallback WCSession: \(error)")
                    WCSessionHelper.sendSnapshotData(data)
                }
            }
        } else {
            WCSessionHelper.sendSnapshotData(data)
        }
    }

    // MARK: - Finish & Save

    private func finishWorkout() {
        guard let builder else { return }
        builder.endCollection(withEnd: Date()) { [weak self] (success, error) in
            guard success else {
                print("[WatchHK] endCollection failed: \(error?.localizedDescription ?? "")")
                return
            }
            builder.finishWorkout { (workout, error) in
                DispatchQueue.main.async {
                    self?.isSessionActive = false
                    if let workout {
                        print("[WatchHK] Workout saved: \(workout)")
                    } else {
                        print("[WatchHK] finishWorkout failed: \(error?.localizedDescription ?? "")")
                    }
                }
            }
        }
    }

    // MARK: - Stats Extraction

    private func updateStatistics() {
        guard let builder else { return }

        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let hrStats = builder.statistics(for: hrType) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            if let mostRecent = hrStats.mostRecentQuantity() {
                heartRate = mostRecent.doubleValue(for: unit)
            }
            if let average = hrStats.averageQuantity() {
                avgHeartRate = average.doubleValue(for: unit)
            }
        }

        if let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let calStats = builder.statistics(for: calType) {
            let unit = HKUnit.kilocalorie()
            activeCalories = calStats.sumQuantity()?.doubleValue(for: unit) ?? 0
        }

        if let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
           let distStats = builder.statistics(for: distType) {
            let unit = HKUnit.meter()
            totalDistance = distStats.sumQuantity()?.doubleValue(for: unit) ?? 0
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutSessionManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch toState {
            case .ended:
                self.finishWorkout()
            default:
                break
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        print("[WatchHK] Session error: \(error)")
        DispatchQueue.main.async { [weak self] in
            self?.isSessionActive = false
            let data: [String: Any] = [WorkoutStreamKey.sessionError: error.localizedDescription]
            if WCSessionHelper.isReachable {
                WCSessionHelper.sendMessage(data)
            }
        }
    }

    // Receive pause/resume/stop commands from phone via HK mirroring
    @available(watchOS 10.0, *)
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for d in data {
            guard let dict = try? JSONDecoder().decode([String: String].self, from: d),
                  let command = dict[WorkoutStreamKey.command] else { continue }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: WatchBridge.remoteCommandNotification,
                    object: nil,
                    userInfo: ["command": command]
                )
            }
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // no-op
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatistics()
        }
    }
}

// MARK: - WCSession Helper (avoid circular dep)

private enum WCSessionHelper {
    static var isReachable: Bool {
        guard WCSessionAvailable else { return false }
        return WCSession.default.isReachable
    }

    static func sendMessage(_ message: [String: Any]) {
        guard WCSessionAvailable else { return }
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    static func sendSnapshotData(_ data: Data) {
        guard WCSessionAvailable else { return }
        let message: [String: Any] = [WorkoutStreamKey.snapshot: data]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    private static var WCSessionAvailable: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
    }
}

import WatchConnectivity

//
//  WorkoutStreamProtocol.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import Foundation

struct WorkoutDataSnapshot: Codable {
    var elapsed: TimeInterval
    var totalDistance: Double          // meters
    var avgPace: TimeInterval?        // sec/km
    var currentPace: TimeInterval?    // sec/km
    var heartRate: Double?            // bpm
    var avgHeartRate: Double?         // bpm
    var segmentPace: TimeInterval?    // sec/km
    var segmentAvgHeartRate: Double?  // bpm
    var activeCalories: Double        // kcal
    var currentLatitude: Double?
    var currentLongitude: Double?
    var phase: String                 // "preparing","running","paused","finished"
    var prestartPhase: String?        // "countdown"
    var countdownValue: Int?
    var countdownEndsAt: TimeInterval?
    // 인터벌 전용
    var currentSet: Int?
    var totalSets: Int?
    var lapDistanceCurrent: Double?
    var restRemaining: TimeInterval?
    var intervalPhase: String?        // "runningLap","resting"
}

enum WorkoutStreamKey {
    static let snapshot = "workoutSnapshot"
    static let command = "workoutCommand"
    static let commandPause = "pause"
    static let commandResume = "resume"
    static let commandStop = "stop"
    static let sessionStarted = "sessionStarted"
    static let sessionPaused = "sessionPaused"
    static let sessionEnded = "sessionEnded"
    static let sessionError = "sessionError"
}

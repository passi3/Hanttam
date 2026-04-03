//
//  WorkoutAttributes.swift
//  Hanttam
//
//  Created by passi on 4/2/26.
//

#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

enum WorkoutPhase: String, Codable, Hashable {
    case preparing
    case running
    case paused
    case finished
}

#if canImport(ActivityKit)
struct WorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: WorkoutPhase
        var elapsed: TimeInterval
        var distance: Double
        var avgPace: Double?
        var currentPace: Double?
        var countdown: Int?
    }
}
#endif

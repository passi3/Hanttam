//
//  CalendarWorkoutMO.swift
//  Hanttam
//
//  Created by passi on 3/29/26.
//

import Foundation

struct DailyWorkoutInfo: Identifiable {
    let id           : Date
    let date         : Date
    let totalDistance: Double
    let totalDuration: TimeInterval
    let workoutCount : Int
    
    var intensity: WorkoutIntensity {
        guard workoutCount > 0 else { return .none }
        let distance = totalDistance / 1000
        switch distance {
        case ..<10: return .light
        case ..<21: return .moderate
        case ..<31: return .hard
        default   : return .intense
        }
    }
}

enum WorkoutIntensity: Int, CaseIterable {
    case none     = 0
    case light    = 1
    case moderate = 2
    case hard     = 3
    case intense  = 4
    
    var label: String {
        switch self {
        case .none     : return ""
        case .light    : return "가벼운"
        case .moderate : return "보통"
        case .hard     : return "강한"
        case .intense  : return "고강도"
        }
    }
}

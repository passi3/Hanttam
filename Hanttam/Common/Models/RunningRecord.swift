//
//  RunningRecord.swift
//  Hanttam
//
//  Created by passi on 3/26/26.
//

import Foundation
internal import HealthKit

struct RunningRecord: Hashable {
    let date      : Date
    let endDate   : Date
    let duration  : TimeInterval
    let distance  : Double
    let calories  : Double
    let workout   : HKWorkout?
    let sourceName: String
    let deviceName: String?
    let isIndoor  : Bool
    
    init(date: Date, endDate: Date, duration: TimeInterval, distance: Double, calories: Double, workout: HKWorkout?, sourceName: String, deviceName: String?, isIndoor: Bool = false) {
        self.date = date
        self.endDate = endDate
        self.duration = duration
        self.distance = distance
        self.calories = calories
        self.workout = workout
        self.sourceName = sourceName
        self.deviceName = deviceName
        self.isIndoor = isIndoor
    }

    static func == (lhs: RunningRecord, rhs: RunningRecord) -> Bool {
        lhs.date == rhs.date
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
    }
}

struct DistanceSample {
    let startDate: Date
    let endDate  : Date
    let distance : Double
}

struct HeartRateSample {
    let date: Date
    let bpm : Double
}

struct QuantitySamplePoint {
    let startDate: Date
    let endDate  : Date
    let value    : Double
}

struct AltitudePoint {
    let date     : Date
    let altitude : Double
    let latitude : Double
    let longitude: Double
}

struct DistSplit: Identifiable {
    let id                    : Int
    let pace                  : TimeInterval
    let distance              : Double
    let startDate             : Date
    let endDate               : Date
    var avgHeartRate          : Double?
    var avgCadence            : Double?
    var avgStrideLength       : Double?
    var avgPower              : Double?
    var avgSpeed              : Double?
    var avgGroundContactTime  : Double?
    var avgVerticalOscillation: Double?
    var elevationChange       : Double?     
}

struct IntervalSettings: Codable {
    var sets        : Int
    var lapDistance : Double
    var restDuration: TimeInterval
}

struct IntervalLap: Codable, Identifiable {
    let id       : Int
    let type     : LapType
    let duration : TimeInterval
    let distance : Double
    let startDate: Date
    let endDate  : Date
    var avgPace  : TimeInterval?

    enum LapType: String, Codable {
        case run, rest
    }
}

struct IntervalRecord: Hashable {
    let id           : UUID
    let date         : Date
    let settings     : IntervalSettings
    let laps         : [IntervalLap]
    let totalDistance: Double
    let totalDuration: TimeInterval

    let routeLatitudes : [Double]
    let routeLongitudes: [Double]

    let workout: HKWorkout?          // HealthKit 원본 (삭제용)

    init(id: UUID, date: Date, settings: IntervalSettings, laps: [IntervalLap],
         totalDistance: Double, totalDuration: TimeInterval,
         routeLatitudes: [Double], routeLongitudes: [Double],
         workout: HKWorkout? = nil) {
        self.id              = id
        self.date            = date
        self.settings        = settings
        self.laps            = laps
        self.totalDistance   = totalDistance
        self.totalDuration   = totalDuration
        self.routeLatitudes  = routeLatitudes
        self.routeLongitudes = routeLongitudes
        self.workout         = workout
    }

    static func == (lhs: IntervalRecord, rhs: IntervalRecord) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

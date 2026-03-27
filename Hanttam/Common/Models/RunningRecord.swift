//
//  RunningRecord.swift
//  Hanttam
//
//  Created by passi on 3/26/26.
//

import Foundation
import HealthKit

struct RunningRecord: Hashable {
    let date    : Date
    let endDate : Date
    let duration: TimeInterval
    let distance: Double
    let calories: Double
    let workout : HKWorkout?
}

struct DistanceSample {
    let startDate: Date
    let endDate  : Date
    let distance : Double   //meter
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
    let altitude : Double   //meter
    let latitude : Double
    let longitude: Double
}

struct KmSplit: Identifiable {
    let id                    : Int
    let pace                  : TimeInterval
    let distance              : Double
    let startDate             : Date
    let endDate               : Date
    var avgHeartRate          : Double?     //bpm
    var avgCadence            : Double?     //spm
    var avgStrideLength       : Double?     //meter
    var avgPower              : Double?     //W
    var avgSpeed              : Double?     //mps
    var avgGroundContactTime  : Double?     //mps
    var avgVerticalOscillation: Double?     //meter
    var elevationChange       : Double?     //meter
}


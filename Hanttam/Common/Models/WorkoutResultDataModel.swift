//
//  WorkoutResultDataModel.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import Foundation
import CoreLocation
internal import HealthKit

struct WorkoutResultDataModel {
    let startDate: Date
    let endDate: Date
    let totalDistance: Double        // 미터
    let totalDuration: TimeInterval
    let avgPace: TimeInterval?      // 초/km
    let calories: Double?
    let splits: [SplitData]
    let routeCoordinates: [(lat: Double, lng: Double)]
    let routeLocations: [CLLocation]
    let workout: HKWorkout?
    var isIndoor: Bool = false
    var alreadySaved: Bool = false   // 인터벌 등 이미 저장된 경우

    struct SplitData {
        let km: Int
        let pace: TimeInterval       // 초/km
        let distance: Double          // 미터 (마지막 불완전 km < 1000)
    }
}

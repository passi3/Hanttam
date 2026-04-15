//
//  RunDetailLapRow.swift
//  Hanttam
//

import Foundation

struct RunDetailLapRow: Identifiable {
    let id: Int
    let label: String
    let pace: TimeInterval
    let distance: Double
    let startDate: Date
    let endDate: Date
    var avgHeartRate: Double?
    var elevationChange: Double?
}

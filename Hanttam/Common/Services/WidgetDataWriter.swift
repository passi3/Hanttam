//
//  WidgetDataWriter.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import Foundation

enum WidgetDataWriter {

    private static let suiteName = "group.com.passi3.hanttam"

    private static var shared: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func writeMonthlyData(thisMonthKm: Double, lastMonthKm: Double) {
        guard let defaults = shared else { return }
        defaults.set(thisMonthKm, forKey: "widget_thisMonthKm")
        defaults.set(lastMonthKm, forKey: "widget_lastMonthKm")
        defaults.set(Date().timeIntervalSince1970, forKey: "widget_lastUpdated")
    }
}

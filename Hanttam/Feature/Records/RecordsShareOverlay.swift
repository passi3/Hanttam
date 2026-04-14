//
//  RecordsShareOverlay.swift
//  Hanttam
//

import SwiftUI

struct RecordsShareOverlay: View {
    let period      : ChartPeriod
    let offset      : Int
    let chartRecords: [RunningRecord]
    let totalDistance: Double
    let totalRuns   : Int

    @Environment(\.overlayTextColor) private var textColor
    @Environment(\.overlaySubTextColor) private var subTextColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) { }
            RunningChartShareView(records: chartRecords, period: period, offset: offset)
        }
    }

    private func summaryLabel(value: String, unit: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 28, weight: .bold, design: .monospaced)).foregroundStyle(textColor)
                Text(unit).font(.caption).foregroundStyle(subTextColor)
            }
            Text(caption).font(.caption2).foregroundStyle(subTextColor)
        }
    }
}

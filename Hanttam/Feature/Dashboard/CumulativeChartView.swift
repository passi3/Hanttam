//
//  CumulativeChartView.swift
//  Hanttam
//
//  Created by passi on 3/29/26.
//

import SwiftUI
import Charts

struct CumulativeChartView: View {
    let thisMonthDist : [DailyCumulativeDistance]
    let lastMonthDist : [DailyCumulativeDistance]
    let thisMonthTotal: Double
    let lastMonthTotal: Double
    let accentColor   : Color
    
    @State private var rawSelectedDay: Int?
    
    private let today = Calendar.current.component(.day, from: Date())
    
    private var selectedDay: Int? {
        guard let raw = rawSelectedDay, raw >= 1, raw <= today else { return nil }
        return raw
    }
    
    
    private let neutralGray = AppColor.dashboardNeutral
    private let labelGray   = AppColor.dashboardLabel
    private let textDark    = AppColor.dashboardTextDark
    
    private var diff    : Double { thisMonthTotal - lastMonthTotal }
    private var diffSign: String { diff >= 0 ? "+" : "" }
    
    private var thisMonthName: String {
        AppFormatter.monthKo.string(from: Date())
    }
    
    private var lastMonthName: String {
        let date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return AppFormatter.monthKo.string(from: date)
    }
    
    //MARK: - Selected day data
    
    private var selectedThisDist: Double? {
        guard let day = selectedDay else { return nil }
        return thisMonthDist.first(where: { $0.day == day })?.cumulativeDistance
    }
    
    private var selectedLastDist: Double? {
        guard let day = selectedDay else { return nil }
        return lastMonthDist.first(where: { $0.day == day })?.cumulativeDistance
    }
    
    private var selectedDiff: Double? {
        guard let t = selectedThisDist, let l = selectedLastDist else { return nil }
        return t - l
    }
    
    //MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            headerSection
            
            chart
                .chartXSelection(value: $rawSelectedDay)
            if let day = selectedDay {
                tooltipView(day: day)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            HStack(spacing: 20) {
                legendItem(color: accentColor, label: thisMonthName)
                legendItem(color: neutralGray, label: lastMonthName)
            }
        }
        .padding(32)
        .background(AppColor.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 1.75, y: 1)
        .animation(.easeOut(duration: 0.15), value: rawSelectedDay)
    }
    
    //MARK: - Header
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("월별 누적 거리")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1)
                .foregroundStyle(labelGray)
            
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(String(format: "%.1f", thisMonthTotal))
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(textDark)
                    .tracking(-0.9)
                
                Text("KM")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(labelGray)
                
                Spacer()
                
                Text(String(format: "%@%.1fkm", diffSign, diff))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(diff >= 0 ? accentColor : AppColor.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(diff >= 0 ? accentColor.opacity(0.1) : AppColor.red.opacity(0.1))
                    )
            }
        }
    }
    
    //MARK: - Chart
    private var chart: some View {
        Chart {
            //지난달
            ForEach(lastMonthDist, id: \.day) { point in
                LineMark (
                    x: .value("Day", point.day),
                    y: .value("Km", point.cumulativeDistance),
                    series: .value("Month", "지난달")
                )
                .foregroundStyle(neutralGray)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }
            
            //이번달
            ForEach(thisMonthDist.filter { $0.day <= today }, id: \.day) { point in
            LineMark(
                x: .value("Day", point.day),
                y: .value("Km", point.cumulativeDistance),
                series: .value("Month", "이번달")
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [accentColor.opacity(0.5), accentColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .lineStyle(StrokeStyle(
                lineWidth: 3,
                                   lineCap: .round))
            }
            
            //이번달 끝점
            if selectedDay == nil, let last = thisMonthDist.filter({ $0.day <= today }).last(where: { $0.cumulativeDistance > 0 }) {
                PointMark(
                    x: .value("Day", last.day),
                    y: .value("Km", last.cumulativeDistance)
                )
                .foregroundStyle(accentColor)
                .symbolSize(40)
            }
            
            //선택 룰마크 + 포인트
            if let day = selectedDay {
                RuleMark(x: .value("Day", day))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(labelGray.opacity(0.4))
                
                if let thisDistance = selectedThisDist {
                    PointMark(x: .value("Day", day), y: .value("Km", thisDistance))
                        .foregroundStyle(accentColor)
                        .symbolSize(50)
                }
                
                if let lastDistance = selectedLastDist {
                    PointMark(x: .value("Day", day), y: .value("Km", lastDistance))
                        .foregroundStyle(neutralGray)
                        .symbolSize(50)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 5)) { value in
                AxisValueLabel {
                    if let day = value.as(Int.self) {
                        Text("\(day)일")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(labelGray)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(AppColor.separator.opacity(0.2))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let km = value.as(Double.self) {
                        Text(String(format: "%.0f", km))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(labelGray)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(AppColor.separator.opacity(0.2))
            }
        }
        .chartLegend(.hidden)
        .frame(height: 192)
    }
    
    //MARK: - Tooltip
    
    private func tooltipView(day: Int) -> some View {
        let thisDistance = selectedThisDist ?? 0
        let lastDistance = selectedLastDist ?? 0
        let dayDiff = thisDistance - lastDistance
        let dayDiffSign = dayDiff >= 0 ? "+" : ""

        return HStack(spacing: 0) {
            // 일자
            VStack(alignment: .leading, spacing: 2) {
                Text("\(day)일")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(textDark)
                Text("누적 비교")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(labelGray)
            }
            .frame(width: 56, alignment: .leading)

            // 이번달
            VStack(alignment: .leading, spacing: 2) {
                Text(thisMonthName)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(accentColor)
                Text(String(format: "%.1fkm", thisDistance))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(textDark)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 지난달
            VStack(alignment: .leading, spacing: 2) {
                Text(lastMonthName)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(labelGray)
                Text(String(format: "%.1fkm", lastDistance))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(textDark)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 차이
            Text(String(format: "%@%.1f", dayDiffSign, dayDiff))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(dayDiff >= 0 ? accentColor : AppColor.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(dayDiff >= 0 ? accentColor.opacity(0.1) : AppColor.textTertiary.opacity(0.1))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColor.dashboardTooltipBg)
        )
    }
    
    // MARK: - Legend

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(labelGray)
        }
    }
}

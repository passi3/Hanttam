//
//  RunningChartView.swift
//  Hanttam
//
//  Created by passi on 3/31/26.
//

import SwiftUI
import Charts
import Combine

// MARK: - Chart Period

enum ChartPeriod: String, CaseIterable {
    case weekly  = "주"
    case monthly = "월"
    case yearly  = "연"
    case all     = "전체"
}

// MARK: - Chart Data

private struct ChartDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let date: Date
    let distance: Double
}

// MARK: - Chart View

struct RunningChartView: View {

    @ObservedObject var store: RecordsViewModel
    @State private var selectedLabel: String?

    private var period: ChartPeriod { store.period }
    private var offset: Int { store.offset }

    private var dataPoints: [ChartDataPoint] {
        switch period {
        case .weekly:  return aggregateWeek(offset: offset)
        case .monthly: return aggregateMonth(offset: offset)
        case .yearly:  return aggregateYear(offset: offset)
        case .all:     return aggregateYears()
        }
    }

    private var selectedPoint: ChartDataPoint? {
        guard let label = selectedLabel else { return nil }
        return dataPoints.first { $0.label == label }
    }

    private var totalDistance: Double {
        dataPoints.reduce(0) { $0 + $1.distance }
    }

    // MARK: - 헤더 텍스트

    private var periodTitle: String {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .weekly:
            let today = cal.startOfDay(for: now)
            let weekday = cal.component(.weekday, from: today)
            let daysFromMonday = (weekday + 5) % 7
            let currentMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: today)!
            let monday = cal.date(byAdding: .weekOfYear, value: offset, to: currentMonday)!
            let sunday = cal.date(byAdding: .day, value: 6, to: monday)!
            return "\(AppFormatter.monthDay.string(from: monday)) ~ \(AppFormatter.monthDay.string(from: sunday))"
        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: now)
            guard let base = cal.date(from: comps),
                  let target = cal.date(byAdding: .month, value: offset, to: base) else { return "" }
            return AppFormatter.yearMonth.string(from: target)
        case .yearly:
            let year = cal.component(.year, from: now) + offset
            return "\(year)년"
        case .all:
            return "전체"
        }
    }

    // MARK: - 이전/다음 가능 여부

    private var canGoBack: Bool {
        guard !store.records.isEmpty else { return false }
        let earliest = store.records.map(\.date).min()!
        let cal = Calendar.current
        let now = Date()

        switch period {
        case .weekly:
            let today = cal.startOfDay(for: now)
            let weekday = cal.component(.weekday, from: today)
            let daysFromMonday = (weekday + 5) % 7
            let currentMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: today)!
            let targetMonday = cal.date(byAdding: .weekOfYear, value: offset - 1, to: currentMonday)!
            return earliest < cal.date(byAdding: .day, value: 7, to: targetMonday)!
        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: now)
            let base = cal.date(from: comps)!
            let target = cal.date(byAdding: .month, value: offset - 1, to: base)!
            let targetEnd = cal.date(byAdding: .month, value: 1, to: target)!
            return earliest < targetEnd
        case .yearly:
            let targetYear = cal.component(.year, from: now) + offset - 1
            let earliestYear = cal.component(.year, from: earliest)
            return targetYear >= earliestYear
        case .all:
            return false
        }
    }

    private var canGoForward: Bool {
        offset < 0
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 기간 선택
            Picker("기간", selection: $store.period) {
                ForEach(ChartPeriod.allCases, id: \.self) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: store.period) { _, _ in
                store.offset = 0
                selectedLabel = nil
            }

            // 기간 표시
            if period != .all {
                Text(periodTitle)
                    .font(.system(size: 14, weight: .medium))
                    .contentTransition(.numericText())
            }

            // 요약
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f km", selectedPoint?.distance ?? totalDistance))
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.2), value: selectedLabel)
                Text(selectedPoint?.label ?? "총 거리")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 차트
            Chart(dataPoints) { point in
                BarMark(
                    x: .value("기간", point.label),
                    y: .value("거리", point.distance)
                )
                .foregroundStyle(
                    selectedLabel == nil || selectedLabel == point.label
                        ? RunningLevelManager.shared.accentColor
                        : RunningLevelManager.shared.accentColor.opacity(0.3)
                )
                .cornerRadius(4)
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let x = location.x - geo[proxy.plotFrame!].origin.x
                            if let label: String = proxy.value(atX: x) {
                                withAnimation(.spring(duration: 0.2)) {
                                    selectedLabel = (selectedLabel == label) ? nil : label
                                }
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 30)
                                .onEnded { value in
                                    let horizontal = value.translation.width
                                    if horizontal < -30 && canGoForward {
                                        withAnimation(.spring(duration: 0.3)) { store.offset += 1 }
                                        selectedLabel = nil
                                    } else if horizontal > 30 && canGoBack {
                                        withAnimation(.spring(duration: 0.3)) { store.offset -= 1 }
                                        selectedLabel = nil
                                    }
                                }
                        )
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    if period == .monthly {
                        let label = value.as(String.self) ?? ""
                        if monthlyVisibleLabels.contains(label) {
                            AxisValueLabel { Text(label).font(.caption2) }
                        } else {
                            AxisValueLabel { Text("") }
                        }
                    } else {
                        AxisValueLabel()
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let km = value.as(Double.self) {
                            Text(String(format: "%.0f", km))
                                .font(.caption2.monospacedDigit())
                                .frame(minWidth: 28, alignment: .trailing)
                        }
                    }
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick()
                }
            }
            .chartPlotBorderStyle(borderColor: AppColor.separator.opacity(0.9))
            .frame(height: 160)
            .animation(.spring(duration: 0.3), value: offset)
        }
        .padding(20)
    }

    // MARK: - 월별 X축 라벨

    private var monthlyVisibleLabels: Set<String> {
        let cal         = Calendar.current
        let now         = Date()
        let comps       = cal.dateComponents([.year, .month], from: now)
        let baseMonth   = cal.date(from: comps)!
        let targetMonth = cal.date(byAdding: .month, value: offset, to: baseMonth)!
        let daysInMonth = cal.range(of: .day, in: .month, for: targetMonth)!.count
        return ["1", "15", "\(daysInMonth)"]
    }

    // MARK: - 주별

    private func aggregateWeek(offset: Int) -> [ChartDataPoint] {
        let cal            = Calendar.current
        let today          = cal.startOfDay(for: Date())

        let weekday        = cal.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let currentMonday  = cal.date(byAdding: .day, value: -daysFromMonday, to: today)!
        let monday         = cal.date(byAdding: .weekOfYear, value: offset, to: currentMonday)!
        let sunday         = cal.date(byAdding: .day, value: 7, to: monday)!

        let dayNames = ["월", "화", "수", "목", "금", "토", "일"]
        var distMap: [Int: Double] = [:]
        for i in 0..<7 { distMap[i] = 0 }

        for record in store.records {
            let recordDay = cal.startOfDay(for: record.date)
            guard recordDay >= monday && recordDay < sunday else { continue }
            let diff = cal.dateComponents([.day], from: monday, to: recordDay).day ?? -1
            if diff >= 0 && diff < 7 {
                distMap[diff, default: 0] += record.distance / 1000
            }
        }

        return (0..<7).map { i in
            let date = cal.date(byAdding: .day, value: i, to: monday)!
            return ChartDataPoint(label: dayNames[i], date: date, distance: distMap[i] ?? 0)
        }
    }

    // MARK: - 월별

    private func aggregateMonth(offset: Int) -> [ChartDataPoint] {
        let cal = Calendar.current
        let now = Date()

        let comps = cal.dateComponents([.year, .month], from: now)
        let baseMonth = cal.date(from: comps)!
        let targetMonth = cal.date(byAdding: .month, value: offset, to: baseMonth)!
        let nextMonth = cal.date(byAdding: .month, value: 1, to: targetMonth)!

        let year = cal.component(.year, from: targetMonth)
        let month = cal.component(.month, from: targetMonth)
        let daysInMonth = cal.range(of: .day, in: .month, for: targetMonth)!.count

        let maxDay = daysInMonth

        var distMap: [Int: Double] = [:]
        for d in 1...maxDay { distMap[d] = 0 }

        for record in store.records {
            guard record.date >= targetMonth && record.date < nextMonth else { continue }
            let d = cal.component(.day, from: record.date)
            if d <= maxDay {
                distMap[d, default: 0] += record.distance / 1000
            }
        }

        return (1...maxDay).map { d in
            ChartDataPoint(label: "\(d)", date: targetMonth, distance: distMap[d] ?? 0)
        }
    }

    // MARK: - 연도별

    private func aggregateYear(offset: Int) -> [ChartDataPoint] {
        let cal = Calendar.current
        let now = Date()
        let targetYear = cal.component(.year, from: now) + offset

        let maxMonth = 12

        var distMap: [Int: Double] = [:]
        for m in 1...maxMonth { distMap[m] = 0 }

        for record in store.records {
            guard cal.component(.year, from: record.date) == targetYear else { continue }
            let m = cal.component(.month, from: record.date)
            if m <= maxMonth {
                distMap[m, default: 0] += record.distance / 1000
            }
        }

        return (1...maxMonth).map { m in
            ChartDataPoint(label: "\(m)월", date: now, distance: distMap[m] ?? 0)
        }
    }

    // MARK: - 전체

    private func aggregateYears() -> [ChartDataPoint] {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())

        var yearSet = Set<Int>([currentYear])
        for record in store.records {
            let y = cal.component(.year, from: record.date)
            if y <= currentYear { yearSet.insert(y) }
        }
        let years = yearSet.sorted()

        var distMap: [Int: Double] = [:]
        for y in years { distMap[y] = 0 }

        for record in store.records {
            let y = cal.component(.year, from: record.date)
            if distMap[y] != nil { distMap[y]! += record.distance / 1000 }
        }

        return years.map { y in
            ChartDataPoint(label: "\(y)", date: Date(), distance: distMap[y] ?? 0)
        }
    }
}

// MARK: - Chart Share View (picker 없는 공유 전용)

struct RunningChartShareView: View {

    let records: [RunningRecord]
    let period: ChartPeriod
    let offset: Int

    @Environment(\.overlayTextColor) private var textColor
    @Environment(\.overlaySubTextColor) private var subTextColor

    private var dataPoints: [ChartDataPoint] {
        switch period {
        case .weekly:  return aggregateWeek(offset: offset)
        case .monthly: return aggregateMonth(offset: offset)
        case .yearly:  return aggregateYear(offset: offset)
        case .all:     return aggregateYears()
        }
    }

    private var totalDistance: Double {
        dataPoints.reduce(0) { $0 + $1.distance }
    }

    private var periodTitle: String {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .weekly:
            let today = cal.startOfDay(for: now)
            let weekday = cal.component(.weekday, from: today)
            let daysFromMonday = (weekday + 5) % 7
            let currentMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: today)!
            let monday = cal.date(byAdding: .weekOfYear, value: offset, to: currentMonday)!
            let sunday = cal.date(byAdding: .day, value: 6, to: monday)!
            return "\(AppFormatter.monthDay.string(from: monday)) ~ \(AppFormatter.monthDay.string(from: sunday))"
        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: now)
            guard let base = cal.date(from: comps),
                  let target = cal.date(byAdding: .month, value: offset, to: base) else { return "" }
            return AppFormatter.yearMonth.string(from: target)
        case .yearly:
            return "\(cal.component(.year, from: now) + offset)년"
        case .all:
            return "전체"
        }
    }

    private var monthlyVisibleLabels: Set<String> {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        let base = cal.date(from: comps)!
        let target = cal.date(byAdding: .month, value: offset, to: base)!
        let days = cal.range(of: .day, in: .month, for: target)!.count
        return ["1", "15", "\(days)"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if period != .all {
                Text(periodTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(subTextColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f km", totalDistance))
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundStyle(textColor)
                Text("총 거리")
                    .font(.caption)
                    .foregroundStyle(subTextColor)
            }
            Chart(dataPoints) { point in
                BarMark(
                    x: .value("기간", point.label),
                    y: .value("거리", point.distance)
                )
                .foregroundStyle(RunningLevelManager.shared.accentColor)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks { value in
                    if period == .monthly {
                        let label = value.as(String.self) ?? ""
                        if monthlyVisibleLabels.contains(label) {
                            AxisValueLabel { Text(label).font(.caption2).foregroundStyle(subTextColor) }
                        } else {
                            AxisValueLabel { Text("") }
                        }
                    } else {
                        AxisValueLabel { Text(value.as(String.self) ?? "").font(.caption2).foregroundStyle(subTextColor) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let km = value.as(Double.self) {
                            Text(String(format: "%.0f", km))
                                .font(.caption2.monospacedDigit())
                                .frame(minWidth: 28, alignment: .trailing)
                                .foregroundStyle(subTextColor)
                        }
                    }
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick()
                }
            }
            .chartPlotBorderStyle(borderColor: subTextColor.opacity(0.35))
            .frame(height: 160)
        }
    }

    // MARK: - Aggregate

    private func aggregateWeek(offset: Int) -> [ChartDataPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let currentMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: today)!
        let monday = cal.date(byAdding: .weekOfYear, value: offset, to: currentMonday)!
        let sunday = cal.date(byAdding: .day, value: 7, to: monday)!
        let dayNames = ["월", "화", "수", "목", "금", "토", "일"]
        var distMap: [Int: Double] = [:]; for i in 0..<7 { distMap[i] = 0 }
        for record in records {
            let recordDay = cal.startOfDay(for: record.date)
            guard recordDay >= monday && recordDay < sunday else { continue }
            let diff = cal.dateComponents([.day], from: monday, to: recordDay).day ?? -1
            if diff >= 0 && diff < 7 { distMap[diff, default: 0] += record.distance / 1000 }
        }
        return (0..<7).map { i in
            ChartDataPoint(label: dayNames[i], date: cal.date(byAdding: .day, value: i, to: monday)!, distance: distMap[i] ?? 0)
        }
    }

    private func aggregateMonth(offset: Int) -> [ChartDataPoint] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        let baseMonth = cal.date(from: comps)!
        let targetMonth = cal.date(byAdding: .month, value: offset, to: baseMonth)!
        let nextMonth = cal.date(byAdding: .month, value: 1, to: targetMonth)!
        let daysInMonth = cal.range(of: .day, in: .month, for: targetMonth)!.count
        var distMap: [Int: Double] = [:]; for d in 1...daysInMonth { distMap[d] = 0 }
        for record in records {
            guard record.date >= targetMonth && record.date < nextMonth else { continue }
            let d = cal.component(.day, from: record.date)
            if d <= daysInMonth { distMap[d, default: 0] += record.distance / 1000 }
        }
        return (1...daysInMonth).map { d in
            ChartDataPoint(label: "\(d)", date: targetMonth, distance: distMap[d] ?? 0)
        }
    }

    private func aggregateYear(offset: Int) -> [ChartDataPoint] {
        let cal = Calendar.current
        let targetYear = cal.component(.year, from: Date()) + offset
        var distMap: [Int: Double] = [:]; for m in 1...12 { distMap[m] = 0 }
        for record in records {
            guard cal.component(.year, from: record.date) == targetYear else { continue }
            let m = cal.component(.month, from: record.date)
            distMap[m, default: 0] += record.distance / 1000
        }
        return (1...12).map { m in ChartDataPoint(label: "\(m)월", date: Date(), distance: distMap[m] ?? 0) }
    }

    private func aggregateYears() -> [ChartDataPoint] {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())
        var yearSet = Set<Int>([currentYear])
        for record in records { yearSet.insert(cal.component(.year, from: record.date)) }
        let years = yearSet.sorted()
        var distMap: [Int: Double] = [:]; for y in years { distMap[y] = 0 }
        for record in records {
            let y = cal.component(.year, from: record.date)
            if distMap[y] != nil { distMap[y]! += record.distance / 1000 }
        }
        return years.map { y in ChartDataPoint(label: "\(y)", date: Date(), distance: distMap[y] ?? 0) }
    }
}

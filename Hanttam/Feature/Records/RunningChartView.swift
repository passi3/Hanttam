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
    let count: Int
}

// MARK: - Chart View

struct RunningChartView: View {

    @ObservedObject var store: RecordsViewModel
    @State private var selectedLabel: String?
    @State private var showDatePicker = false
    @State private var pickerYear: Int = Calendar.current.component(.year, from: Date())
    @State private var pickerMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var preDragSelectedLabel: String?
    @State private var longPressTimer: DispatchWorkItem?
    @State private var isLongPressed: Bool = false
    @State private var longPressStartX: CGFloat = 0

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

    private var displayedCount: Int {
        if let label = selectedLabel { return dataPoints.first { $0.label == label }?.count ?? 0 }
        return dataPoints.reduce(0) { $0 + $1.count }
    }

    private var yAxisValues: [Double] {
        let maxVal = dataPoints.map(\.distance).max() ?? 0
        guard maxVal > 0 else { return [0] }
        let ceiling = (maxVal / 5).rounded(.up) * 5
        return [ceiling / 3, ceiling * 2 / 3, ceiling]
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
            .onChange(of: selectedLabel) { _, newLabel in
                store.selectedChartLabel = newLabel
            }

            // 기간 표시
            if period != .all {
                if period == .monthly || period == .yearly {
                    Button {
                        syncPickerToCurrentOffset()
                        showDatePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(periodTitle)
                                .font(.system(size: 14, weight: .medium))
                                .contentTransition(.numericText())
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Color.black)
                    }
                } else {
                    Text(periodTitle)
                        .font(.system(size: 14, weight: .medium))
                        .contentTransition(.numericText())
                }
            }

            // 요약
            HStack(alignment: .center) {
                VStack(alignment: .leading) {
                    Text("총 거리")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fkm", selectedPoint?.distance ?? totalDistance))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.2), value: selectedLabel)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("총 워크아웃")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(displayedCount)번")
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        // .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.2), value: selectedLabel)
                }
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
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x - geo[proxy.plotFrame!].origin.x

                                    // 최초 터치: 롱프레스 타이머 시작
                                    if longPressTimer == nil && !isLongPressed {
                                        longPressStartX = x
                                        let work = DispatchWorkItem {
                                            isLongPressed = true
                                            preDragSelectedLabel = selectedLabel
                                            if let label: String = proxy.value(atX: longPressStartX),
                                               dataPoints.first(where: { $0.label == label })?.distance ?? 0 > 0 {
                                                selectedLabel = label
                                                preDragSelectedLabel = label
                                            }
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        }
                                        longPressTimer = work
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                                    }

                                    // 롱프레스 미활성 상태에서 이동이 크면 스와이프 의도 → 타이머 취소
                                    let moved = hypot(value.translation.width, value.translation.height)
                                    if !isLongPressed && moved >= 15 {
                                        longPressTimer?.cancel()
                                        longPressTimer = nil
                                    }

                                    // 롱프레스 활성 상태: 드래그로 바 이동
                                    if isLongPressed {
                                        if let label: String = proxy.value(atX: x),
                                           dataPoints.first(where: { $0.label == label })?.distance ?? 0 > 0 {
                                            selectedLabel = label
                                            preDragSelectedLabel = label
                                        }
                                    }
                                }
                                .onEnded { value in
                                    let wasLongPressed = isLongPressed
                                    defer { cancelLongPress(); preDragSelectedLabel = nil }

                                    // 롱프레스 해제: selectedLabel 유지
                                    guard !wasLongPressed else { return }

                                    // 일반 모드: 스와이프 또는 탭
                                    let dx = value.translation.width
                                    if dx < -30 && canGoForward {
                                        withAnimation(.spring(duration: 0.3)) { store.offset += 1 }
                                        selectedLabel = nil
                                    } else if dx > 30 && canGoBack {
                                        withAnimation(.spring(duration: 0.3)) { store.offset -= 1 }
                                        selectedLabel = nil
                                    } else if abs(value.translation.width) + abs(value.translation.height) < 10 {
                                        let x = value.location.x - geo[proxy.plotFrame!].origin.x
                                        if let label: String = proxy.value(atX: x),
                                           dataPoints.first(where: { $0.label == label })?.distance ?? 0 > 0 {
                                            withAnimation(.spring(duration: 0.2)) {
                                                selectedLabel = (selectedLabel == label) ? nil : label
                                            }
                                        }
                                    }
                                }
                        )
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    let label = value.as(String.self) ?? ""
                    switch period {
                    case .monthly:
                        if let day = Int(label), (day - 1) % 7 == 0 {
                            AxisValueLabel { Text(label).font(.caption2) }
                            AxisGridLine()
                        }
                    default:
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: yAxisValues) { value in
                    AxisValueLabel {
                        if let km = value.as(Double.self) {
                            Text(String(format: "%.0f", km))
                                .font(.caption2.monospacedDigit())
                                .frame(minWidth: 28, alignment: .trailing)
                        }
                    }
                    AxisGridLine()
                    AxisTick()
                }
            }
            .chartPlotBorderStyle(borderColor: AppColor.separator.opacity(0.9))
            .frame(height: 160)
            .animation(.spring(duration: 0.3), value: offset)
        }
        .padding(20)
        .sheet(isPresented: $showDatePicker) {
            PeriodPickerSheet(period: period, year: $pickerYear, month: $pickerMonth) {
                applyPicker()
                showDatePicker = false
            } onCancel: {
                showDatePicker = false
            }
            .presentationDetents([.height(300)])
        }
    }

    // MARK: - Long Press Helpers

    private func cancelLongPress() {
        longPressTimer?.cancel()
        longPressTimer = nil
        isLongPressed = false
    }

    // MARK: - Picker Helpers

    private func syncPickerToCurrentOffset() {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .monthly:
            let base = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            let target = cal.date(byAdding: .month, value: store.offset, to: base)!
            pickerYear  = cal.component(.year,  from: target)
            pickerMonth = cal.component(.month, from: target)
        case .yearly:
            pickerYear  = cal.component(.year, from: now) + store.offset
            pickerMonth = cal.component(.month, from: now)
        default:
            pickerYear  = cal.component(.year,  from: now)
            pickerMonth = cal.component(.month, from: now)
        }
    }

    private func applyPicker() {
        let cal = Calendar.current
        let now = Date()
        let currentYear  = cal.component(.year,  from: now)
        let currentMonth = cal.component(.month, from: now)
        switch period {
        case .monthly:
            store.offset = min((pickerYear - currentYear) * 12 + (pickerMonth - currentMonth), 0)
        case .yearly:
            store.offset = min(pickerYear - currentYear, 0)
        default:
            break
        }
        selectedLabel = nil
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
        var countMap: [Int: Int] = [:]
        for i in 0..<7 { distMap[i] = 0; countMap[i] = 0 }

        for record in store.records {
            let recordDay = cal.startOfDay(for: record.date)
            guard recordDay >= monday && recordDay < sunday else { continue }
            let diff = cal.dateComponents([.day], from: monday, to: recordDay).day ?? -1
            if diff >= 0 && diff < 7 {
                distMap[diff, default: 0] += record.distance / 1000
                countMap[diff, default: 0] += 1
            }
        }

        return (0..<7).map { i in
            let date = cal.date(byAdding: .day, value: i, to: monday)!
            return ChartDataPoint(label: dayNames[i], date: date, distance: distMap[i] ?? 0, count: countMap[i] ?? 0)
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
        var countMap: [Int: Int] = [:]
        for d in 1...maxDay { distMap[d] = 0; countMap[d] = 0 }

        for record in store.records {
            guard record.date >= targetMonth && record.date < nextMonth else { continue }
            let d = cal.component(.day, from: record.date)
            if d <= maxDay {
                distMap[d, default: 0] += record.distance / 1000
                countMap[d, default: 0] += 1
            }
        }

        return (1...maxDay).map { d in
            ChartDataPoint(label: "\(d)", date: targetMonth, distance: distMap[d] ?? 0, count: countMap[d] ?? 0)
        }
    }

    // MARK: - 연도별

    private func aggregateYear(offset: Int) -> [ChartDataPoint] {
        let cal = Calendar.current
        let now = Date()
        let targetYear = cal.component(.year, from: now) + offset

        let maxMonth = 12

        var distMap: [Int: Double] = [:]
        var countMap: [Int: Int] = [:]
        for m in 1...maxMonth { distMap[m] = 0; countMap[m] = 0 }

        for record in store.records {
            guard cal.component(.year, from: record.date) == targetYear else { continue }
            let m = cal.component(.month, from: record.date)
            if m <= maxMonth {
                distMap[m, default: 0] += record.distance / 1000
                countMap[m, default: 0] += 1
            }
        }

        return (1...maxMonth).map { m in
            ChartDataPoint(label: "\(m)월", date: now, distance: distMap[m] ?? 0, count: countMap[m] ?? 0)
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
        var countMap: [Int: Int] = [:]
        for y in years { distMap[y] = 0; countMap[y] = 0 }

        for record in store.records {
            let y = cal.component(.year, from: record.date)
            if distMap[y] != nil {
                distMap[y]! += record.distance / 1000
                countMap[y]! += 1
            }
        }

        return years.map { y in
            ChartDataPoint(label: "\(y)", date: Date(), distance: distMap[y] ?? 0, count: countMap[y] ?? 0)
        }
    }
}

// MARK: - Period Picker Sheet

private struct PeriodPickerSheet: View {
    let period: ChartPeriod
    @Binding var year: Int
    @Binding var month: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let currentYear  = Calendar.current.component(.year,  from: Date())
    private let currentMonth = Calendar.current.component(.month, from: Date())
    private var years: [Int] { Array((2015...currentYear).reversed()) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("취소", action: onCancel)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("확인", action: onConfirm)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            HStack(spacing: 0) {
                Picker("연도", selection: $year) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y) + "년").tag(y)
                    }
                }
                .pickerStyle(.wheel)

                if period == .monthly {
                    Picker("월", selection: $month) {
                        ForEach(1...12, id: \.self) { m in
                            Text("\(m)월").tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                }
            }
            // 미래 선택 방지
            .onChange(of: year) { _, newYear in
                if newYear == currentYear && month > currentMonth {
                    month = currentMonth
                }
            }
            .onChange(of: month) { _, newMonth in
                if year == currentYear && newMonth > currentMonth {
                    month = currentMonth
                }
            }
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
            ChartDataPoint(label: dayNames[i], date: cal.date(byAdding: .day, value: i, to: monday)!, distance: distMap[i] ?? 0, count: 0)
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
            ChartDataPoint(label: "\(d)", date: targetMonth, distance: distMap[d] ?? 0, count: 0)
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
        return (1...12).map { m in ChartDataPoint(label: "\(m)월", date: Date(), distance: distMap[m] ?? 0, count: 0) }
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
        return years.map { y in ChartDataPoint(label: "\(y)", date: Date(), distance: distMap[y] ?? 0, count: 0) }
    }
}

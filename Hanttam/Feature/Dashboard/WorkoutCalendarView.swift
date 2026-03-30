//
//  WorkoutCalendarView.swift
//  Hanttam
//
//  Created by passi on 3/30/26.
//

import SwiftUI

struct WorkoutCalendarView: View {
    
    let dailyData  : [Date: DailyWorkoutInfo]
    let accentColor: Color
    
    @State private var displayedMonth: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }()
    
    private let calendar       = Calendar.current
    private let weekdaySymbols = ["월", "화", "수", "목", "금", "토", "일"]
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WORKOUT CALENDAR")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(accentColor)
                    Text("\(AppFormatter.yearMonth.string(from: displayedMonth))")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppColor.bgSecondary)
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button { changeMonth(by: -1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.bgSecondary)
                    }
                    Button { changeMonth(by: 1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isCurrentMonth ? .quaternary : .secondary)
                    }
                    .disabled(isCurrentMonth)
                }
            }
            
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            let days = daysInMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
                ForEach(days, id: \.self) { day in
                    dayCell(for: day)
                }
            }
            
            legendView
        }
        .padding(20)
        .background(AppColor.dashboardSecondaryBg)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
    
    @ViewBuilder
    private func dayCell(for date: Date?) -> some View {
        if let date {
            let day       = calendar.component(.day, from: date)
            let info      = dailyData[calendar.startOfDay(for: date)]
            let intensity = info?.intensity ?? .none
            let isToday   = calendar.isDateInToday(date)
            let isFuture  = date > Date()
            
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(fillColor(for: intensity, isFuture: isFuture))
                        .frame(width: 32, height: 32)
                    
                    if isToday {
                        Circle()
                            .strokeBorder(accentColor ,lineWidth: 2)
                            .frame(width: 32, height: 32)
                    }
                    
                    Text("\(day)")
                        .font(.system(size: 12, weight: isToday ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(textColor(for: intensity, isFuture: isFuture, isToday: isToday))
                }
                
                Circle()
                    .fill(intensity != .none ? accentColor.opacity(dotOpacify(for: intensity)) : .clear)
                    .frame(width: 4, height: 4)
            }
        } else {
            Color.clear
                .frame(height: 39)
        }
    }
    
    private var legendView: some View {
        HStack(spacing: 12) {
            Text("강도")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                legendItem(intensity: .light)
                legendItem(intensity: .moderate)
                legendItem(intensity: .hard)
                legendItem(intensity: .intense)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func legendItem(intensity: WorkoutIntensity) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(accentColor.opacity(fillOpacity(for: intensity)))
                .frame(width: 10, height: 10)
            
            Text(intensity.distanceLabel)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }
    
    //MARK: - Colors
    
    private func fillColor(for intensity: WorkoutIntensity, isFuture: Bool) -> Color {
        guard !isFuture else { return .clear }
        guard intensity != .none else { return .clear }
        return accentColor.opacity(fillOpacity(for: intensity))
    }
    
    private func fillOpacity(for intensity: WorkoutIntensity) -> Double {
        switch intensity {
        case .none    : return 0
        case .light   : return 0.15
        case .moderate: return 0.35
        case .hard    : return 0.6
        case .intense : return 0.9
        }
    }
    
    private func dotOpacify(for intensity: WorkoutIntensity) -> Double {
        switch intensity {
        case .none    : return 0
        case .light   : return 0.4
        case .moderate: return 0.6
        case .hard    : return 0.8
        case .intense : return 1.0
        }
    }
    
    private func textColor(for intensity: WorkoutIntensity, isFuture: Bool, isToday: Bool) -> Color {
        if isFuture { return AppColor.textSecondary.opacity(0.3) }
        if intensity == .hard || intensity == .intense { return .white}
        if isToday { return accentColor }
        return AppColor.textLabel
    }
    
    //MARK: - Date 헬퍼
    
    private var isCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }
    
    private func changeMonth(by value: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
                displayedMonth = newMonth
            }
        }
    }
    
    private func daysInMonth() -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        else { return [] }
        
        // weekday offset(월요일 = 0)
        var weekday = calendar.component(.weekday, from: firstDay) - 2
        if weekday < 0 { weekday += 7 }
        
        var days: [Date?] = Array(repeating: nil, count: weekday)
        
        for day in range {
            if let date = calendar.date(byAdding: .day,
                                        value: day - 1,
                                        to: firstDay) {
                days.append(date)
            }
        }
        
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }
    
}

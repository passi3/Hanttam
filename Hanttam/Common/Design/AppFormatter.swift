//
//  AppFormatter.swift
//  Hanttam
//
//  Created by passi on 3/29/26.
//

import Foundation

final class AppFormatter {

    // MARK: - Date

    /// "yyyy.MM.dd (E)"  ko_KR  — 기록 목록 날짜
    static let recordDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy.MM.dd (E)"; f.locale = .init(identifier: "ko_KR"); return f
    }()

    /// "M.d"  — 차트 주간 범위 (3.19 ~ 3.25)
    static let monthDay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M.d"; return f
    }()

    /// "yyyy년 M월"  — 차트 월간 제목
    static let yearMonth: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy년 M월"; return f
    }()

    /// "M월"  ko_KR  — 누적 차트 월 이름
    static let monthKo: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M월"; f.locale = .init(identifier: "ko_KR"); return f
    }()
    
    /// "HH:mm:ss - 운동 시작/종료 시각
    static let timeHMS: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    // MARK: - Number (String(format:) 래퍼 — 반복 패턴)

    static func distance2f(_ meters: Double) -> String { String(format: "%.2f km", meters / 1000) }
    static func distance1f(_ meters: Double) -> String { String(format: "%.1f km", meters / 1000) }
    static func calories(_ kcal: Double) -> String      { String(format: "%.0f kcal", kcal) }
    static func heartRate(_ bpm: Double) -> String      { String(format: "%.0f bpm", bpm) }

    /// mm:ss  (RecordsCell 공통)
    static func duration(_ seconds: TimeInterval) -> String {
        let t = Int(seconds); return String(format: "%d:%02d", t / 60, t % 60)
    }
}

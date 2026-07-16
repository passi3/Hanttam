//
//  WorkoutVoiceAnnouncement.swift
//  Hanttam
//
//  Created by passi on 7/16/26.
//

import Foundation

struct IntervalLapCompletionSummary: Equatable {
    let eventID: String
    let completedSet: Int
    let totalDistance: Double
    let totalDuration: TimeInterval
    let avgPace: TimeInterval?
    let lapPace: TimeInterval?
    let avgHeartRate: Double?
    let lapHeartRate: Double?
}

struct WorkoutCompletionSummary: Equatable {
    let eventID: String
    let completedSets: Int
    let totalDistance: Double
    let totalDuration: TimeInterval
    let avgPace: TimeInterval?
    let avgHeartRate: Double?
}

enum WorkoutVoiceAnnouncementPreferences {
    static let isEnabledKey = "workoutVoiceAnnouncementsEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: isEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isEnabledKey) }
    }
}

enum WorkoutVoiceAnnouncementFormatter {
    static func intervalLapCompletionText(_ summary: IntervalLapCompletionSummary) -> String {
        var parts = [
            "\(summary.completedSet)세트 완료",
            "누적 거리 \(distanceText(summary.totalDistance))",
            "총 시간 \(durationText(summary.totalDuration))"
        ]

        if let avgPace = paceText(summary.avgPace) {
            parts.append("평균 페이스 \(avgPace)")
        }
        if let lapPace = paceText(summary.lapPace) {
            parts.append("랩 페이스 \(lapPace)")
        }
        if let avgHeartRate = heartRateText(summary.avgHeartRate) {
            parts.append("평균 심박 \(avgHeartRate)")
        }
        if let lapHeartRate = heartRateText(summary.lapHeartRate) {
            parts.append("랩 심박 \(lapHeartRate)")
        }

        return sentence(from: parts)
    }

    static func workoutCompletionText(_ summary: WorkoutCompletionSummary) -> String {
        var parts = [
            "운동 완료",
            "총 \(summary.completedSets)세트",
            "총 거리 \(distanceText(summary.totalDistance))",
            "총 시간 \(durationText(summary.totalDuration))"
        ]

        if let avgPace = paceText(summary.avgPace) {
            parts.append("평균 페이스 \(avgPace)")
        }
        if let avgHeartRate = heartRateText(summary.avgHeartRate) {
            parts.append("평균 심박 \(avgHeartRate)")
        }

        return sentence(from: parts)
    }

    private static func sentence(from parts: [String]) -> String {
        parts.joined(separator: ". ") + "."
    }

    private static func distanceText(_ meters: Double) -> String {
        String(format: "%.3f킬로미터", meters / 1000)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        var parts: [String] = []
        if hours > 0 {
            parts.append("\(nativeKoreanNumber(hours)) 시간")
        }
        if minutes > 0 {
            parts.append("\(sinoKoreanNumber(minutes))분")
        }
        if seconds > 0 || parts.isEmpty {
            parts.append("\(sinoKoreanNumber(seconds))초")
        }
        return parts.joined(separator: " ")
    }

    private static func paceText(_ secondsPerKilometer: TimeInterval?) -> String? {
        guard let secondsPerKilometer,
              secondsPerKilometer.isFinite,
              secondsPerKilometer > 0,
              secondsPerKilometer < 3600 else { return nil }

        let totalSeconds = Int(secondsPerKilometer.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "킬로미터당 \(minutes)분 \(seconds)초"
    }

    private static func heartRateText(_ bpm: Double?) -> String? {
        guard let bpm, bpm.isFinite, bpm > 0 else { return nil }
        return String(format: "%.0f", bpm)
    }

    private static func nativeKoreanNumber(_ number: Int) -> String {
        let ones = [
            "", "한", "두", "세", "네", "다섯", "여섯", "일곱", "여덟", "아홉"
        ]
        let tens = [
            "", "열", "스무", "서른", "마흔", "쉰", "예순", "일흔", "여든", "아흔"
        ]

        guard number > 0 else { return "영" }
        guard number < 100 else { return "\(number)" }

        let ten = number / 10
        let one = number % 10
        if ten == 0 { return ones[one] }
        if one == 0 { return tens[ten] }
        return "\(tens[ten])\(ones[one])"
    }

    private static func sinoKoreanNumber(_ number: Int) -> String {
        let digits = ["영", "일", "이", "삼", "사", "오", "육", "칠", "팔", "구"]
        let units = ["", "십", "백", "천"]

        guard number > 0 else { return "영" }
        guard number < 10000 else { return "\(number)" }

        var result = ""
        let characters = Array(String(number))
        for (index, character) in characters.enumerated() {
            guard let digit = Int(String(character)), digit > 0 else { continue }
            let unitIndex = characters.count - index - 1
            if digit == 1 && unitIndex > 0 {
                result += units[unitIndex]
            } else {
                result += digits[digit] + units[unitIndex]
            }
        }
        return result
    }
}

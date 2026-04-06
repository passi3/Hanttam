//
//  WatchWorkoutSummaryBuilder.swift
//  Hanttam Watch Watch App
//
//  Created by Codex on 4/5/26.
//

import SwiftUI
import CoreLocation

enum WatchWorkoutSummaryBuilder {
    static func freeRun(
        route: [CLLocation],
        elapsed: TimeInterval,
        totalDistance: Double,
        avgPace: TimeInterval?,
        avgHeartRate: Double?,
        calories: Double
    ) -> WatchWorkoutSummaryData {
        let splits = buildFreeRunLaps(from: route)
        return WatchWorkoutSummaryData(
            title: "WORKOUT\nSUMMARY",
            route: route.map(\.coordinate),
            distanceText: String(format: "%.2f", totalDistance / 1000),
            durationText: durationText(elapsed),
            metricCards: [
                .init(
                    title: "AVG HR",
                    value: hrText(avgHeartRate),
                    unit: "BPM",
                    icon: "heart.fill",
                    tint: .red,
                    progress: heartRateProgress(avgHeartRate)
                ),
                .init(
                    title: "CALORIES",
                    value: String(format: "%.0f", calories),
                    unit: "KCAL",
                    icon: "flame.fill",
                    tint: .yellow,
                    progress: nil
                ),
                .init(
                    title: "ELEVATION",
                    value: String(format: "%.0f", totalElevationGain(from: route)),
                    unit: "M",
                    icon: "mountain.2.fill",
                    tint: .green,
                    progress: nil
                )
            ],
            laps: splits
        )
    }

    static func interval(
        route: [CLLocationCoordinate2D],
        elapsed: TimeInterval,
        totalDistance: Double,
        avgHeartRate: Double?,
        calories: Double,
        laps: [IntervalLap]
    ) -> WatchWorkoutSummaryData {
        let runLaps = laps.filter { $0.type == .run }
        return WatchWorkoutSummaryData(
            title: "INTERVAL\nSUMMARY",
            route: route,
            distanceText: String(format: "%.2f", totalDistance / 1000),
            durationText: durationText(elapsed),
            metricCards: [
                .init(
                    title: "AVG HR",
                    value: hrText(avgHeartRate),
                    unit: "BPM",
                    icon: "heart.fill",
                    tint: .red,
                    progress: heartRateProgress(avgHeartRate)
                ),
                .init(
                    title: "CALORIES",
                    value: String(format: "%.0f", calories),
                    unit: "KCAL",
                    icon: "flame.fill",
                    tint: .yellow,
                    progress: nil
                ),
                .init(
                    title: "SETS",
                    value: "\(runLaps.count)",
                    unit: "RUN",
                    icon: "repeat",
                    tint: RunningLevelManager.shared.accentColor,
                    progress: nil
                )
            ],
            laps: buildIntervalLaps(from: runLaps)
        )
    }

    private static func buildFreeRunLaps(from route: [CLLocation]) -> [WatchWorkoutSummaryData.LapRow] {
        guard route.count >= 2 else {
            return (1...3).map {
                .init(id: $0, indexLabel: "\($0)", splitTime: "--", paceText: "--", isBest: false, isPlaceholder: true)
            }
        }

        var rows: [WatchWorkoutSummaryData.LapRow] = []
        var accumulated: Double = 0
        var lapStartDate = route[0].timestamp
        var lapIndex = 1

        for index in 1..<route.count {
            accumulated += route[index].distance(from: route[index - 1])
            while accumulated >= Double(lapIndex) * 1000 {
                let duration = route[index].timestamp.timeIntervalSince(lapStartDate)
                let pace = duration
                rows.append(
                    .init(
                        id: lapIndex,
                        indexLabel: "\(lapIndex)",
                        splitTime: splitTimeText(duration),
                        paceText: paceText(pace),
                        isBest: false,
                        isPlaceholder: false
                    )
                )
                lapStartDate = route[index].timestamp
                lapIndex += 1
            }
        }

        if let last = route.last {
            let fullDistance = Double(max(rows.count, 0)) * 1000
            let remainder = totalDistance(from: route) - fullDistance
            if remainder > 100 {
                let duration = last.timestamp.timeIntervalSince(lapStartDate)
                let pace = duration / max(remainder / 1000, 0.001)
                rows.append(
                    .init(
                        id: lapIndex,
                        indexLabel: "\(lapIndex)",
                        splitTime: splitTimeText(duration),
                        paceText: paceText(pace),
                        isBest: false,
                        isPlaceholder: false
                    )
                )
            }
        }

        return finalizeRows(markBestLap(rows))
    }

    private static func buildIntervalLaps(from laps: [IntervalLap]) -> [WatchWorkoutSummaryData.LapRow] {
        let rows = laps.enumerated().map { index, lap in
            let pace = lap.avgPace ?? (lap.duration / max(lap.distance / 1000, 0.001))
            return WatchWorkoutSummaryData.LapRow(
                id: index + 1,
                indexLabel: "\(index + 1)",
                splitTime: splitTimeText(lap.duration),
                paceText: paceText(pace),
                isBest: false,
                isPlaceholder: false
            )
        }
        return finalizeRows(markBestLap(rows))
    }

    private static func markBestLap(_ rows: [WatchWorkoutSummaryData.LapRow]) -> [WatchWorkoutSummaryData.LapRow] {
        let parsed = rows.enumerated().compactMap { index, row -> (Int, TimeInterval)? in
            guard !row.isPlaceholder else { return nil }
            guard let seconds = seconds(from: row.paceText) else { return nil }
            return (index, seconds)
        }
        let bestIndex = parsed.min(by: { $0.1 < $1.1 })?.0
        return rows.enumerated().map { index, row in
            .init(
                id: row.id,
                indexLabel: row.indexLabel,
                splitTime: row.splitTime,
                paceText: row.paceText,
                isBest: index == bestIndex,
                isPlaceholder: row.isPlaceholder
            )
        }
    }

    private static func finalizeRows(_ rows: [WatchWorkoutSummaryData.LapRow]) -> [WatchWorkoutSummaryData.LapRow] {
        guard rows.count < 7 else { return rows }
        let placeholders = ((rows.count + 1)...7).map {
            WatchWorkoutSummaryData.LapRow(
                id: $0,
                indexLabel: "\($0)",
                splitTime: "--",
                paceText: "--",
                isBest: false,
                isPlaceholder: true
            )
        }
        return rows + placeholders
    }

    private static func totalDistance(from route: [CLLocation]) -> Double {
        guard route.count >= 2 else { return 0 }
        return zip(route, route.dropFirst()).reduce(0) { $0 + $1.1.distance(from: $1.0) }
    }

    private static func totalElevationGain(from route: [CLLocation]) -> Double {
        guard route.count >= 2 else { return 0 }
        return zip(route, route.dropFirst()).reduce(0) { partial, points in
            let gain = max(points.1.altitude - points.0.altitude, 0)
            return partial + gain
        }
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }

    static func splitTimeText(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d'%02d\"", minutes, seconds)
    }

    static func paceText(_ secPerKm: TimeInterval?) -> String {
        guard let secPerKm, secPerKm.isFinite, secPerKm > 0, secPerKm < 3600 else { return "--" }
        return String(format: "%d:%02d/KM", Int(secPerKm) / 60, Int(secPerKm) % 60)
    }

    private static func seconds(from paceText: String) -> TimeInterval? {
        let value = paceText.replacingOccurrences(of: "/KM", with: "")
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else { return nil }
        return (minutes * 60) + seconds
    }

    static func hrText(_ bpm: Double?) -> String {
        guard let bpm else { return "--" }
        return String(format: "%.0f", bpm)
    }

    static func heartRateProgress(_ bpm: Double?) -> Double? {
        guard let bpm else { return nil }
        return min(max((bpm - 80) / 90, 0), 1)
    }
}

//
//  WatchWorkoutDashboard.swift
//  Hanttam Watch Watch App
//
//  Created by Codex on 4/5/26.
//

import SwiftUI

struct WatchLapSummarySnapshot: Equatable, Identifiable {
    let id = UUID()
    let totalDistance: Double
    let lapDisplayDistance: Double
    let avgPace: TimeInterval?
    let lapPace: TimeInterval?
    let avgHeartRate: Double?
    let lapHeartRate: Double?
}

struct WatchWorkoutDashboardPage: View {
    let topIcon: String
    let topLeading: String
    let accentColor: Color
    let primaryValue: String
    let primaryUnit: String
    let leftMetricTitle: String
    let leftMetricValue: String
    let rightMetricTitle: String
    let rightMetricValue: String
    let rightMetricAction: (() -> Void)?
    let bottomIcon: String
    let bottomTint: Color
    let bottomLabel: String
    let bottomValue: String
    let bottomUnit: String
    let bottomAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            topBar
            primaryMetric
            HStack(spacing: 4) {
                WatchWorkoutMetricTile(title: leftMetricTitle, value: leftMetricValue)
                WatchWorkoutMetricTile(
                    title: rightMetricTitle,
                    value: rightMetricValue,
                    action: rightMetricAction
                )
            }
            WatchWorkoutBottomMetricRow(
                icon: bottomIcon,
                tint: bottomTint,
                label: bottomLabel,
                value: bottomValue,
                unit: bottomUnit,
                action: bottomAction
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var topBar: some View {
        HStack {
            Label(topLeading, systemImage: topIcon)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryMetric: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(primaryValue)
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(accentColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(primaryUnit)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.64))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WatchLapSummaryOverlay: View {
    let summary: WatchLapSummarySnapshot
    let accentColor: Color

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Text("LAP COMPLETE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)

                HStack(spacing: 8) {
                    summaryTile(title: "TOTAL DISTANCE", value: distanceText(summary.totalDistance))
                    summaryTile(title: "LAP DISTANCE", value: distanceText(summary.lapDisplayDistance))
                }

                HStack(spacing: 8) {
                    summaryTile(title: "AVG PACE", value: paceText(summary.avgPace))
                    summaryTile(title: "LAP PACE", value: paceText(summary.lapPace))
                }

                HStack(spacing: 8) {
                    summaryTile(title: "AVG HR", value: heartRateText(summary.avgHeartRate))
                    summaryTile(title: "LAP HR", value: heartRateText(summary.lapHeartRate))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(accentColor.opacity(0.24), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35).ignoresSafeArea())
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func summaryTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.52))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private func distanceText(_ meters: Double) -> String {
        String(format: "%.2f KM", meters / 1000)
    }

    private func paceText(_ secondsPerKm: TimeInterval?) -> String {
        guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0, secondsPerKm < 3600 else {
            return "--'--\""
        }
        return String(format: "%d'%02d\"", Int(secondsPerKm) / 60, Int(secondsPerKm) % 60)
    }

    private func heartRateText(_ bpm: Double?) -> String {
        guard let bpm else { return "--" }
        return String(format: "%.0f BPM", bpm)
    }
}

struct WatchWorkoutMetricTile: View {
    let title: String
    let value: String
    let action: (() -> Void)?

    init(title: String, value: String, action: (() -> Void)? = nil) {
        self.title = title
        self.value = value
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }
}

struct WatchWorkoutBottomMetricRow: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String
    let unit: String
    let action: (() -> Void)?

    init(
        icon: String,
        tint: Color,
        label: String,
        value: String,
        unit: String,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.tint = tint
        self.label = label
        self.value = value
        self.unit = unit
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text(unit)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.52))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }
}

//
//  WatchWorkoutDashboard.swift
//  Hanttam Watch Watch App
//
//  Created by Codex on 4/5/26.
//

import SwiftUI

struct WatchWorkoutDashboardPage: View {
    let topIcon: String
    let topLeading: String
    let topTrailingText: String?
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
    let bottomProgress: Double?
    let bottomAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            topBar
            primaryMetric
            HStack(spacing: 8) {
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
                progress: bottomProgress,
                action: bottomAction
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            Label(topLeading, systemImage: topIcon)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            if let topTrailingText {
                Text(topTrailingText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var primaryMetric: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(primaryValue)
                .font(.system(size: 42, weight: .black, design: .rounded))
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
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
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
    let progress: Double?
    let action: (() -> Void)?

    init(
        icon: String,
        tint: Color,
        label: String,
        value: String,
        unit: String,
        progress: Double?,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.tint = tint
        self.label = label
        self.value = value
        self.unit = unit
        self.progress = progress
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
        HStack(spacing: 8) {
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

            Spacer(minLength: 8)

            if let progress {
                WatchWorkoutProgressBar(progress: progress, tint: tint)
                    .frame(width: 46)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }
}

struct WatchWorkoutProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, min(1, progress)) * proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.85), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
            }
        }
        .frame(height: 10)
    }
}

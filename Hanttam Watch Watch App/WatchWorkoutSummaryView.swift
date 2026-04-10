//
//  WatchWorkoutSummaryView.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/5/26.
//

import SwiftUI
import CoreLocation

struct WatchWorkoutSummaryData {
    struct MetricCard: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let unit: String
        let icon: String
        let tint: Color
        let progress: Double?
    }

    struct LapRow: Identifiable {
        let id: Int
        let indexLabel: String
        let splitTime: String
        let paceText: String
        let isBest: Bool
        let isPlaceholder: Bool
    }

    let title: String
    let route: [CLLocationCoordinate2D]
    let distanceText: String
    let durationText: String
    let metricCards: [MetricCard]
    let laps: [LapRow]
}

struct WatchWorkoutSummaryView: View {
    let data: WatchWorkoutSummaryData
    var onBack: () -> Void = {}
    var onFinishReview: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    routeCard
                    heroMetrics
                    metricCards
                    lapsSection
                    finishButton
                        .padding(.top, 4)
                    Spacer(minLength: 70)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 0.90, green: 0.95, blue: 0.72))
            }
            .buttonStyle(.plain)

            Text(data.title)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.90, green: 0.95, blue: 0.72))
                .multilineTextAlignment(.leading)

            Spacer()
        }
    }

    private var routeCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 124)
                .overlay {
                    WatchRoutePreview(route: data.route)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(1)
                }

            Text("ROUTE")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.84, green: 1.0, blue: 0.0))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.7), in: Capsule())
                .padding(12)
        }
    }

    private var heroMetrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryBlock(title: "DISTANCE", value: data.distanceText, unit: "KM", accent: true)
            summaryBlock(title: "TOTAL TIME", value: data.durationText, unit: "MIN", accent: false)
        }
    }

    private var metricCards: some View {
        VStack(spacing: 10) {
            ForEach(data.metricCards) { card in
                HStack(spacing: 10) {
                    if let progress = card.progress {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 4)
                            Circle()
                                .trim(from: 0, to: max(0.04, min(progress, 1)))
                                .stroke(card.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 28, height: 28)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.6))
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(card.value)
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                            Text(card.unit)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(card.tint)
                        }
                    }

                    Spacer()

                    Image(systemName: card.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(card.tint.opacity(0.85))
                }
                .padding(.horizontal, 14)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                )
            }
        }
    }

    private var lapsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAPS")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.8))

            ForEach(data.laps) { lap in
                HStack {
                    Text(lap.indexLabel)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(lap.isBest ? Color(red: 0.84, green: 1.0, blue: 0.0) : Color(red: 0.95, green: 0.97, blue: 0.74))
                        .frame(width: 18, alignment: .leading)

                    Spacer()

                    Text(lap.splitTime)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(lap.isBest ? Color(red: 0.84, green: 1.0, blue: 0.0) : .white)
                        .monospacedDigit()

                    Spacer()

                    Text(lap.paceText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(lap.isPlaceholder ? 0.35 : 0.62))
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(lap.isPlaceholder ? 0.03 : 0.055))
                        .overlay(alignment: .leading) {
                            if lap.isBest {
                                Capsule()
                                    .fill(Color(red: 0.84, green: 1.0, blue: 0.0))
                                    .frame(width: 3, height: 26)
                                    .padding(.leading, 1)
                            }
                        }
                )
            }
        }
    }

    private var finishButton: some View {
        Button(action: onFinishReview) {
            Text("FINISH REVIEW")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(red: 0.84, green: 1.0, blue: 0.0))
                        .shadow(color: Color(red: 0.84, green: 1.0, blue: 0.0).opacity(0.35), radius: 10, y: 6)
                )
        }
        .buttonStyle(.plain)
    }

    private func summaryBlock(title: String, value: String, unit: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: accent ? 38 : 28, weight: .black, design: .rounded))
                    .foregroundStyle(accent ? Color(red: 0.84, green: 1.0, blue: 0.0) : .white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
    }
}

private struct WatchRoutePreview: View {
    let route: [CLLocationCoordinate2D]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.015))
                routeBackground
                let points = normalizedPoints(in: proxy.size)
                if let path = normalizedPath(from: points) {
                    path
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .shadow(color: Color.white.opacity(0.55), radius: 6)
                    startEndMarkers(points: points)
                }
            }
        }
    }

    private var routeBackground: some View {
        Canvas { context, size in
            let columns = stride(from: 16.0, to: size.width, by: 22.0)
            let rows = stride(from: 14.0, to: size.height, by: 20.0)
            for x in columns {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x - 12, y: size.height))
                context.stroke(path, with: .color(Color.white.opacity(0.025)), lineWidth: 1)
            }
            for y in rows {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y + 6))
                context.stroke(path, with: .color(Color.white.opacity(0.018)), lineWidth: 1)
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard route.count >= 2 else { return [] }
        let lats = route.map(\.latitude)
        let lngs = route.map(\.longitude)
        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLng = lngs.min(),
              let maxLng = lngs.max() else { return [] }

        let latSpan = max(maxLat - minLat, 0.0001)
        let lngSpan = max(maxLng - minLng, 0.0001)
        let insetX = size.width * 0.08
        let insetY = size.height * 0.1
        let width = size.width - insetX * 2
        let height = size.height - insetY * 2

        return route.map { point in
            let x = insetX + ((point.longitude - minLng) / lngSpan) * width
            let y = insetY + (1 - ((point.latitude - minLat) / latSpan)) * height
            return CGPoint(x: x, y: y)
        }
    }

    private func normalizedPath(from points: [CGPoint]) -> Path? {
        guard let first = points.first else { return nil }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    @ViewBuilder
    private func startEndMarkers(points: [CGPoint]) -> some View {
        if let start = points.first {
            Circle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 6, height: 6)
                .position(start)
        }
        if let end = points.last {
            Circle()
                .stroke(Color.white.opacity(0.75), lineWidth: 2)
                .background(Circle().fill(Color.white.opacity(0.18)))
                .frame(width: 16, height: 16)
                .position(end)
        }
    }
}

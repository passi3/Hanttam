//
//  RunDetailView.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import UIKit
import SwiftUI
import Charts
import MapKit
internal import HealthKit

// MARK: - Design Tokens

enum DS {
    static let bg         = AppColor.backgroundTertiary
    static let card       = AppColor.cardBackground
    static let cardActive = AppColor.cardActive
    static var accent: Color { RunningLevelManager.shared.accentColor }
    static var accentDeep: Color { RunningLevelManager.shared.accentColor.opacity(0.8) }
    static let highlight  = AppColor.yellow
    static let textLabel  = AppColor.textPrimary
    static let textDim    = AppColor.textSecondary
    static let border     = AppColor.border
}

enum RunDetailLayout {
    static let horizontalInset: CGFloat = 16
    static let topInset: CGFloat = 20
    static let bottomInset: CGFloat = 80
    static let sectionSpacing: CGFloat = 16
    static let cardRadius: CGFloat = 14
    static let compactCardRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let metricChartYAxisWidth: CGFloat = 28
    static let summaryMetricColumnSpacing: CGFloat = 28
    static let compactMetricHeaderMinHeight: CGFloat = 36
    static let compactMetricHeaderSpacing: CGFloat = 10
    static let compactMetricStatWidth: CGFloat = 48
    static let compactMetricStatsGroupSpacing: CGFloat = 8
}

// Color(hex:) extension is defined in RunningLevelView.swift

// MARK: - Time Series Point

struct TSPoint: Identifiable {
    let id: Int
    let elapsed: Double   // 분
    let value: Double
}

// MARK: - Metric Type

enum MetricType: CaseIterable {
    case pace, heartRate, cadence, strideLength
    case verticalOscillation, groundContactTime, power, cumulativeElevation, altitude
    
    var title: String {
        switch self {
        case .pace:                 return "페이스"
        case .heartRate:            return "심박수"
        case .cadence:              return "케이던스"
        case .strideLength:         return "보폭 길이"
        case .verticalOscillation:  return "수직 진폭"
        case .groundContactTime:    return "접지시간"
        case .power:                return "달리기파워"
        case .cumulativeElevation:  return "누적 상승 시간"
        case .altitude:             return "고도"
        }
    }
    
    var unit: String {
        switch self {
        case .pace:                 return "/km"
        case .heartRate:            return "bpm"
        case .cadence:              return "spm"
        case .strideLength:         return "m"
        case .verticalOscillation:  return "cm"
        case .groundContactTime:    return "ms"
        case .power:                return "W"
        case .cumulativeElevation:  return "m"
        case .altitude:             return "m"
        }
    }
    
    var color: Color {
        switch self {
        case .pace:                 return Color(red: 0.45, green: 0.78, blue: 0.25)
        case .heartRate:            return Color.orange
        case .cadence:              return Color(red: 0.2, green: 0.7, blue: 0.65)
        case .strideLength:         return Color(red: 0.35, green: 0.55, blue: 0.85)
        case .verticalOscillation:  return Color(red: 0.55, green: 0.45, blue: 0.8)
        case .groundContactTime:    return Color(red: 0.85, green: 0.5, blue: 0.3)
        case .power:                return Color(red: 0.9, green: 0.6, blue: 0.2)
        case .cumulativeElevation:  return Color(red: 0.55, green: 0.75, blue: 0.3)
        case .altitude:             return Color(red: 0.4, green: 0.65, blue: 0.45)
        }
    }
    
    var gradientTopColor: Color {
        switch self {
        case .pace:                 return Color(red: 0.85, green: 0.9, blue: 0.15)
        default:                    return color.opacity(0.7)
        }
    }
    
    enum ChartStyle {
        case line, bar
    }
    
    var chartStyle: ChartStyle {
        switch self {
        case .heartRate:            return .line
        case .verticalOscillation:  return .line
        default:                    return .bar
        }
    }
    
    var invertedY: Bool { self == .pace }
    
    func format(_ v: Double) -> String {
        switch self {
        case .pace:                 return formatPaceValue(v)
        case .heartRate:            return String(format: "%.0f", v)
        case .cadence:              return String(format: "%.0f", v)
        case .strideLength:         return String(format: "%.2f", v)
        case .verticalOscillation:  return String(format: "%.1f", v)
        case .groundContactTime:    return String(format: "%.0f", v)
        case .power:                return String(format: "%.1f", v)
        case .cumulativeElevation:  return String(format: "%.1f", v)
        case .altitude:             return String(format: "%.1f", v)
        }
    }
}

func formatPaceValue(_ secPerKm: Double) -> String {
    guard secPerKm.isFinite && secPerKm > 0 else { return "-'--\"" }
    let m = Int(secPerKm) / 60
    let s = Int(secPerKm) % 60
    return String(format: "%d'%02d\"", m, s)
}

func formatDuration(_ t: TimeInterval) -> String {
    let h = Int(t) / 3600
    let m = Int(t) % 3600 / 60
    let s = Int(t) % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

private struct RunDetailRouteMapView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    let highlightCoordinate: CLLocationCoordinate2D?
    
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isUserInteractionEnabled = false
        let config = MKStandardMapConfiguration()
        config.emphasisStyle = .muted
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config
        map.delegate = context.coordinator
        return map
    }
    
    func updateUIView(_ map: MKMapView, context: Context) {
        let applyRoute = {
            guard map.bounds.width > 0, map.bounds.height > 0 else { return }
            
            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations)
            
            guard coordinates.count >= 2 else { return }
            
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            map.addOverlay(polyline)
            
            if let start = coordinates.first {
                map.addAnnotation(PointAnnotation(coordinate: start, color: UIColor(DS.accent), size: 8))
            }
            if let end = coordinates.last {
                map.addAnnotation(PointAnnotation(coordinate: end, color: UIColor(DS.accentDeep), size: 8))
            }
            if let highlightCoordinate {
                map.addAnnotation(PointAnnotation(coordinate: highlightCoordinate, color: .white, size: 12, strokeColor: UIColor(DS.accent), strokeWidth: 2))
            }
            
            let rect = polyline.boundingMapRect
            guard !rect.isNull, !rect.isEmpty else { return }
            let insets = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
            map.setVisibleMapRect(rect, edgePadding: insets, animated: false)
        }
        
        if map.bounds.width == 0 || map.bounds.height == 0 {
            DispatchQueue.main.async(execute: applyRoute)
            return
        }
        
        applyRoute()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(DS.accent)
            renderer.lineWidth = 5
            renderer.lineCap = .round
            return renderer
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? PointAnnotation else { return nil }
            let identifier = "RunDetailPointAnnotation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ?? MKAnnotationView(annotation: point, reuseIdentifier: identifier)
            view.annotation = point
            view.frame = CGRect(x: 0, y: 0, width: point.size, height: point.size)
            view.layer.cornerRadius = point.size / 2
            view.backgroundColor = point.color
            view.layer.borderColor = point.strokeColor?.cgColor
            view.layer.borderWidth = point.strokeWidth
            view.layer.shadowColor = UIColor.black.withAlphaComponent(0.2).cgColor
            view.layer.shadowOpacity = point.strokeColor == nil ? 0 : 1
            view.layer.shadowRadius = point.strokeColor == nil ? 0 : 4
            view.layer.shadowOffset = .zero
            return view
        }
    }
    
    final class PointAnnotation: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let color: UIColor
        let size: CGFloat
        let strokeColor: UIColor?
        let strokeWidth: CGFloat
        
        init(coordinate: CLLocationCoordinate2D, color: UIColor, size: CGFloat, strokeColor: UIColor? = nil, strokeWidth: CGFloat = 0) {
            self.coordinate = coordinate
            self.color = color
            self.size = size
            self.strokeColor = strokeColor
            self.strokeWidth = strokeWidth
        }
    }
}

// MARK: - Content View (SwiftUI Sections for UIKit embedding)

private struct ShareButton: View {
    let onTap: () -> Void
    var body: some View {
        Button {
            onTap()
        } label: {
            Image(systemName: "camera.fill")
                .font(AppFont.labelSM)
                .foregroundStyle(DS.textLabel)
                .padding(6)
                .background(DS.cardActive, in: Circle())
        }
    }
}

enum RunDetailContentView {
    struct SummaryMetricGridCell: View {
        let label: String
        let value: String
        var isShareStyle: Bool = false

        @Environment(\.overlayTextColor) private var overlayTextColor
        @Environment(\.overlaySubTextColor) private var overlaySubTextColor

        private var labelFont: Font {
            isShareStyle ? .system(size: 8, weight: .bold) : AppFont.captionMD.weight(.medium)
        }

        private var valueFont: Font {
            isShareStyle ? .system(size: 20, weight: .ultraLight, design: .monospaced) : .system(size: 24, weight: .ultraLight, design: .monospaced)
        }

        private var labelColor: Color {
            isShareStyle ? overlaySubTextColor : DS.textDim
        }

        private var valueColor: Color {
            isShareStyle ? overlayTextColor : DS.textLabel
        }

        var body: some View {
            VStack(spacing: isShareStyle ? 2 : 4) {
                Text(label)
                    .font(labelFont)
                    .tracking(isShareStyle ? 1 : 1.5)
                    .foregroundStyle(labelColor)
                    .multilineTextAlignment(.center)
                Text(value)
                    .font(valueFont)
                    .foregroundStyle(valueColor)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    // MARK: - Chart Helper
    
    struct ChartHelper {
        let record: RunningRecord
        let data: RunDetailViewModel.DetailData
        private let maxChartPoints = 1000
        private let bucketInterval: TimeInterval = 10

        func averageValue(for metric: MetricType) -> Double? {
            let series = timeSeries(for: metric)
            guard !series.isEmpty else { return nil }
            return series.reduce(0) { $0 + $1.value } / Double(series.count)
        }
        
        func timeSeries(for metric: MetricType) -> [TSPoint] {
            let startDate = record.date
            let raw: [TSPoint]
            
            switch metric {
            case .pace:
                raw = bucketedAverageSeries(
                    data.speedSamples.compactMap { s in
                        guard s.value > 0 else { return nil }
                        return TimedMetricSample(
                            elapsed: s.startDate.timeIntervalSince(startDate),
                            value: 1000.0 / s.value
                        )
                    }
                )
            case .heartRate:
                raw = bucketedAverageSeries(
                    data.heartRates.map { s in
                        TimedMetricSample(
                            elapsed: s.date.timeIntervalSince(startDate),
                            value: s.bpm
                        )
                    }
                )
            case .cadence:
                raw = bucketedAverageSeries(
                    data.stepSamples.compactMap { s in
                        let dur = s.endDate.timeIntervalSince(s.startDate) / 60
                        guard dur > 0 else { return nil }
                        return TimedMetricSample(
                            elapsed: s.startDate.timeIntervalSince(startDate),
                            value: s.value / dur
                        )
                    }
                )
            case .strideLength:
                raw = bucketedAverageSeries(quantityTimedSamples(data.strideSamples, from: startDate))
            case .verticalOscillation:
                raw = bucketedAverageSeries(quantityTimedSamples(data.voSamples, from: startDate))
            case .power:
                raw = bucketedAverageSeries(quantityTimedSamples(data.powerSamples, from: startDate))
            case .groundContactTime:
                raw = bucketedAverageSeries(quantityTimedSamples(data.gctSamples, from: startDate))
            case .cumulativeElevation:
                raw = bucketedCumulativeElevation(from: data.altPoints, startDate: startDate)
            case .altitude:
                raw = bucketedAverageSeries(
                    data.altPoints.map { p in
                        TimedMetricSample(
                            elapsed: p.date.timeIntervalSince(startDate),
                            value: p.altitude
                        )
                    }
                )
            }
            
            return downsample(raw)
        }

        private struct TimedMetricSample {
            let elapsed: TimeInterval
            let value: Double
        }

        private func quantityTimedSamples(_ samples: [QuantitySamplePoint], from startDate: Date) -> [TimedMetricSample] {
            samples.map { s in
                TimedMetricSample(
                    elapsed: s.startDate.timeIntervalSince(startDate),
                    value: s.value
                )
            }
        }

        private func bucketedAverageSeries(_ samples: [TimedMetricSample]) -> [TSPoint] {
            guard !samples.isEmpty else { return [] }

            let grouped = Dictionary(grouping: samples) { sample in
                Int(floor(max(sample.elapsed, 0) / bucketInterval))
            }

            let sortedKeys = grouped.keys.sorted()
            return sortedKeys.enumerated().compactMap { index, key in
                guard let values = grouped[key], !values.isEmpty else { return nil }
                let average = values.reduce(0) { $0 + $1.value } / Double(values.count)
                return TSPoint(
                    id: index,
                    elapsed: (Double(key) * bucketInterval) / 60,
                    value: average
                )
            }
        }

        private func bucketedCumulativeElevation(from altPoints: [AltitudePoint], startDate: Date) -> [TSPoint] {
            guard altPoints.count >= 2 else { return [] }

            var cumulativeSamples: [TimedMetricSample] = []
            var cumulativeGain: Double = 0
            cumulativeSamples.append(TimedMetricSample(elapsed: altPoints[0].date.timeIntervalSince(startDate), value: 0))

            for index in 1..<altPoints.count {
                let diff = altPoints[index].altitude - altPoints[index - 1].altitude
                if diff > 0 { cumulativeGain += diff }
                cumulativeSamples.append(
                    TimedMetricSample(
                        elapsed: altPoints[index].date.timeIntervalSince(startDate),
                        value: cumulativeGain
                    )
                )
            }

            let maxElapsed = max(cumulativeSamples.last?.elapsed ?? 0, 0)
            let bucketCount = Int(floor(maxElapsed / bucketInterval))
            guard bucketCount >= 0 else { return [] }

            var result: [TSPoint] = []
            var sampleIndex = 0

            for bucket in 0...bucketCount {
                let bucketElapsed = Double(bucket) * bucketInterval
                while sampleIndex + 1 < cumulativeSamples.count,
                      cumulativeSamples[sampleIndex + 1].elapsed <= bucketElapsed {
                    sampleIndex += 1
                }

                let value = cumulativeSamples[sampleIndex].value
                result.append(
                    TSPoint(
                        id: result.count,
                        elapsed: bucketElapsed / 60,
                        value: value
                    )
                )
            }

            return result
        }
        
        private func downsample(_ points: [TSPoint]) -> [TSPoint] {
            guard points.count > maxChartPoints else {
                return points.enumerated().map { TSPoint(id: $0.offset, elapsed: $0.element.elapsed, value: $0.element.value) }
            }
            let step = Double(points.count) / Double(maxChartPoints)
            return (0..<maxChartPoints).map { i in
                let p = points[Int(Double(i) * step)]
                return TSPoint(id: i, elapsed: p.elapsed, value: p.value)
            }
        }
    }
    
    // MARK: - Route Map Section
    
    struct RouteMapSection: View {
        let altPoints: [AltitudePoint]
        let record: RunningRecord
        var highlightCoordinate: CLLocationCoordinate2D? = nil
        
        private var routeCoordinates: [CLLocationCoordinate2D] {
            altPoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
        
        var body: some View {
            ZStack {
                RunDetailRouteMapView(
                    coordinates: routeCoordinates,
                    highlightCoordinate: highlightCoordinate
                )
                
                LinearGradient(
                    colors: [DS.bg, .clear, .clear, DS.bg],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .background(DS.card)
        }
    }
    
    struct AnimatableValueText: View, Animatable {
        var value: Double
        var formatter: (Double) -> String
        
        var animatableData: Double {
            get { value }
            set { value = newValue }
        }
        
        var body: some View {
            Text(formatter(value))
        }
    }
    
    // MARK: - Summary Hero Section
    
    struct SummaryHeroSection: View {
        enum SummaryShareType: Identifiable {
            case metrics
            case lapPace

            var id: String {
                switch self {
                case .metrics: return "metrics"
                case .lapPace: return "lapPace"
                }
            }
        }
        
        let record: RunningRecord
        let heartRates: [HeartRateSample]
        let data: RunDetailViewModel.DetailData
        
        @State private var locationName: String = ""
        @State private var activeShareType: SummaryShareType?
        
        @State private var animatedDistance: Double = 0
        @State private var animatedDuration: Double = 0
        @State private var animatedPace: Double = 0
        @State private var animatedCadence: Double = 0
        @State private var animatedHR: Double = 0

        private var chartHelper: ChartHelper {
            ChartHelper(record: record, data: data)
        }
        
        private var avgPace: TimeInterval {
            guard record.distance > 0 else { return 0 }
            return record.duration / (record.distance / 1000)
        }
        private var avgHR: Double {
            guard !heartRates.isEmpty else { return 0 }
            return heartRates.reduce(0) { $0 + $1.bpm } / Double(heartRates.count)
        }
        private var avgCadence: Double {
            chartHelper.averageValue(for: .cadence) ?? 0
        }
        private var totalElevationGain: Double {
            guard data.altPoints.count >= 2 else { return 0 }
            var gain: Double = 0
            for i in 1..<data.altPoints.count {
                let diff = data.altPoints[i].altitude - data.altPoints[i - 1].altitude
                if diff > 0 { gain += diff }
            }
            return gain
        }
        
        var body: some View {
            VStack(spacing: 0) {
                // Distance hero
                distanceSection
                    .padding(.vertical, 20)
                
                sectionDivider
                
                // 2x2 metric grid
                metricGrid
                    .padding(.vertical, 0)
                
                // Mini route map
                if !record.isIndoor && !data.altPoints.isEmpty {
                    sectionDivider
                    miniMapSection
                        .padding(.vertical, 16)
                }
                
                // Lap pace chart
                if !data.lapRows.isEmpty {
                    sectionDivider
                    splitPaceBarSection
                        .padding(.vertical, 16)
                }
                
                // Elevation bar chart
                if !data.altPoints.isEmpty {
                    sectionDivider
                    elevationBarSection
                        .padding(.vertical, 16)
                }
            }
            .task {
                await fetchLocationName()
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.0)) {
                    animatedDistance = record.distance / 1000
                    animatedDuration = record.duration
                    animatedPace = avgPace
                    animatedCadence = avgCadence
                    animatedHR = avgHR
                }
            }
            .sheet(item: $activeShareType) { shareType in
                ChartPhotoShareView {
                    if shareType == .metrics {
                        RunDetailContentView.SummaryMetricsShareOverlay(
                            record: record,
                            avgPace: avgPace,
                            avgHR: avgHR,
                            avgCadence: avgCadence,
                            data: data
                        )
                    } else {
                        RunDetailContentView.SummaryLapPaceShareOverlay(
                            record: record,
                            data: data
                        )
                    }
                }
            }
        }
        
        // MARK: - Distance Section
        
        private var distanceSection: some View {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Text(record.isIndoor ? "INDOOR RUN" : "OUTDOOR RUN")
                        .font(AppFont.labelSM)
                        .tracking(2)
                        .foregroundStyle(DS.textDim)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        AnimatableValueText(value: animatedDistance) { v in
                            String(format: "%.2f", v)
                        }
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundStyle(DS.textLabel)
                        Text("km")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(DS.textDim)
                    }
                    
                    if !locationName.isEmpty {
                        Text(locationName)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(DS.textDim)
                    }
                }
                .frame(maxWidth: .infinity)
                
                ShareButton {
                    activeShareType = .metrics
                }
                .padding(.trailing, 20)
                .padding(.top, 0)
            }
        }
        
        // MARK: - Metric Grid
        
        private var metricGrid: some View {
            let columns = [
                GridItem(.flexible(), spacing: RunDetailLayout.summaryMetricColumnSpacing),
                GridItem(.flexible(), spacing: RunDetailLayout.summaryMetricColumnSpacing)
            ]
            return LazyVGrid(columns: columns, spacing: 0) {
                metricCell(label: "TIME", value: animatedDuration) { formatDuration($0) }
                metricCell(label: "PACE", value: animatedPace) { formatPaceValue($0) }
                metricCell(label: "CADENCE", value: animatedCadence) { $0 > 0 ? String(format: "%.0f", $0) : "--" }
                metricCell(label: "AVG HEART RATE", value: animatedHR) { $0 > 0 ? String(format: "%.0f", $0) : "--" }
            }
            .padding(.horizontal, 8)
        }
        
        private func metricCell(label: String, value: Double, formatter: @escaping (Double) -> String) -> some View {
            SummaryMetricGridCell(
                label: label,
                value: formatter(value)
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        
        // MARK: - Mini Map
        
        private var miniMapSection: some View {
            let coords = data.altPoints.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            return RunDetailRouteMapView(coordinates: coords, highlightCoordinate: nil)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: RunDetailLayout.compactCardRadius))
                .padding(.horizontal, 20)
        }
        
        // MARK: - Split Pace Bar Section
        
        @ViewBuilder
        private var splitPaceBarSection: some View {
            let worstPace: Double = data.lapRows.map(\.pace).max() ?? 0
            let bestPace: Double = data.lapRows.map(\.pace).min() ?? 0
            let bottomScore = min(paceChartScore(worstPace), paceChartScore(avgPace)) * 0.7
            let topScore = max(paceChartScore(bestPace), paceChartScore(avgPace)) * 1.04
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("LAP PACE")
                        .font(AppFont.captionMD.weight(.medium))
                        .tracking(1.5)
                        .foregroundStyle(DS.textDim)
                    Spacer()
                    ShareButton {
                        activeShareType = .lapPace
                    }
                }
                .padding(.horizontal, 20)
                
                Chart {
                    ForEach(data.lapRows) { row in
                        BarMark(
                            x: .value("Lap", row.label),
                            yStart: .value("floor", bottomScore),
                            yEnd: .value("PaceScore", paceChartScore(row.pace))
                        )
                        .foregroundStyle(DS.accent.opacity(row.pace == bestPace ? 1.0 : 0.6))
                    }
                    
                    RuleMark(y: .value("Average", paceChartScore(avgPace)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(DS.textDim.opacity(0.6))
                }
                .chartYScale(domain: bottomScore...topScore)
                .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 18))
                .chartYAxis {
                    AxisMarks(
                        position: .leading,
                        values: [
                            paceChartScore(worstPace),
                            paceChartScore(avgPace),
                            paceChartScore(bestPace)
                        ]
                    ) { (value: AxisValue) in
                        AxisValueLabel {
                            if let score = value.as(Double.self) {
                                Text(formatPaceValue(pace(fromChartScore: score)))
                                    .font(.system(size: 10))
                                    .foregroundStyle(DS.textDim)
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(DS.border)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { (value: AxisValue) in
                        if let lapStr = value.as(String.self) {
                            let labels = data.lapRows.map(\.label)
                            let isFirst = lapStr == labels.first
                            let isLast = lapStr == labels.last
                            let isEveryFive = labels.firstIndex(of: lapStr).map { ($0 + 1) % 5 == 0 } ?? false
                            if isFirst || isEveryFive || isLast {
                                AxisValueLabel {
                                    Text(lapStr)
                                        .font(.system(size: 10))
                                        .foregroundStyle(DS.textDim)
                                }
                            }
                        }
                    }
                }
                .chartPlotBorderStyle(borderColor: DS.border.opacity(0.9))
                .frame(height: 140)
                .padding(.horizontal, 20)
            }
        }

        private func paceChartScore(_ pace: Double) -> Double {
            guard pace.isFinite, pace > 0 else { return 0 }
            return 1000.0 / pace
        }

        private func pace(fromChartScore score: Double) -> Double {
            guard score.isFinite, score > 0 else { return 0 }
            return 1000.0 / score
        }
        
        // MARK: - Elevation Bar Chart
        
        @ViewBuilder
        private var elevationBarSection: some View {
            let segments = elevationSegments(count: 12)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ELEVATION GAIN")
                        .font(AppFont.captionMD.weight(.medium))
                        .tracking(1.5)
                        .foregroundStyle(DS.textDim)
                    Spacer()
                    Text(String(format: "%.1f m", totalElevationGain))
                        .font(AppFont.captionMD.weight(.medium))
                        .tracking(0.5)
                        .foregroundStyle(DS.textLabel)
                }
                .padding(.horizontal, 20)
                
                if !segments.isEmpty {
                    Chart(segments) { seg in
                        BarMark(
                            x: .value("구간", seg.id),
                            y: .value("고도", seg.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DS.accent.opacity(0.4), DS.accent],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartPlotBorderStyle(borderColor: DS.border.opacity(0.9))
                    .chartYScale(domain: .automatic(includesZero: true))
                    .frame(height: 56)
                    .padding(.horizontal, 20)
                }
            }
        }
        
        // MARK: - Helpers
        
        private var sectionDivider: some View {
            Rectangle()
                .fill(DS.border.opacity(0.3))
                .frame(height: 1)
        }
        
        private func elevationSegments(count: Int) -> [TSPoint] {
            let points = data.altPoints
            guard points.count >= 2 else { return [] }
            let segSize = max(points.count / count, 1)
            var segments: [TSPoint] = []
            for i in 0..<count {
                let start = i * segSize
                let end = min(start + segSize, points.count)
                guard start < points.count else { break }
                let slice = points[start..<end]
                var gain: Double = 0
                for j in 1..<slice.count {
                    let idx = start + j
                    let diff = points[idx].altitude - points[idx - 1].altitude
                    if diff > 0 { gain += diff }
                }
                segments.append(TSPoint(id: i, elapsed: Double(i), value: gain))
            }
            return segments
        }
        
        private func fetchLocationName() async {
            guard !data.altPoints.isEmpty else { return }
            let mid = data.altPoints[data.altPoints.count / 2]
            let location = CLLocation(latitude: mid.latitude, longitude: mid.longitude)
            do {
                if let placemark = try await CLGeocoder().reverseGeocodeLocation(location).first {
                    let parts = [placemark.locality, placemark.administrativeArea].compactMap { $0 }
                    if !parts.isEmpty {
                        await MainActor.run { locationName = parts.joined(separator: ", ") }
                    }
                }
            } catch {}
        }
    }
    
    // MARK: - Section Header
    
    struct SectionHeader: View {
        let title: String
        var icon: String? = nil
        
        var body: some View {
            HStack(spacing: 6) {
                Text(title)
                    .font(AppFont.labelMD)
                    .tracking(2)
                    .foregroundStyle(DS.textLabel)
                if let icon {
                    Image(systemName: icon)
                        .font(AppFont.labelSM)
                        .foregroundStyle(DS.textDim)
                }
                Spacer()
            }
        }
    }
    
    // MARK: - Combined Chart Section
    
    struct CombinedChartSection: View {
        let paceData: [TSPoint]
        let hrData: [TSPoint]
        let altData: [TSPoint]
        
        @Binding var selectedElapsed: Double?
        @State private var showShareSheet = false
        
        private var hasData: Bool {
            !paceData.isEmpty || !hrData.isEmpty || !altData.isEmpty
        }
        
        private func nearest(_ data: [TSPoint], to elapsed: Double) -> TSPoint? {
            data.min(by: { abs($0.elapsed - elapsed) < abs($1.elapsed - elapsed) })
        }
        
        private var maxElapsed: Double {
            [paceData.last?.elapsed, hrData.last?.elapsed, altData.last?.elapsed]
                .compactMap { $0 }.max() ?? 1
        }
        
        var body: some View {
            if !hasData { EmptyView() }
            else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("통합 지표")
                            .font(.system(size: 12, weight: .regular))
                            .tracking(1.2)
                            .foregroundStyle(DS.textLabel)
                        Spacer()
                        legendDot(color: .blue, label: "페이스")
                        legendDot(color: .red, label: "심박")
                        legendDot(color: .green, label: "고도")
                    }
                    
                    ZStack(alignment: .topLeading) {
                        Chart {
                            ForEach(altData) { point in
                                PointMark(x: .value("시간", point.elapsed), y: .value("고도", point.value))
                                    .foregroundStyle(.green.opacity(0.5))
                                    .symbolSize(8)
                            }
                            ForEach(hrData) { point in
                                LineMark(x: .value("시간", point.elapsed), y: .value("심박", point.value), series: .value("series", "hr"))
                                    .foregroundStyle(.red.gradient)
                                    .interpolationMethod(.catmullRom)
                            }
                            let paceFloor = -(paceData.map(\.value).max() ?? 0) * 1.08
                            let paceCeiling = -(paceData.map(\.value).min() ?? 0) * 0.85
                            ForEach(paceData) { point in
                                BarMark(
                                    x: .value("시간", point.elapsed),
                                    yStart: .value("floor", paceFloor),
                                    yEnd: .value("페이스", -point.value),
                                    width: 2
                                )
                                .foregroundStyle(.blue.opacity(0.4))
                            }
                            // 상단 경계선 (도메인 고정용)
                            RuleMark(y: .value("ceiling", paceCeiling))
                                .foregroundStyle(.clear)
                            if let sel = selectedElapsed {
                                RuleMark(x: .value("선택", sel))
                                    .foregroundStyle(DS.textLabel.opacity(0.4))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            }
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisValueLabel {
                                    if let min = value.as(Double.self) {
                                        Text(String(format: "%.0f분", min))
                                            .font(.system(size: 9, weight: .light))
                                            .foregroundStyle(DS.textDim)
                                    }
                                }
                            }
                        }
                        .chartYAxis(.hidden)
                        .chartPlotBorderStyle(borderColor: DS.border.opacity(0.9))
                        .chartXSelection(value: $selectedElapsed)
                        .frame(height: 220)
                        
                        if let sel = selectedElapsed {
                            dataPopup(at: sel)
                        }
                    }
                }
                .padding(20)
                .background(DS.card)
                .overlay(Rectangle().fill(DS.accent).frame(width: 3), alignment: .leading)
                .sheet(isPresented: $showShareSheet) {
                    ChartPhotoShareView {
                        chartForShare
                    }
                    .presentationDragIndicator(.visible)
                }
            }
        }
        
        private var chartForShare: some View {
            let paceFloor = -(paceData.map(\.value).max() ?? 0) * 1.08
            let paceCeiling = -(paceData.map(\.value).min() ?? 0) * 0.85
            return VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("통합 차트")
                        .font(.system(size: 10, weight: .light))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    legendDot(color: .blue, label: "페이스")
                    legendDot(color: .red, label: "심박")
                    legendDot(color: .green, label: "고도")
                }
                Chart {
                    ForEach(altData) { point in
                        PointMark(x: .value("시간", point.elapsed), y: .value("고도", point.value))
                            .foregroundStyle(.green.opacity(0.5))
                            .symbolSize(8)
                    }
                    ForEach(hrData) { point in
                        LineMark(x: .value("시간", point.elapsed), y: .value("심박", point.value), series: .value("series", "hr"))
                            .foregroundStyle(.red.gradient)
                            .interpolationMethod(.catmullRom)
                    }
                    ForEach(paceData) { point in
                        BarMark(
                            x: .value("시간", point.elapsed),
                            yStart: .value("floor", paceFloor),
                            yEnd: .value("페이스", -point.value),
                            width: 2
                        )
                        .foregroundStyle(.blue.opacity(0.4))
                    }
                    RuleMark(y: .value("ceiling", paceCeiling))
                        .foregroundStyle(.clear)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let min = value.as(Double.self) {
                                Text(String(format: "%.0f분", min))
                                    .font(.system(size: 8, weight: .light))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .chartPlotBorderStyle(borderColor: .white.opacity(0.18))
                .frame(height: 160)
            }
        }
        
        private func dataPopup(at elapsed: Double) -> some View {
            let pace = nearest(paceData, to: elapsed)
            let hr = nearest(hrData, to: elapsed)
            let alt = nearest(altData, to: elapsed)
            let xRatio = maxElapsed > 0 ? elapsed / maxElapsed : 0
            let clampedX = min(max(xRatio, 0.15), 0.7)
            
            return VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "%.1f분", elapsed))
                    .font(.system(size: 9, weight: .light))
                    .tracking(0.8)
                    .foregroundStyle(DS.textDim)
                if let p = pace {
                    popupRow(color: .blue, label: "페이스", value: formatPaceValue(p.value), unit: "/km")
                }
                if let h = hr {
                    popupRow(color: .red, label: "심박", value: String(format: "%.0f", h.value), unit: "bpm")
                }
                if let a = alt {
                    popupRow(color: .green, label: "고도", value: String(format: "%.0f", a.value), unit: "m")
                }
            }
            .padding(10)
            .background(DS.cardActive, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(DS.border, lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: CGFloat(clampedX) * 280)
        }
        
        private func popupRow(color: Color, label: String, value: String, unit: String) -> some View {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label).font(.system(size: 8, weight: .light)).tracking(0.8).foregroundStyle(DS.textDim)
                Text(value).font(.system(size: 13, weight: .ultraLight, design: .monospaced)).foregroundStyle(.primary)
                Text(unit).font(.system(size: 8, weight: .light)).foregroundStyle(DS.textDim)
            }
        }
        
        private func legendDot(color: Color, label: String) -> some View {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label).font(.system(size: 8, weight: .light)).tracking(0.8).foregroundStyle(DS.textDim)
            }
        }
    }
    
    // MARK: - Tracking Section (Route Map + Combined Chart with interaction)
    
    struct TrackingSection: View {
        let altPoints: [AltitudePoint]
        let record: RunningRecord
        let paceData: [TSPoint]
        let hrData: [TSPoint]
        let altChartData: [TSPoint]
        
        @State private var selectedElapsed: Double?
        
        private var highlightCoordinate: CLLocationCoordinate2D? {
            guard let elapsed = selectedElapsed else { return nil }
            let targetDate = record.date.addingTimeInterval(elapsed * 60)
            guard let closest = altPoints.min(by: {
                abs($0.date.timeIntervalSince(targetDate)) < abs($1.date.timeIntervalSince(targetDate))
            }) else { return nil }
            return CLLocationCoordinate2D(latitude: closest.latitude, longitude: closest.longitude)
        }
        
        var body: some View {
            VStack(spacing: 0) {
                RouteMapSection(
                    altPoints: altPoints,
                    record: record,
                    highlightCoordinate: highlightCoordinate
                )
                .frame(height: 340)
                
                CombinedChartSection(
                    paceData: paceData,
                    hrData: hrData,
                    altData: altChartData,
                    selectedElapsed: $selectedElapsed
                )
            }
        }
    }
    
    // MARK: - Laps Full Section
    
    struct LapsFullSection: View {
        let record: RunningRecord
        let lapRows: [RunDetailLapRow]
        let heartRates: [HeartRateSample]
        let avgCadence: Double?
        let strideSamples: [QuantitySamplePoint]
        let voSamples: [QuantitySamplePoint]
        let speedSamples: [QuantitySamplePoint]
        
        private var avgPace: Double {
            guard !lapRows.isEmpty else { return 0 }
            let totalDist = lapRows.reduce(0) { $0 + $1.distance }
            let totalTime = lapRows.reduce(0) { $0 + ($1.pace * $1.distance / 1000) }
            return totalDist > 0 ? totalTime / (totalDist / 1000) : 0
        }
        
        private var avgHeartRate: Double? {
            let values = lapRows.compactMap(\.avgHeartRate)
            guard !values.isEmpty else { return heartRates.isEmpty ? nil : heartRates.reduce(0) { $0 + $1.bpm } / Double(heartRates.count) }
            return values.reduce(0, +) / Double(values.count)
        }
        
        private var avgStrideLength: Double? {
            guard !strideSamples.isEmpty else { return nil }
            return strideSamples.reduce(0) { $0 + $1.value } / Double(strideSamples.count)
        }
        
        private var avgVerticalOscillation: Double? {
            guard !voSamples.isEmpty else { return nil }
            return voSamples.reduce(0) { $0 + $1.value } / Double(voSamples.count)
        }
        
        private var bestLapRow: RunDetailLapRow? {
            lapRows.min(by: { $0.pace < $1.pace })
        }
        
        private var peakPace: Double? {
            guard let maxSpeed = speedSamples.map(\.value).filter({ $0 > 0 }).max() else { return nil }
            return 1000.0 / maxSpeed
        }
        
        private var peakHeartRate: Double? {
            guard let maxHeart = heartRates.map(\.bpm).filter({ $0 > 0 }).max() else { return nil }
            return maxHeart
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: RunDetailLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(record.isIndoor ? "INDOOR RUN" : "OUTDOOR RUN")
                        .font(AppFont.labelSM)
                        .tracking(2)
                        .foregroundStyle(DS.textDim)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(lapRows.count)")
                            .font(.system(size: 52, weight: .ultraLight))
                            .foregroundStyle(DS.textLabel)
                        Text("Laps")
                            .font(AppFont.titleSM)
                            .foregroundStyle(DS.textDim)
                    }
                }
                
                VStack(spacing: 0) {
                    let rows = summaryRows
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        summaryRow(label: row.label, value: row.value, unit: row.unit, accent: row.accent, isEven: index % 2 == 0)
                    }
                }
                .background(DS.card)
                .clipShape(RoundedRectangle(cornerRadius: RunDetailLayout.cardRadius))
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("LAP PACE")
                        .font(AppFont.labelMD)
                        .tracking(2)
                        .foregroundStyle(DS.textDim)
                    LapTableSection(rows: lapRows)
                }
            }
        }
        
        private struct SummaryRowData {
            let label: String
            let value: String
            let unit: String
            let accent: Color
        }

        private var summaryRows: [SummaryRowData] {
            var rows: [SummaryRowData] = [
                SummaryRowData(label: "평균 페이스", value: formatPaceValue(avgPace), unit: "", accent: DS.textLabel),
                SummaryRowData(label: "최고 구간 페이스", value: bestLapRow.map { formatPaceValue($0.pace) } ?? "--", unit: "", accent: DS.textLabel),
            ]
            if let peakPace {
                rows.append(SummaryRowData(label: "최고 순간 페이스", value: formatPaceValue(peakPace), unit: "", accent: DS.accent))
            }
            if let avgHeartRate {
                rows.append(SummaryRowData(label: "평균 심박수", value: String(format: "%.0f", avgHeartRate), unit: "bpm", accent: DS.textLabel))
            }
            if let peakHeartRate {
                rows.append(SummaryRowData(label: "최고 심박수", value: String(format: "%.0f", peakHeartRate), unit: "bpm", accent: DS.textLabel))
            }
            if let avgCadence {
                rows.append(SummaryRowData(label: "평균 케이던스", value: String(format: "%.0f", avgCadence), unit: "spm", accent: DS.textLabel))
            }
            if let avgStrideLength {
                rows.append(SummaryRowData(label: "평균 스트라이드", value: String(format: "%.2f", avgStrideLength), unit: "m", accent: DS.textLabel))
            }
            if let avgVerticalOscillation {
                rows.append(SummaryRowData(label: "평균 수직진폭", value: String(format: "%.1f", avgVerticalOscillation), unit: "cm", accent: DS.textLabel))
            }
            return rows
        }

        private func summaryRow(label: String, value: String, unit: String = "", accent: Color = DS.textLabel, isEven: Bool = false) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(AppFont.labelMD)
                    .tracking(1.5)
                    .foregroundStyle(DS.textDim)

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(AppFont.metricLabel)
                        .foregroundStyle(accent)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(AppFont.captionMD)
                            .foregroundStyle(DS.textDim)
                    }
                }
            }
            .padding(.horizontal, RunDetailLayout.cardPadding)
            .padding(.vertical, 12)
            .background(isEven ? DS.cardActive : DS.card)
        }
    }
    
    // MARK: - Lap Table Section
    
    struct LapTableSection: View {
        let rows: [RunDetailLapRow]
        
        var body: some View {
            VStack(spacing: 0) {
                LapHeaderRow()
                
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    LapRow(
                        row: row,
                        previousRow: index > 0 ? rows[index - 1] : nil,
                        isEven: index % 2 == 0
                    )
                }
            }
            .background(DS.card)
            .clipShape(RoundedRectangle(cornerRadius: RunDetailLayout.cardRadius))
        }
    }
    
    private struct LapHeaderRow: View {
        var body: some View {
            HStack(spacing: 0) {
                Text("LAP")
                    .frame(width: 52, alignment: .leading)
                Text("페이스")
                    .frame(maxWidth: .infinity)
                Text("심박")
                    .frame(maxWidth: .infinity)
                Text("고도")
                    .frame(maxWidth: .infinity)
                Text("변화")
                    .frame(width: 72, alignment: .trailing)
            }
            .font(AppFont.captionMD.weight(.medium))
            .tracking(0.5)
            .foregroundStyle(DS.textDim)
            .padding(.horizontal, RunDetailLayout.cardPadding)
            .padding(.vertical, 10)
            .background(DS.card)
        }
    }
    
    private struct LapRow: View {
        let row: RunDetailLapRow
        let previousRow: RunDetailLapRow?
        var isEven: Bool = false
        
        private var paceDiff: Double? {
            guard let prev = previousRow else { return nil }
            return row.pace - prev.pace
        }
        
        private var diffColor: Color {
            guard let diff = paceDiff else { return DS.textDim }
            if diff < -1 { return .green }
            if diff > 1 { return .red }
            return DS.textDim
        }
        
        var body: some View {
            HStack(spacing: 0) {
                Text(row.label)
                    .font(AppFont.metricCaption)
                    .frame(width: 52, alignment: .leading)
                
                Text(formatPaceValue(row.pace))
                    .font(AppFont.metricCaption)
                    .frame(maxWidth: .infinity)
                
                Text(row.avgHeartRate.map { String(format: "%.0f", $0) } ?? "--")
                    .font(AppFont.metricCaption)
                    .foregroundStyle(.red.opacity(0.8))
                    .frame(maxWidth: .infinity)
                
                Text(row.elevationChange.map { String(format: "%+.0f", $0) } ?? "--")
                    .font(AppFont.metricCaption)
                    .foregroundStyle(.green.opacity(0.8))
                    .frame(maxWidth: .infinity)
                
                HStack(spacing: 2) {
                    if let diff = paceDiff {
                        Image(systemName: diff < -1 ? "chevron.up" : diff > 1 ? "chevron.down" : "minus")
                            .font(.system(size: 8, weight: .bold))
                        Text(formatPaceValue(abs(diff)))
                            .font(AppFont.metricSmall)
                    } else {
                        Text("--")
                            .font(AppFont.metricSmall)
                    }
                }
                .foregroundStyle(diffColor)
                .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, RunDetailLayout.cardPadding)
            .padding(.vertical, 12)
            .background(isEven ? DS.cardActive : DS.card)
        }
    }
    
    // MARK: - Time Series Section
    
    struct TimeSeriesSection: View {
        let metric: MetricType
        let data: [TSPoint]
        
        @State private var showShareSheet = false
        
        private var avg: Double {
            guard !data.isEmpty else { return 0 }
            return data.reduce(0) { $0 + $1.value } / Double(data.count)
        }
        
        private var minVal: Double {
            data.map(\.value).min() ?? 0
        }
        
        private var maxVal: Double {
            data.map(\.value).max() ?? 0
        }
        
        private var paceFloor: Double {
            -(data.map(\.value).max() ?? 0) * 1.08
        }
        
        private var paceCeiling: Double {
            -(data.map(\.value).min() ?? 0) * 0.92
        }
        
        private var chartDomain: ClosedRange<Double> {
            if metric.invertedY {
                return min(paceFloor, paceCeiling)...max(paceFloor, paceCeiling)
            }
            let span = max(maxVal - minVal, 1)
            let padding = span * 0.12
            return (minVal - padding)...(maxVal + padding)
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(metric.title)
                        .font(AppFont.labelSM)
                        .tracking(1.2)
                        .foregroundStyle(DS.textLabel)
                    Spacer()
                    ShareButton { showShareSheet = true }
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metric.format(avg))
                        .font(AppFont.metricTitle)
                        .foregroundStyle(DS.textLabel)
                    Text(metric.unit)
                        .font(AppFont.captionMD)
                        .tracking(0.5)
                        .foregroundStyle(DS.textDim)
                    Spacer()
                    Text("평균")
                        .font(AppFont.labelSM)
                        .tracking(1)
                        .foregroundStyle(DS.textDim)
                }
                
                Chart {
                    chartContent(areaOpacity: 0.12)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let min = value.as(Double.self) {
                                Text(String(format: "%.0f분", min))
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundStyle(DS.textDim)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(metric.invertedY ? metric.format(abs(v)) : metric.format(v))
                                    .font(.system(size: 9, weight: .light))
                                    .foregroundStyle(DS.textDim)
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [4]))
                            .foregroundStyle(DS.textLabel.opacity(0.08))
                    }
                }
                .chartPlotBorderStyle(borderColor: DS.border.opacity(0.9))
                .chartYScale(domain: chartDomain)
                .frame(height: 160)
                
                HStack(spacing: 8) {
                    statCell(title: "MIN", value: metric.format(minVal))
                    statCell(title: "AVG", value: metric.format(avg), accent: metric.color)
                    statCell(title: "MAX", value: metric.format(maxVal))
                }
            }
            .padding(RunDetailLayout.cardPadding)
            .background(DS.card)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [metric.gradientTopColor, metric.color.opacity(0.25)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: RunDetailLayout.cardRadius))
            .contextMenu {
                Button {
                    showShareSheet = true
                } label: {
                    Label("차트 공유", systemImage: "camera.fill")
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ChartPhotoShareView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(metric.title)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.8))
                        
                        Chart {
                            chartContent(areaOpacity: 0.15)
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisValueLabel {
                                    if let min = value.as(Double.self) {
                                        Text(String(format: "%.0f분", min))
                                            .font(.system(size: 8, weight: .light))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text(metric.invertedY ? metric.format(abs(v)) : metric.format(v))
                                            .font(.system(size: 8, weight: .light))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                            }
                        }
                        .chartPlotBorderStyle(borderColor: .white.opacity(0.18))
                        .chartYScale(domain: chartDomain)
                        .frame(height: 120)
                        
                        HStack(spacing: 8) {
                            shareStatCell(title: "MIN", value: metric.format(minVal))
                            shareStatCell(title: "AVG", value: metric.format(avg), accent: metric.color)
                            shareStatCell(title: "MAX", value: metric.format(maxVal))
                        }
                    }
                }
                .presentationDragIndicator(.visible)
            }
        }
        
        @ChartContentBuilder
        private func chartContent(areaOpacity: Double) -> some ChartContent {
            ForEach(data) { point in
                let plotY = metric.invertedY ? -point.value : point.value
                
                switch metric.chartStyle {
                case .line:
                    LineMark(x: .value("시간", point.elapsed), y: .value(metric.title, plotY))
                        .foregroundStyle(metric.color.gradient)
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("시간", point.elapsed), y: .value(metric.title, plotY))
                        .foregroundStyle(metric.color.opacity(areaOpacity).gradient)
                        .interpolationMethod(.catmullRom)
                    
                case .bar:
                    if metric.invertedY {
                        BarMark(
                            x: .value("시간", point.elapsed),
                            yStart: .value("floor", paceFloor),
                            yEnd: .value(metric.title, plotY),
                            width: 3
                        )
                        .foregroundStyle(metric.color.gradient)
                    } else {
                        BarMark(
                            x: .value("시간", point.elapsed),
                            y: .value(metric.title, plotY),
                            width: 3
                        )
                        .foregroundStyle(metric.color.gradient)
                    }
                }
            }
            
            if metric.invertedY {
                RuleMark(y: .value("ceiling", paceCeiling))
                    .foregroundStyle(.clear)
            }
        }
        
        @ViewBuilder
        private func statCell(title: String, value: String, accent: Color = DS.textLabel) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFont.labelSM)
                    .tracking(1)
                    .foregroundStyle(DS.textDim)
                Text(value)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DS.cardActive, in: RoundedRectangle(cornerRadius: RunDetailLayout.compactCardRadius))
        }
        
        @ViewBuilder
        private func shareStatCell(title: String, value: String, accent: Color = .white) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: RunDetailLayout.compactCardRadius))
        }
    }
    
    // MARK: - Performance Metric Card (Compact)
    
    struct PerformanceMetricCard: View {
        let metric: MetricType
        let data: [TSPoint]
        @Binding var selectedElapsed: Double?
        
        private var avg: Double {
            guard !data.isEmpty else { return 0 }
            return data.reduce(0) { $0 + $1.value } / Double(data.count)
        }
        
        private var minVal: Double { data.map(\.value).min() ?? 0 }
        private var maxVal: Double { data.map(\.value).max() ?? 0 }
        private var displayedMinVal: Double { metric == .pace ? maxVal : minVal }
        private var displayedMaxVal: Double { metric == .pace ? minVal : maxVal }
        
        private var paceFloor: Double {
            -(data.map(\.value).max() ?? 0) * 1.08
        }
        
        private var paceCeiling: Double {
            -(data.map(\.value).min() ?? 0) * 0.92
        }
        
        private var chartDomain: ClosedRange<Double> {
            if metric.invertedY {
                return min(paceFloor, paceCeiling)...max(paceFloor, paceCeiling)
            }
            let span = max(maxVal - minVal, 1)
            let padding = span * 0.12
            return (minVal - padding)...(maxVal + padding)
        }

        private var maxElapsed: Double {
            data.map(\.elapsed).max() ?? 0
        }

        private var selectedPoint: TSPoint? {
            guard let selectedElapsed else { return nil }
            return data.min(by: { abs($0.elapsed - selectedElapsed) < abs($1.elapsed - selectedElapsed) })
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text(metric.title.uppercased())
                        .font(AppFont.labelMD)
                        .tracking(1.2)
                        .foregroundStyle(DS.textDim)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer(minLength: 8)

                    HStack(spacing: RunDetailLayout.compactMetricStatsGroupSpacing) {
                        statCell(title: "MIN", value: metric.format(displayedMinVal))
                        statCell(title: "AVG", value: metric.format(avg), accent: metric.color)
                        statCell(title: "MAX", value: metric.format(displayedMaxVal))
                    }
                }
                .frame(minHeight: RunDetailLayout.compactMetricHeaderMinHeight, alignment: .top)

                chartContent
            }
            .padding(RunDetailLayout.cardPadding)
            .background(DS.card)
            .clipShape(RoundedRectangle(cornerRadius: RunDetailLayout.cardRadius))
        }
        
        private func statCell(title: String, value: String, accent: Color = DS.textLabel) -> some View {
            VStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(AppFont.labelSM)
                    .tracking(1)
                    .foregroundStyle(DS.textDim)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(value)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: RunDetailLayout.compactMetricStatWidth, alignment: .center)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(DS.cardActive, in: RoundedRectangle(cornerRadius: RunDetailLayout.compactCardRadius))
        }

        private var chartContent: some View {
            Chart {
                ForEach(data) { point in
                    let plotY = metric.invertedY ? -point.value : point.value

                    switch metric.chartStyle {
                    case .line:
                        LineMark(x: .value("t", point.elapsed), y: .value("v", plotY))
                            .foregroundStyle(metric.color.gradient)
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("t", point.elapsed), y: .value("v", plotY))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [metric.color.opacity(0.4), metric.color.opacity(0.05)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .interpolationMethod(.catmullRom)

                    case .bar:
                        if metric.invertedY {
                            BarMark(
                                x: .value("t", point.elapsed),
                                yStart: .value("floor", paceFloor),
                                yEnd: .value("v", plotY),
                                width: 3
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [metric.color.opacity(0.5), metric.gradientTopColor.opacity(0.8)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                        } else {
                            BarMark(
                                x: .value("t", point.elapsed),
                                y: .value("v", plotY),
                                width: 3
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [metric.color.opacity(0.5), metric.color],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                        }
                    }
                }

                if metric.invertedY {
                    RuleMark(y: .value("ceiling", paceCeiling))
                        .foregroundStyle(.clear)
                }

                if let selectedElapsed, let point = selectedPoint {
                    RuleMark(x: .value("selected", selectedElapsed))
                        .foregroundStyle(DS.textDim.opacity(0.9))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value("selectedPoint", point.elapsed),
                        y: .value("selectedValue", metric.invertedY ? -point.value : point.value)
                    )
                    .symbolSize(36)
                    .foregroundStyle(metric.color)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                        .foregroundStyle(DS.border.opacity(0.35))
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                        .foregroundStyle(DS.border.opacity(0.6))
                    AxisValueLabel {
                        if let axisValue = value.as(Double.self) {
                            Text(metricAxisText(for: axisValue))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(DS.textDim)
                                .frame(width: RunDetailLayout.metricChartYAxisWidth, alignment: .trailing)
                        }
                    }
                }
            }
            .chartPlotBorderStyle(borderColor: DS.border.opacity(0.9))
            .chartYScale(domain: chartDomain)
            .frame(height: 120)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    handleChartTap(at: value.location, proxy: proxy, geometry: geometry)
                                }
                        )
                }
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    if let selectedElapsed, let point = selectedPoint {
                        metricTooltip(for: point, selectedElapsed: selectedElapsed, plotWidth: proxy.size.width)
                    }
                }
            }
        }

        private func metricAxisText(for axisValue: Double) -> String {
            let displayedValue = metric.invertedY ? abs(axisValue) : axisValue
            return metric.format(displayedValue)
        }

        private func handleChartTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
            guard let plotFrameAnchor = proxy.plotFrame else { return }
            let plotFrame = geometry[plotFrameAnchor]
            guard plotFrame.contains(location), !data.isEmpty else { return }

            let relativeX = location.x - plotFrame.origin.x
            guard relativeX >= 0, relativeX <= plotFrame.width else { return }

            let ratio = max(0, min(1, relativeX / max(plotFrame.width, 1)))
            let targetElapsed = ratio * maxElapsed
            guard let nearestPoint = data.min(by: { abs($0.elapsed - targetElapsed) < abs($1.elapsed - targetElapsed) }) else { return }

            if selectedElapsed == nearestPoint.elapsed {
                selectedElapsed = nil
            } else {
                selectedElapsed = nearestPoint.elapsed
            }
        }

        @ViewBuilder
        private func metricTooltip(for point: TSPoint, selectedElapsed: Double, plotWidth: CGFloat) -> some View {
            let xRatio = maxElapsed > 0 ? point.elapsed / maxElapsed : 0
            let clampedX = min(max(xRatio, 0.08), 0.78)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%.1f분", selectedElapsed))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.textDim)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Circle()
                        .fill(metric.color)
                        .frame(width: 6, height: 6)
                    Text(metric.format(point.value))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.textLabel)
                    Text(metric.unit)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(metric.color)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DS.cardActive, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DS.border.opacity(0.9), lineWidth: 1)
            )
            .offset(x: plotWidth * clampedX, y: 4)
        }
    }

    struct PerformanceMetricsSection: View {
        let metrics: [(MetricType, [TSPoint])]

        @State private var selectedElapsed: Double?

        var body: some View {
            VStack(alignment: .leading, spacing: RunDetailLayout.sectionSpacing) {
                SectionHeader(title: "PERFORMANCE METRICS", icon: "chart.line.uptrend.xyaxis")

                ForEach(Array(metrics.enumerated()), id: \.offset) { _, item in
                    PerformanceMetricCard(
                        metric: item.0,
                        data: item.1,
                        selectedElapsed: $selectedElapsed
                    )
                }
            }
        }
    }
    
    // MARK: - Split Pace Section
    
    struct SplitPaceSection: View {
        let lapRows: [RunDetailLapRow]
        let speedSamples: [QuantitySamplePoint]
        
        @State private var selectedLabel: String?
        @State private var showShareSheet = false
        
        private var avgPace: Double {
            guard !lapRows.isEmpty else { return 0 }
            let totalDist = lapRows.reduce(0) { $0 + $1.distance }
            let totalTime = lapRows.reduce(0) { $0 + ($1.pace * $1.distance / 1000) }
            return totalDist > 0 ? totalTime / (totalDist / 1000) : 0
        }
        
        private var bestPace: Double {
            lapRows.map(\.pace).min() ?? 0
        }
        
        private var worstPace: Double {
            lapRows.map(\.pace).max() ?? 0
        }
        
        private struct PeakPace {
            let pace: Double
            let splitLabel: String
        }
        
        private var peakFastest: PeakPace? {
            guard let fastest = speedSamples.filter({ $0.value > 0 }).max(by: { $0.value < $1.value }) else { return nil }
            let pace = 1000.0 / fastest.value
            let splitLabel = findSplitLabel(for: fastest.startDate)
            return PeakPace(pace: pace, splitLabel: splitLabel)
        }
        
        private var floor: Double { -(worstPace * 1.1) }
        private var ceiling: Double { -(peakFastest?.pace ?? bestPace) * 0.95 }
        
        private func findSplitLabel(for date: Date) -> String {
            guard let row = lapRows.first(where: { date >= $0.startDate && date < $0.endDate })
                    ?? lapRows.last else { return "" }
            return row.label
        }
        
        private var selectedSplit: RunDetailLapRow? {
            guard let sel = selectedLabel else { return nil }
            return lapRows.first { $0.label == sel }
        }
        
        private func selectedDistanceLabel() -> String {
            guard let split = selectedSplit else { return "평균" }
            return split.label
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("랩별 페이스")
                        .font(.system(size: 10, weight: .light))
                        .tracking(1.2)
                        .foregroundStyle(DS.textLabel)
                    Spacer()
                    ShareButton { showShareSheet = true }
                }
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatPaceValue(selectedSplit?.pace ?? avgPace))
                            .font(.system(size: 22, weight: .ultraLight, design: .monospaced))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.2), value: selectedLabel)
                        Text(selectedDistanceLabel())
                            .font(.system(size: 10, weight: .light))
                            .tracking(1)
                            .foregroundStyle(DS.textDim)
                    }
                    if selectedSplit == nil, let fastest = peakFastest {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatPaceValue(fastest.pace))
                                .font(.system(size: 22, weight: .ultraLight, design: .monospaced))
                                .foregroundStyle(DS.accent)
                            Text("최고")
                                .font(.system(size: 10, weight: .light))
                                .tracking(1)
                                .foregroundStyle(DS.textDim)
                        }
                    }
                }
                
                Chart {
                    ForEach(lapRows) { split in
                        let splitLabel = split.label
                        BarMark(
                            x: .value("km", splitLabel),
                            yStart: .value("floor", floor),
                            yEnd: .value("페이스", -split.pace)
                        )
                        .foregroundStyle(
                            selectedLabel == nil
                            ? (split.pace == bestPace ? DS.accent : DS.accent.opacity(0.5))
                            : (selectedLabel == splitLabel ? DS.accent : DS.accent.opacity(0.2))
                        )
                        .cornerRadius(3)
                    }
                    
                    if let fastest = peakFastest {
                        PointMark(
                            x: .value("km", fastest.splitLabel),
                            y: .value("페이스", -fastest.pace)
                        )
                        .foregroundStyle(DS.accent)
                        .symbolSize(40)
                    }
                    
                    RuleMark(y: .value("평균", -avgPace))
                        .foregroundStyle(DS.textLabel.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let x = location.x - geo[plotFrame].origin.x
                                if let km: String = proxy.value(atX: x) {
                                    withAnimation(.spring(duration: 0.2)) {
                                        selectedLabel = (selectedLabel == km) ? nil : km
                                    }
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let x = value.location.x - geo[plotFrame].origin.x
                                        if let km: String = proxy.value(atX: x) {
                                            withAnimation(.spring(duration: 0.15)) {
                                                selectedLabel = km
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        withAnimation(.spring(duration: 0.2)) {
                                            selectedLabel = nil
                                        }
                                    }
                            )
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        let axisLabel = value.as(String.self) ?? ""
                        let labels = lapRows.map(\.label)
                        let isFirst = axisLabel == labels.first
                        let isLast = axisLabel == labels.last
                        let isEveryFive = labels.firstIndex(of: axisLabel).map { ($0 + 1) % 5 == 0 } ?? false
                        if isFirst || isEveryFive || isLast {
                            AxisValueLabel {
                                Text(axisLabel)
                                    .font(.system(size: 9, weight: .light))
                                    .foregroundStyle(DS.textDim)
                            }
                        } else {
                            AxisValueLabel { Text("") }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(
                        position: .leading,
                        values: [
                            -worstPace,
                             -avgPace,
                             -bestPace,
                             -(peakFastest?.pace ?? bestPace)
                        ]
                    ) { value in
                        AxisValueLabel {
                            if let sec = value.as(Double.self) {
                                let isAvg = abs(abs(sec) - avgPace) < 0.1
                                Text(formatPaceValue(abs(sec)))
                                    .font(.system(size: 9, weight: isAvg ? .medium : .light))
                                    .foregroundStyle(isAvg ? DS.textLabel : DS.textDim)
                            }
                        }
                    }
                }
                .chartPlotBorderStyle(borderColor: DS.border.opacity(0.9))
                .chartYScale(domain: min(floor, ceiling)...max(floor, ceiling))
                .frame(height: 200)
            }
            .padding(20)
            .background(DS.card)
            .overlay(Rectangle().fill(DS.accent).frame(width: 3), alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: RunDetailLayout.cardRadius))
            .sheet(isPresented: $showShareSheet) {
                ChartPhotoShareView {
                    SplitPaceShareOverlay(
                        lapRows: lapRows,
                        avgPace: avgPace,
                        bestPace: bestPace,
                        worstPace: worstPace,
                        peakFastest: peakFastest,
                        floor: floor,
                        ceiling: ceiling
                    )
                }
                .presentationDragIndicator(.visible)
            }
        }
        
        // MARK: - Split Pace Share Overlay
        
        private struct SplitPaceShareOverlay: View {
            let lapRows: [RunDetailLapRow]
            let avgPace: Double
            let bestPace: Double
            let worstPace: Double
            let peakFastest: PeakPace?
            let floor: Double
            let ceiling: Double
            
            @Environment(\.overlayTextColor) private var textColor
            @Environment(\.overlaySubTextColor) private var subTextColor
            
            var body: some View {
                VStack(alignment: .leading, spacing: 6) {
                    Text("랩별 페이스")
                        .font(.system(size: 10, weight: .light))
                        .tracking(1.2)
                        .foregroundStyle(textColor.opacity(0.8))
                    Chart {
                        ForEach(lapRows) { split in
                            BarMark(
                                x: .value("km", split.label),
                                yStart: .value("floor", floor),
                                yEnd: .value("페이스", -split.pace)
                            )
                            .foregroundStyle(
                                split.pace == bestPace ? DS.accent : DS.accent.opacity(0.5)
                            )
                            .cornerRadius(3)
                        }
                        if let fastest = peakFastest {
                            PointMark(
                                x: .value("km", fastest.splitLabel),
                                y: .value("페이스", -fastest.pace)
                            )
                            .foregroundStyle(DS.accent)
                            .symbolSize(40)
                        }
                        RuleMark(y: .value("평균", -avgPace))
                            .foregroundStyle(textColor.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            let axisLabel = value.as(String.self) ?? ""
                            let labels = lapRows.map(\.label)
                            let isFirst = axisLabel == labels.first
                            let isLast = axisLabel == labels.last
                            let isEveryFive = labels.firstIndex(of: axisLabel).map { ($0 + 1) % 5 == 0 } ?? false
                            if isFirst || isEveryFive || isLast {
                                AxisValueLabel {
                                    Text(axisLabel)
                                        .font(.system(size: 8, weight: .light))
                                        .foregroundStyle(subTextColor)
                                }
                            } else {
                                AxisValueLabel { Text("") }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(
                            position: .leading,
                            values: [-worstPace, -avgPace, -bestPace, -(peakFastest?.pace ?? bestPace)]
                        ) { value in
                            AxisValueLabel {
                                if let sec = value.as(Double.self) {
                                    Text(formatPaceValue(abs(sec)))
                                        .font(.system(size: 8, weight: .light))
                                        .foregroundStyle(subTextColor)
                                }
                            }
                        }
                    }
                    .chartPlotBorderStyle(borderColor: subTextColor.opacity(0.35))
                    .chartYScale(domain: min(floor, ceiling)...max(floor, ceiling))
                    .frame(height: 140)
                }
            }
        }
    }
    
    // MARK: - Run Share Card Section
    
    struct RunShareOverlay: View {
        let record: RunningRecord
        let avgPace: TimeInterval
        let paceData: [TSPoint]
        
        @Environment(\.overlayTextColor) private var textColor
        @Environment(\.overlaySubTextColor) private var subTextColor
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 20) {
                    statLabel(value: String(format: "%.2f", record.distance / 1000), unit: "km")
                    statLabel(value: formatDuration(record.duration), unit: "")
                    statLabel(value: formatPaceValue(avgPace), unit: "/km")
                }
                if !paceData.isEmpty {
                    Chart(paceData) { point in
                        LineMark(x: .value("시간", point.elapsed), y: .value("페이스", -point.value))
                            .foregroundStyle(DS.accent.gradient)
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("시간", point.elapsed), y: .value("페이스", -point.value))
                            .foregroundStyle(DS.accent.opacity(0.15).gradient)
                            .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartPlotBorderStyle(borderColor: subTextColor.opacity(0.28))
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 80)
                }
                Text(record.date.formatted(.dateTime.year().month().day().weekday(.wide)))
                    .font(.system(size: 10, weight: .light))
                    .tracking(1)
                    .foregroundStyle(subTextColor)
            }
        }
        
        private func statLabel(value: String, unit: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(textColor)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .light))
                        .tracking(0.5)
                        .foregroundStyle(subTextColor)
                }
            }
        }
    }
    
    // MARK: - Summary Metrics Share Overlay
    
    struct SummaryMetricsShareOverlay: View {
        let record: RunningRecord
        let avgPace: TimeInterval
        let avgHR: Double
        let avgCadence: Double
        let data: RunDetailViewModel.DetailData
        
        @Environment(\.overlayTextColor) private var textColor
        @Environment(\.overlaySubTextColor) private var subTextColor
        
        var body: some View {
            VStack(spacing: 24) {
                // 헤더: 거리
                VStack(spacing: 4) {
                    Text(record.isIndoor ? "INDOOR RUN" : "OUTDOOR RUN")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(subTextColor)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.2f", record.distance / 1000))
                            .font(.system(size: 56, weight: .ultraLight, design: .monospaced))
                        Text("km")
                            .font(.system(size: 16, weight: .light))
                    }
                    .foregroundStyle(textColor)
                }
                
                // 2x2 그리드 스탯
                let columns = [
                    GridItem(.flexible(), spacing: RunDetailLayout.summaryMetricColumnSpacing),
                    GridItem(.flexible(), spacing: RunDetailLayout.summaryMetricColumnSpacing)
                ]
                LazyVGrid(columns: columns, spacing: 16) {
                    SummaryMetricGridCell(label: "TIME", value: formatDuration(record.duration), isShareStyle: true)
                    SummaryMetricGridCell(label: "PACE", value: formatPaceValue(avgPace), isShareStyle: true)
                    SummaryMetricGridCell(label: "CADENCE", value: avgCadence > 0 ? String(format: "%.0f", avgCadence) : "--", isShareStyle: true)
                    SummaryMetricGridCell(label: "HEART RATE", value: avgHR > 0 ? String(format: "%.0f", avgHR) : "--", isShareStyle: true)
                }
                .padding(.horizontal, 8)
                
                // 미니 맵 경로 (실외일 경우)
                if !record.isIndoor && !data.altPoints.isEmpty {
                    let coords = data.altPoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    RunDetailRouteMapView(coordinates: coords, highlightCoordinate: nil)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .opacity(0.8)
                }
                
                Text(record.date.formatted(.dateTime.year().month().day().weekday(.wide)))
                    .font(.system(size: 10, weight: .light))
                    .tracking(1)
                    .foregroundStyle(subTextColor)
            }
            .padding(.horizontal, 10)
        }
    }
    
    // MARK: - Summary Lap Pace Share Overlay
    
    struct SummaryLapPaceShareOverlay: View {
        let record: RunningRecord
        let data: RunDetailViewModel.DetailData
        
        @Environment(\.overlayTextColor) private var textColor
        @Environment(\.overlaySubTextColor) private var subTextColor
        
        private var avgPace: Double {
            guard record.distance > 0 else { return 0 }
            return record.duration / (record.distance / 1000)
        }
        
        var body: some View {
            VStack(spacing: 24) {
                // 상단 요약 정보 (간략히)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(String(format: "%.2fkm", record.distance / 1000))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                    Text(formatDuration(record.duration))
                        .font(.system(size: 16, weight: .light, design: .monospaced))
                    Spacer()
                }
                .foregroundStyle(textColor)
                
                if !data.lapRows.isEmpty {
                    shareSplitPaceChart
                }
                
                Text(record.date.formatted(.dateTime.year().month().day().weekday(.wide)))
                    .font(.system(size: 10, weight: .light))
                    .tracking(1)
                    .foregroundStyle(subTextColor)
            }
            .padding(.horizontal, 10)
        }
        
        private var shareSplitPaceChart: some View {
            let worstPace: Double = data.lapRows.map(\.pace).max() ?? 0
            let bestPace: Double = data.lapRows.map(\.pace).min() ?? 0
            let bottomScore = min(paceChartScore(worstPace), paceChartScore(avgPace)) * 0.985
            let topScore = max(paceChartScore(bestPace), paceChartScore(avgPace)) * 1.04
            
            return VStack(alignment: .leading, spacing: 8) {
                Text("LAP PACE")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(subTextColor)
                
                Chart {
                    ForEach(data.lapRows) { split in
                        BarMark(
                            x: .value("Lap", split.label),
                            yStart: .value("floor", bottomScore),
                            yEnd: .value("PaceScore", paceChartScore(split.pace))
                        )
                        .foregroundStyle(DS.accent.opacity(split.pace == bestPace ? 1.0 : 0.8))
                    }
                    
                    RuleMark(y: .value("Average", paceChartScore(avgPace)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(subTextColor.opacity(0.6))
                }
                .chartYScale(domain: bottomScore...topScore)
                .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 18))
                .chartYAxis {
                    AxisMarks(
                        position: .leading,
                        values: [
                            paceChartScore(worstPace),
                            paceChartScore(avgPace),
                            paceChartScore(bestPace)
                        ]
                    ) { (value: AxisValue) in
                        AxisValueLabel {
                            if let score = value.as(Double.self) {
                                Text(formatPaceValue(pace(fromChartScore: score)))
                                    .font(.system(size: 8))
                                    .foregroundStyle(subTextColor)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { (value: AxisValue) in
                        if let lapStr = value.as(String.self) {
                            let labels = data.lapRows.map(\.label)
                            let isFirst = lapStr == labels.first
                            let isLast = lapStr == labels.last
                            let isEveryFive = labels.firstIndex(of: lapStr).map { ($0 + 1) % 5 == 0 } ?? false
                            if isFirst || isEveryFive || isLast {
                                AxisValueLabel {
                                    Text(lapStr)
                                        .font(.system(size: 8))
                                        .foregroundStyle(subTextColor)
                                }
                            }
                        }
                    }
                }
                .chartPlotBorderStyle(borderColor: subTextColor.opacity(0.35))
                .frame(height: 180)
            }
        }

        private func paceChartScore(_ pace: Double) -> Double {
            guard pace.isFinite, pace > 0 else { return 0 }
            return 1000.0 / pace
        }

        private func pace(fromChartScore score: Double) -> Double {
            guard score.isFinite, score > 0 else { return 0 }
            return 1000.0 / score
        }
    }
}

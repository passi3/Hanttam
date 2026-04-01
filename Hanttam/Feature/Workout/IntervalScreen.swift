//
//  IntervalScreen.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import SwiftUI

struct IntervalScreen: View {
    
    @State private var totalSets: Int = 0
    @State private var accumulatedAngle: Double = 0
    @State private var lastAngle: Double?
    @State private var dialSize: CGFloat = 0

    @State private var showSettings = false
    @State private var showIntervalRun = false

    @AppStorage("intervalLapDistance") private var lapDistance: Double = 400
    @AppStorage("intervalRestDuration") private var restDuration: Double = 20
    @ObservedObject private var levelManager = RunningLevelManager.shared

    private let setsPerRotation = 10

    // MARK: - Computed

    private var degPerSegment: Double { 360.0 / Double(setsPerRotation) }
    private var progressDeg: Double { accumulatedAngle.truncatingRemainder(dividingBy: 360) }
    private var progressFraction: Double { progressDeg / 360.0 }
    private var completedLaps: Int { Int(accumulatedAngle / 360) }
    private var activeSegments: Int {
        guard progressDeg > 0 else { return 0 }
        return min(Int(progressDeg / degPerSegment) + 1, setsPerRotation)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                headerSection
                ringSection
                bottomButtons
                Spacer()
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: activeSegments)
        .sensoryFeedback(.impact(weight: .heavy), trigger: totalSets / setsPerRotation)
        .sheet(isPresented: $showSettings) {
            IntervalSettingsView()
        }
        .fullScreenCover(isPresented: $showIntervalRun) {
            IntervalRunView(sets: totalSets, lapDistance: lapDistance, restDuration: restDuration)
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 6) {
            Group {
                if totalSets == 0 {
                    Text("인터벌 트레이닝")
                } else {
                    Text("\(totalSets)세트")
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.25), value: totalSets)
                }
            }
            .font(.system(size: 32, weight: .bold))

            Group {
                if totalSets == 0 {
                    Text("돌려서 세트 설정")
                } else {
                    Text("\(distanceLabel(lapDistance)) · \(Int(restDuration))초 휴식")
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(levelManager.accentColor)
            .kerning(2)
        }
        .padding(.bottom, 200)
    }

    private var ringSection: some View {
        let size: CGFloat = 280
        let holeSize: CGFloat = 130 * size / 200   // 182 — 원본 비율 유지
        let holeOffY: CGFloat = -25 * size / 200   // -35

        return ZStack {
            // 1. 바닥 트랙
            PunchedBigCircle(holeSize: holeSize, holeOffsetY: holeOffY)
                .fill(Color(red: 151/255, green: 42/255, blue: 0).opacity(0.4),
                      style: FillStyle(eoFill: true))
                .frame(width: size, height: size)

            // 2. 색 누적 레이어 — plusLighter로 쌓일수록 흰색에 가까워짐
            ZStack {
                ForEach(0..<min(completedLaps, 10), id: \.self) { _ in
                    PunchedBigCircle(holeSize: holeSize, holeOffsetY: holeOffY)
                        .fill(levelManager.accentColor.opacity(0.5),
                              style: FillStyle(eoFill: true))
                        .blendMode(.plusLighter)
                        .frame(width: size, height: size)
                }

                // 현재 진행 레이어 (angular mask)
                PunchedBigCircle(holeSize: holeSize, holeOffsetY: holeOffY)
                    .fill(levelManager.accentColor.opacity(0.8),
                          style: FillStyle(eoFill: true))
                    .blendMode(.plusLighter)
                    .mask {
                        if progressFraction >= 1.0 {
                            Rectangle()
                        } else {
                            AngularGradient(
                                stops: [
                                    .init(color: .white, location: 0),
                                    .init(color: .white, location: progressFraction),
                                    .init(color: .clear, location: progressFraction),
                                    .init(color: .clear, location: 1)
                                ],
                                center: .center,
                                angle: .degrees(-90)
                            )
                        }
                    }
                    .frame(width: size, height: size)
            }
            .drawingGroup()  // 레이어 간 누적 블렌딩이 올바르게 합성되도록

            // 4. 센터: 세트 카운트 또는 플레이
            Group {
                if totalSets == 0 {
                    Image(systemName: "play.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                } else {
                    VStack(spacing: 2) {
                        Text("\(totalSets)")
                            .font(.system(size: 54, weight: .thin, design: .monospaced))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.25), value: totalSets)
                            .monospacedDigit()
                        Text("S E T")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .kerning(4)
                    }
                }
            }
            .offset(y: holeOffY / 2)
            .onTapGesture {
                if totalSets > 0 {
                    showIntervalRun = true
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in handleDrag(v.location, frameSize: size) }
                .onEnded   { _ in lastAngle = nil }
        )
    }

    private var bottomButtons: some View {
        HStack(spacing: 24) {
            // 리셋
            Button(action: reset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, height: 52)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }

            // 설정
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, height: 52)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
        }
        .padding(.top, 48)
    }

    // MARK: - Gesture

    private func handleDrag(_ location: CGPoint, frameSize: CGFloat) {
        let center = CGPoint(x: frameSize / 2, y: frameSize / 2)
        var angle  = atan2(location.y - center.y, location.x - center.x) * 180 / .pi + 90
        if angle < 0    { angle += 360 }
        if angle >= 360 { angle -= 360 }

        defer { lastAngle = angle }
        guard let last = lastAngle else { return }

        var delta = angle - last
        if delta >  180 { delta -= 360 }
        if delta < -180 { delta += 360 }

        accumulatedAngle = max(0, accumulatedAngle + delta)

        let newSets = Int(accumulatedAngle / degPerSegment)
        if newSets != totalSets {
            withAnimation(.spring(duration: 0.2)) { totalSets = newSets }
        }
    }

    // MARK: - Reset

    private func reset() {
        withAnimation(.spring(duration: 0.35)) {
            accumulatedAngle = 0
            totalSets        = 0
        }
        lastAngle = nil
    }

    // MARK: - Helpers

    private func distanceLabel(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.0fkm", meters / 1000)
        }
        return String(format: "%.0fm", meters)
    }
}

struct IntervalSettingsView: View {

    @AppStorage("intervalLapDistance") private var lapDistance: Double = 400
    @AppStorage("intervalRestDuration") private var restDuration: Double = 20

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var levelManager = RunningLevelManager.shared

    private let distancePresets: [Double] = [200, 400, 800, 1000, 1600]

    var body: some View {
        NavigationView {
            List {
                // 랩 거리
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(distancePresets, id: \.self) { d in
                                Button {
                                    lapDistance = d
                                } label: {
                                    Text(distanceLabel(d))
                                        .font(.system(size: 15, weight: .medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            lapDistance == d
                                                ? levelManager.accentColor.opacity(0.15)
                                                : Color(AppColor.UI.tertiarySystemFill)
                                        )
                                        .foregroundStyle(lapDistance == d ? levelManager.accentColor : .primary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("랩 거리")
                }

                // 쉬는 시간
                Section {
                    Stepper("쉬는 시간: \(Int(restDuration))초", value: $restDuration, in: 5...120, step: 5)
                } header: {
                    Text("휴식")
                }
            }
            .navigationTitle("인터벌 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(levelManager.accentColor)
                }
            }
        }
    }

    private func distanceLabel(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.0fkm", meters / 1000)
        }
        return String(format: "%.0fm", meters)
    }
}

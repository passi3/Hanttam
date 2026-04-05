//
//  IntervalScreen.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import SwiftUI

struct IntervalScreen: View {
    
    @Binding var totalSets: Int
    @State private var accumulatedAngle: Double = 0
    @State private var lastAngle: Double?
    @State private var showSettings = false
    @Binding var showIntervalRun: Bool

    @AppStorage("intervalLapDistance") private var lapDistance: Double = 400
    @AppStorage("intervalRestDuration") private var restDuration: Double = 20
    @ObservedObject private var levelManager = RunningLevelManager.shared

    private let setsPerRotation = 10
    private let ringSize: CGFloat = 280

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
                headerSection
                ringSection
                bottomButtons
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: activeSegments)
        .sensoryFeedback(.impact(weight: .heavy), trigger: totalSets / setsPerRotation)
        .sheet(isPresented: $showSettings) {
            IntervalSettingsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchBridge.workoutStartedNotification)) { note in
            guard let kindRaw = note.userInfo?["kind"] as? String,
                  kindRaw == WatchBridge.WorkoutKind.intervalRun.rawValue else { return }
            showIntervalRun = true
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
            .font(AppFont.displaySM)
            .foregroundStyle(AppColor.textPrimary)

            Group {
                if totalSets == 0 {
                    Text("돌려서 세트 설정")
                } else {
                    Text("\(distanceLabel(lapDistance)) · \(Int(restDuration))초 휴식")
                }
            }
            .font(AppFont.labelSM)
            .foregroundStyle(levelManager.accentColor)
            .kerning(2)
        }
        .padding(.bottom, 16)
    }

    private var ringSection: some View {
        let baseColor = AppColor.hanttamRing
        let prevWhite = min(Double(max(completedLaps - 1, 0)) / 10.0, 1.0)
        let currWhite = min(Double(completedLaps) / 10.0, 1.0)
        let prevColor = levelManager.accentColor.mix(with: .white, by: prevWhite)
        let currColor = levelManager.accentColor.mix(with: .white, by: currWhite)
        let holeOffY: CGFloat = -25 * ringSize / 200

        return ZStack {
            // 1. 바닥 트랙 (항상 play 아이콘 표시)
            HanttamCirclesView(
                size: ringSize,
                color: baseColor.opacity(0.4),
                icon: "play.fill"
            )

            // 2. 완료된 랩 — 꽉 찬 링 (이전 랩 색상)
            if completedLaps > 0 {
                HanttamCirclesView(size: ringSize, color: prevColor)
            }

            // 3. 현재 진행 중인 랩 (현재 랩 색상 + angular mask)
            HanttamCirclesView(size: ringSize, color: currColor)
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

            // 4. 센터: play 버튼 (세트 설정 시 탭으로 시작)
            if totalSets > 0 {
                Color.clear
                    .frame(width: 130 * ringSize / 200, height: 130 * ringSize / 200)
                    .offset(y: holeOffY / 2)
                    .contentShape(Circle())
                    .onTapGesture {
                        startIntervalWorkout()
                    }
            }
        }
        .frame(width: ringSize, height: ringSize)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in handleDrag(v.location, frameSize: ringSize) }
                .onEnded   { _ in lastAngle = nil }
        )
    }

    private var bottomButtons: some View {
        HStack(spacing: 24) {
            // 리셋
            Button(action: reset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(AppFont.titleLG)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 52, height: 52)
                    .background(AppColor.chipBackground, in: Circle())
            }

            // 설정
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(AppFont.titleLG)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 52, height: 52)
                    .background(AppColor.chipBackground, in: Circle())
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 48)
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

    private func startIntervalWorkout() {
        let payload: [String: Any] = [
            "sets": totalSets,
            "lapDistance": lapDistance,
            "restDuration": restDuration
        ]

        WatchBridge.shared.requestWorkoutStartOnWatch(kind: .intervalRun, payload: payload)
        showIntervalRun = true
    }
}

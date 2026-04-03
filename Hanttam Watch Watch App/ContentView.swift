//
//  ContentView.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/1/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selection = 0
    @State private var totalSets: Int = 0
    @State private var crownValue: Double = 0
    @State private var showRun = false
    @State private var showIntervalRun = false

    @AppStorage("intervalLapDistance") private var lapDistance: Double = 400
    @AppStorage("intervalRestDuration") private var restDuration: Double = 20

    var body: some View {
        Group {
            if selection == 0 {
                WatchButtonScreen(selection: $selection, showRun: $showRun)
            } else {
                WatchDialPage(
                    selection: $selection,
                    totalSets: $totalSets,
                    crownValue: $crownValue,
                    showIntervalRun: $showIntervalRun
                )
            }
        }
        .fullScreenCover(isPresented: $showRun) {
            WatchFreeRunView()
        }
        .fullScreenCover(isPresented: $showIntervalRun) {
            WatchIntervalRunView(
                sets: totalSets,
                lapDistance: lapDistance,
                restDuration: restDuration
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchBridge.workoutStartedNotification)) { _ in
            showRun = true
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchBridge.workoutStoppedNotification)) { _ in
            showRun = false
            showIntervalRun = false
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchBridge.workoutLaunchRequestedNotification)) { note in
            guard let kindRaw = note.userInfo?["kind"] as? String,
                  let kind = WatchBridge.WorkoutKind(rawValue: kindRaw) else { return }

            switch kind {
            case .freeRun:
                selection = 0
                showIntervalRun = false
                showRun = true

            case .intervalRun:
                if let sets = note.userInfo?["sets"] as? Int {
                    totalSets = sets
                }
                if let lapDistance = note.userInfo?["lapDistance"] as? Double {
                    self.lapDistance = lapDistance
                }
                if let restDuration = note.userInfo?["restDuration"] as? Double {
                    self.restDuration = restDuration
                }
                selection = 1
                showRun = false
                showIntervalRun = true
            }
        }
    }
}

// MARK: - Dial Page

struct WatchDialPage: View {
    @Binding var selection: Int
    @Binding var totalSets: Int
    @Binding var crownValue: Double
    @Binding var showIntervalRun: Bool

    @AppStorage("intervalLapDistance") private var lapDistance: Double = 400
    @AppStorage("intervalRestDuration") private var restDuration: Double = 20
    @ObservedObject private var levelManager = RunningLevelManager.shared

    var body: some View {
        ZStack {
            VStack(spacing: 4) {
                Text(totalSets == 0 ? "세트 설정" : "\(totalSets)세트")
                    .font(.system(size: 16, weight: .bold))
                    .contentTransition(.numericText())

                ZStack {
                    // 바닥 트랙 (세트 0일 때 crown 아이콘 포함)
                    HanttamCirclesView(
                        size: 130,
                        color: Color(red: 151/255, green: 42/255, blue: 0).opacity(0.4),
                        icon: totalSets == 0 ? "crown" : nil,
                        iconColor: levelManager.accentColor.opacity(0.5)
                    )

                    // 진행 링
                    let progress = crownValue.truncatingRemainder(dividingBy: 1.0)
                    HanttamCirclesView(size: 130, color: levelManager.accentColor)
                        .mask {
                            if progress >= 1.0 || progress <= 0 {
                                Rectangle()
                                    .opacity(progress >= 1.0 ? 1 : 0)
                            } else {
                                AngularGradient(
                                    stops: [
                                        .init(color: .white, location: 0),
                                        .init(color: .white, location: progress),
                                        .init(color: .clear, location: progress),
                                        .init(color: .clear, location: 1)
                                    ],
                                    center: .center,
                                    angle: .degrees(-90)
                                )
                            }
                        }

                    // 세트 카운트
                    if totalSets > 0 {
                        VStack(spacing: 0) {
                            Text("\(totalSets)")
                                .font(.system(size: 32, weight: .thin, design: .monospaced))
                            Text("SET")
                                .font(.system(size: 8, weight: .medium))
                                .opacity(0.6)
                        }
                        .offset(y: -25 * 130 / 200 / 2)
                    }
                }
                .frame(width: 130, height: 130)
                #if os(watchOS)
                .focusable()
                .digitalCrownRotation(
                    $crownValue,
                    from: 0,
                    through: 100,
                    by: 0.01,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                #endif
                .onChange(of: crownValue) { _, newValue in
                    let newSets = Int(max(0, newValue) * 10)
                    if newSets != totalSets {
                        totalSets = newSets
                    }
                }
                .onTapGesture {
                    if totalSets > 0 {
                        showIntervalRun = true
                    }
                }

                // 설정 요약
                if totalSets > 0 {
                    Text("\(distanceLabel(lapDistance)) · \(Int(restDuration))초")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("INTERVAL")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(levelManager.accentColor)
                }
            }

            // 좌하단: Free run으로 전환
            Button { selection = 0 } label: {
                Image(systemName: "figure.run")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(levelManager.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 4)
            .padding(.bottom, 4)

            // 우하단: 시작 버튼 (세트 설정 시)
            if totalSets > 0 {
                Button { showIntervalRun = true } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(levelManager.accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 4)
                .padding(.bottom, 4)
            }
        }
    }

    private func distanceLabel(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.0fkm", meters / 1000) : String(format: "%.0fm", meters)
    }
}

#Preview {
    ContentView()
}

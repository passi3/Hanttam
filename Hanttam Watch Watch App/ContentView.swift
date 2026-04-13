//
//  ContentView.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/1/26.
//

import SwiftUI
internal import HealthKit

struct ContentView: View {
    private enum WatchRoute {
        case homeFreeRun
        case homeIntervalSetup
        case freeRunWorkout(skipCountdown: Bool)
        case intervalWorkout(sets: Int, lapDistance: Double, restDuration: TimeInterval, skipCountdown: Bool)
        case workoutSummary(WatchWorkoutSummaryData)
    }

    @State private var selection = 0
    @State private var totalSets: Int = 0
    @State private var crownValue: Double = 0
    @State private var route: WatchRoute = .homeFreeRun

    @AppStorage("intervalLapDistance") private var lapDistance: Double = 400
    @AppStorage("intervalRestDuration") private var restDuration: Double = 20

    var body: some View {
        Group {
            switch route {
            case .homeFreeRun, .homeIntervalSetup:
                WatchDialPage(
                    selection: $selection,
                    totalSets: $totalSets,
                    crownValue: $crownValue,
                    startIntervalRun: startIntervalRun
                )
                .overlay {
                    if selection == 0 {
                        WatchButtonScreen(selection: $selection, startFreeRun: startFreeRun)
                    }
                }
            case .freeRunWorkout(let skipCountdown):
                WatchFreeRunView(skipCountdown: skipCountdown, onFinish: showSummary)
            case .intervalWorkout(let sets, let lapDistance, let restDuration, let skipCountdown):
                WatchIntervalRunView(
                    sets: sets,
                    lapDistance: lapDistance,
                    restDuration: restDuration,
                    skipCountdown: skipCountdown,
                    onFinish: showSummary
                )
            case .workoutSummary(let data):
                WatchWorkoutSummaryView(
                    data: data,
                    onBack: returnToHome,
                    onFinishReview: returnToHome
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchBridge.workoutStartedNotification)) { _ in
            if case .homeIntervalSetup = route {
                route = .freeRunWorkout(skipCountdown: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchBridge.workoutStoppedNotification)) { _ in
            returnToHome()
        }
        .onAppear(perform: presentPendingStartIfNeeded)
        .onReceive(NotificationCenter.default.publisher(for: WatchBridge.workoutLaunchRequestedNotification)) { _ in
            presentPendingStartIfNeeded()
        }
        .onChange(of: selection) { _, newValue in
            if case .homeFreeRun = route, newValue == 1 {
                route = .homeIntervalSetup
            } else if case .homeIntervalSetup = route, newValue == 0 {
                route = .homeFreeRun
            }
        }
    }

    private func presentPendingStartIfNeeded() {
        guard let request = WatchBridge.shared.consumePendingStartRequest() else { return }

        switch request.kind {
        case .freeRun:
            selection = 0
            route = .freeRunWorkout(skipCountdown: request.skipCountdown)

        case .intervalRun:
            if let sets = request.sets {
                totalSets = sets
            }
            if let lapDistance = request.lapDistance {
                self.lapDistance = lapDistance
            }
            if let restDuration = request.restDuration {
                self.restDuration = restDuration
            }
            selection = 1
            route = .intervalWorkout(
                sets: totalSets,
                lapDistance: lapDistance,
                restDuration: restDuration,
                skipCountdown: request.skipCountdown
            )
        }
    }

    private func startFreeRun() {
        selection = 0
        route = .freeRunWorkout(skipCountdown: false)
    }

    private func startIntervalRun() {
        guard totalSets > 0 else { return }
        selection = 1
        route = .intervalWorkout(
            sets: totalSets,
            lapDistance: lapDistance,
            restDuration: restDuration,
            skipCountdown: false
        )
    }

    private func returnToHome() {
        route = selection == 0 ? .homeFreeRun : .homeIntervalSetup
    }

    private func showSummary(_ data: WatchWorkoutSummaryData) {
        route = .workoutSummary(data)
    }
}

// MARK: - Dial Page

struct WatchDialPage: View {
    @Binding var selection: Int
    @Binding var totalSets: Int
    @Binding var crownValue: Double
    let startIntervalRun: () -> Void

    @AppStorage("intervalLapDistance") private var lapDistance: Double = 400
    @AppStorage("intervalRestDuration") private var restDuration: Double = 20
    @ObservedObject private var levelManager = RunningLevelManager.shared

    var body: some View {
        ZStack {
            VStack(spacing: 4) {
                Text(totalSets == 0 ? "인터벌 러닝" : "\(totalSets)세트")
                    .font(.system(size: 16, weight: .bold))
                    .contentTransition(.numericText())

                ZStack {
                    // 바닥 트랙 (세트 0일 때 crown 아이콘 포함)
                    WatchHanttamBrandLogoRing(
                        size: 130,
                        color: Color(red: 151/255, green: 42/255, blue: 0).opacity(0.4),
                        icon: totalSets == 0 ? "crown" : "play",
                        iconColor: totalSets == 0 ? AppColor.workoutBg : levelManager.accentColor
                    )

                    // 진행 링
                    let progress = crownValue.truncatingRemainder(dividingBy: 1.0)
                    WatchHanttamBrandLogo(size: 130, color: levelManager.accentColor)
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
                        startIntervalRun()
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

            Button { selection = 0 } label: {
                Image(systemName: "figure.run")
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

    private func distanceLabel(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.0fkm", meters / 1000) : String(format: "%.0fm", meters)
    }
}

#Preview {
    ContentView()
}

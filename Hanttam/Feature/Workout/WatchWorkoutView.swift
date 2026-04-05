//
//  WatchWorkoutView.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import SwiftUI

struct WatchWorkoutView: View {
    @State private var selection = 0
    @ObservedObject private var levelManager = RunningLevelManager.shared
    
    // Dial State
    @State private var totalSets: Int = 0
    @State private var crownValue: Double = 0
    
    var body: some View {
        TabView(selection: $selection) {
            // 1. 시작 버튼 화면 (ButtonScreen 대응)
            WatchButtonPage()
                .tag(0)
            
            // 2. 세트 설정 화면 (DialScreen 대응)
            WatchDialPage(totalSets: $totalSets, crownValue: $crownValue)
                .tag(1)
        }
        .tabViewStyle(.page)
    }
}

// MARK: - Button Page
struct WatchButtonPage: View {
    @ObservedObject private var levelManager = RunningLevelManager.shared
    
    var body: some View {
        VStack(spacing: 4) {
            Text("자유 목표")
                .font(.system(size: 16, weight: .medium))
            
            ZStack {
                WorkoutRingView(color: levelManager.accentColor)
                    .frame(width: 130, height: 130)
                
                Image(systemName: "play.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .offset(y: -11) // 워치 크기에 맞춰 오프셋 조정
            }
            
            Text("FREE RUN")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(levelManager.accentColor)
        }
    }
}

// MARK: - Dial Page
struct WatchDialPage: View {
    @Binding var totalSets: Int
    @Binding var crownValue: Double
    @ObservedObject private var levelManager = RunningLevelManager.shared
    
    private let stepsPerRotation = 10.0
    
    var body: some View {
        VStack(spacing: 4) {
            Text(totalSets == 0 ? "횟수 설정" : "\(totalSets)회")
                .font(.system(size: 16, weight: .bold))
                .contentTransition(.numericText())
            
            ZStack {
                // 배경 링
                WorkoutRingView(color: Color.brown.opacity(0.3))
                    .frame(width: 130, height: 130)
                
                // 진행 링 (크라운 값에 연동)
                WorkoutRingView(
                    progress: crownValue.truncatingRemainder(dividingBy: 1.0),
                    color: levelManager.accentColor,
                    additive: true
                )
                .frame(width: 130, height: 130)
                
                // 카운트 표시
                VStack(spacing: 0) {
                    Text("\(totalSets)")
                        .font(.system(size: 32, weight: .thin, design: .monospaced))
                    Text("SET")
                        .font(.system(size: 8, weight: .medium))
                        .opacity(0.6)
                }
                .frame(width: 130, height: 130)
                #if os(watchOS)
                .focusable()
                .digitalCrownRotation(
                    $crownValue,
                    from: 0,
                    through: 10, // 10바퀴까지
                    by: 0.01,
                    sensitivity: .medium,
                    isContinuous: true,
                    isHapticFeedbackEnabled: true
                )
                #endif
                .onChange(of: crownValue) { oldValue, newValue in
                    // 1.0(한 바퀴)마다 10세트씩 증가하는 로직
                    let newSets = Int(newValue * 10)
                    if newSets != totalSets {
                        totalSets = newSets
                    }
                }
            }
            
            Text("INTERVAL")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(levelManager.accentColor)
        }
    }
}

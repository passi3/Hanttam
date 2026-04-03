//
//  FreeRunScreen.swift
//  Hanttam
//
//  Created by passi on 3/31/26.
//

import SwiftUI

struct FreeRunScreen: View {
    
    @Binding var showFreeRun: Bool
    @ObservedObject private var levelManager = RunningLevelManager.shared
    @State private var isPressed             = false
    @State private var holeOffsetY: CGFloat  = -25
    
    private let ringSize: CGFloat            = 280
    
    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                headerSection
                ringButton
                bottomButtons
                Spacer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchBridge.workoutStartedNotification)) { note in
            guard let kindRaw = note.userInfo?["kind"] as? String,
                  kindRaw == WatchBridge.WorkoutKind.freeRun.rawValue else { return }
            showFreeRun = true
        }
    }
    
    //MARK: - Subviews
    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("자유 목표")
                .font(.system(size: 32, weight: .bold))

            Text("FREE RUN")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(levelManager.accentColor)
                .kerning(4)
        }
        .padding(.bottom, 16)
    }
    
    private var ringButton: some View {
        HanttamCirclesView(
            topCircleOffsetY: holeOffsetY,
            size: ringSize,
            icon: "play.fill"
        )
        .scaleEffect(isPressed ? 0.93 : 1.0)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeIn(duration: 0.08)) {
                        isPressed = true
                        holeOffsetY = -10
                    }
                }
                .onEnded { v in
                    withAnimation(.spring(duration: 0.3)) {
                        isPressed = false
                        holeOffsetY = -25
                    }
                    if abs(v.translation.width) < 10 && abs(v.translation.height) < 10 {
                        if !WatchBridge.shared.requestWorkoutStartOnWatch(kind: .freeRun) {
                            showFreeRun = true
                        }
                    }
                }
        )
    }

    private var bottomButtons: some View {
        // DialScreen의 bottomButtons와 동일한 높이 확보
        Color.clear
            .frame(height: 52)
            .padding(.top, 24)
            .padding(.bottom, 48)
    }}

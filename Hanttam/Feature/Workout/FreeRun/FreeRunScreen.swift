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
    
    private let ringSize: CGFloat            = 280
    
    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                ringButton
                bottomButtons
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
        Button {
            WatchBridge.shared.requestWorkoutStartOnWatch(kind: .freeRun)
            showFreeRun = true
        } label: {
            HanttamCirclesView(
                topCircleOffsetY: -25,
                size: ringSize,
                icon: "play.fill"
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var bottomButtons: some View {
        // DialScreen의 bottomButtons와 동일한 높이 확보
        Color.clear
            .frame(height: 52)
            .padding(.top, 24)
            .padding(.bottom, 48)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.easeIn(duration: 0.1), value: configuration.isPressed)
    }
}

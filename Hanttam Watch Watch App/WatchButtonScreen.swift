//
//  WatchButtonScreen.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/1/26.
//

import SwiftUI

struct WatchButtonScreen: View {

    @Binding var selection: Int
    let startFreeRun: () -> Void
    @State private var isPressed = false
    @ObservedObject private var levelManager = RunningLevelManager.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 4) {
                Text("자유 목표")
                    .font(.system(size: 16, weight: .medium))

                HanttamCirclesView(size: 130, icon: "play", iconColor: levelManager.accentColor)
                .scaleEffect(isPressed ? 0.93 : 1.0)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            withAnimation(.easeIn(duration: 0.08)) { isPressed = true }
                        }
                        .onEnded { v in
                            withAnimation(.spring(duration: 0.3)) { isPressed = false }
                            if abs(v.translation.width) < 10 && abs(v.translation.height) < 10 {
                                startFreeRun()
                            }
                        }
                )

                Text("FREE RUN")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(levelManager.accentColor)
            }

            Button { selection = 1 } label: {
                Image(systemName: "timer")
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

#Preview {
    WatchButtonScreen(selection: .constant(0), startFreeRun: {})
}

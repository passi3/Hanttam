//
//  FreeRunScreen.swift
//  Hanttam
//
//  Created by passi on 3/31/26.
//

import SwiftUI

struct FreeRunScreen: View {
    
    @ObservedObject private var levelManager = RunningLevelManager.shared
    @State private var isPressed             = false
    @State private var showFreeRun           = false
    
    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                headerSection
                ringButton
                bottomSpacer
                Spacer()
            }
        }
        .fullScreenCover(isPresented: $showFreeRun) {
            FreeRunView()
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
        .padding(.bottom, 200)
    }
    
    private var ringButton: some View {
        ZStack {
            
            let size: CGFloat = 280
            let holeSize: CGFloat = 130 * size / 200   // 182 — 원본 비율 유지
            let holeOffY: CGFloat = -25 * size / 200   // -35
            
            PunchedBigCircle(holeSize: holeSize, holeOffsetY: holeOffY)
                .fill(Color(red: 151/255, green: 42/255, blue: 0).opacity(0.4),
                      style: FillStyle(eoFill: true))
                .frame(width: size, height: size)

            ZStack {
                // Border 처리
                Image(systemName: "play")
                    .font(.system(size: 44))
                    .foregroundStyle(levelManager.accentColor.opacity(0.4))
                // Foreground icon on top
                Image(systemName: "play")
                    .font(.system(size: 36))
                    .foregroundStyle(levelManager.accentColor)
            }
            .offset(y: -30)
        }
        .scaleEffect(isPressed ? 0.93 : 1.0)
    }
    
    private var bottomSpacer: some View {
        Color.clear
            .frame(width: 52, height: 52)
            .padding(.top, 48)
    }
}

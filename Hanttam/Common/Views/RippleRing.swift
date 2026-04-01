//
//  RippleRing.swift
//  Hanttam
//
//  Created by passi on 3/30/26.
//

import SwiftUI

// MARK: - Configuration

/// 개별 링의 레이아웃 파라미터
struct RingConfig: Identifiable {
    let id: Int
    let level: UserRunningLevel
    let outerDiameter: CGFloat
    let innerDiameter: CGFloat
    let holeOffset: CGFloat
    let initialYOffset: CGFloat
}

// MARK: - Shapes

/// 펀치홀이 뚫린 타원형 링
struct RippleBaseRing: Shape {
    let outerDiameter: CGFloat
    let innerDiameter: CGFloat
    let holeOffset: CGFloat
    let heightRatio: CGFloat
    let holeInset: CGFloat

    var yOffset: CGFloat

    var animatableData: CGFloat {
        get { yOffset }
        set { yOffset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = outerDiameter / 2
        let outerHeight = outerDiameter * heightRatio

        var path = Path()

        // 외곽 타원
        path.addEllipse(in: CGRect(
            x: center.x - outerRadius,
            y: center.y - outerHeight / 2 + yOffset,
            width: outerDiameter,
            height: outerHeight
        ))

        // 펀치홀 (holeOffset > 0일 때만)
        if holeOffset > 0 {
            let holeDiameter = innerDiameter + 2.8 * holeOffset
            let holeRadius = holeDiameter / 2
            let holeHeight = holeDiameter * heightRatio

            path.addEllipse(in: CGRect(
                x: center.x - holeRadius + holeInset,
                y: center.y - holeHeight / 2 + (holeInset * 4 / 15) + yOffset,
                width: holeDiameter - holeInset * 2,
                height: holeHeight - (holeInset * 8 / 15)
            ))
        }

        return path
    }
}

/// 중앙에 올려지는 솔리드 타원
struct RippleTopEllipse: Shape {
    let diameter: CGFloat
    let heightRatio: CGFloat

    var yOffset: CGFloat

    var animatableData: CGFloat {
        get { yOffset }
        set { yOffset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = diameter / 2
        let height = diameter * heightRatio

        var path = Path()
        path.addEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - height / 2 + yOffset,
            width: diameter,
            height: height
        ))
        return path
    }
}

// MARK: - Main View

struct RippleRingView: View {

    /// nil → 모든 링 activeOpacity로 표시 (기본 동작).
    /// 특정 등급 지정 → 해당 링만 풀 컬러, 나머지는 dimmedOpacity.
    var highlightedLevel: UserRunningLevel? = nil
    var onAnimationComplete: (() -> Void)? = nil

    // MARK: Layout Constants

    private let baseOuterD: CGFloat = 200
    private let baseInnerD: CGFloat = 100
    private let baseHoleOffset: CGFloat = 30
    private let heightRatio: CGFloat = 0.4
    private let holeInset: CGFloat = 15
    private let frameSize = CGSize(width: 260, height: 150)

    private let activeOpacity: Double = 1.0
    private let dimmedOpacity: Double = 0.1

    // MARK: Ring Definitions

    private var ringConfigs: [RingConfig] {
        [
            RingConfig(id: 0, level: .yellow, outerDiameter: baseOuterD + 100, innerDiameter: baseInnerD + 110,
                       holeOffset: baseHoleOffset, initialYOffset: 1),
            RingConfig(id: 1, level: .orange, outerDiameter: baseOuterD + 70,  innerDiameter: baseInnerD + 80,
                       holeOffset: baseHoleOffset, initialYOffset: -2),
            RingConfig(id: 2, level: .green,  outerDiameter: baseOuterD + 40,  innerDiameter: baseInnerD + 50,
                       holeOffset: baseHoleOffset, initialYOffset: -5),
            RingConfig(id: 3, level: .blue,   outerDiameter: baseOuterD + 10,  innerDiameter: baseInnerD + 50,
                       holeOffset: baseHoleOffset - 10, initialYOffset: -8),
            RingConfig(id: 4, level: .purple, outerDiameter: baseOuterD - 20,  innerDiameter: baseInnerD + 20,
                       holeOffset: baseHoleOffset - 10, initialYOffset: -11),
            RingConfig(id: 5, level: .black,  outerDiameter: baseOuterD - 50,  innerDiameter: baseInnerD + 20,
                       holeOffset: baseHoleOffset - 20, initialYOffset: -14),
            RingConfig(id: 6, level: .volt,   outerDiameter: baseOuterD - 80,  innerDiameter: baseInnerD - 10,
                       holeOffset: baseHoleOffset - 20, initialYOffset: -17),
        ]
    }

    private let centerEllipseDiameter: CGFloat = 80

    // MARK: Animation State

    @State private var animatedOffsets: [CGFloat] = [1, -5, -8, -11, -14, -17, -20, -30]
    @State private var hasAppeared = false

    // MARK: Body

    var body: some View {
        ZStack {
            ForEach(ringConfigs) { config in
                ringLayer(for: config)
                    .zIndex(Double(config.id))
            }

            centerEllipse
                .zIndex(Double(ringConfigs.count))
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            startRippleAnimation()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func ringLayer(for config: RingConfig) -> some View {
        RippleBaseRing(
            outerDiameter: config.outerDiameter,
            innerDiameter: config.innerDiameter,
            holeOffset: config.holeOffset,
            heightRatio: heightRatio,
            holeInset: holeInset,
            yOffset: animatedOffsets[config.id]
        )
        .stroke(.white, lineWidth: 1)
        .fill(
            config.level.swiftUIColor.opacity(opacity(for: config.level)),
            style: FillStyle(eoFill: true)
        )
    }

    private var centerEllipse: some View {
        RippleTopEllipse(
            diameter: centerEllipseDiameter,
            heightRatio: heightRatio,
            yOffset: animatedOffsets[ringConfigs.count]
        )
        .stroke(.white, lineWidth: 1)
        .fill(AppColor.border)
    }

    // MARK: - Opacity

    private func opacity(for level: UserRunningLevel) -> Double {
        guard let highlighted = highlightedLevel else {
            return activeOpacity
        }
        return level == highlighted ? activeOpacity : dimmedOpacity
    }

    // MARK: - Animation

    private func startRippleAnimation() {
        let totalCount = animatedOffsets.count
        let delayPerRing: Double = 0.12
        let toZeroDuration: Double = 0.25
        let returnDuration: Double = 0.35

        let originalOffsets = animatedOffsets

        for i in 0..<totalCount {
            let targetIndex = totalCount - 1 - i
            let delay = Double(i) * delayPerRing

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeIn(duration: toZeroDuration)) {
                    animatedOffsets[targetIndex] = 0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + delay + toZeroDuration) {
                withAnimation(.easeOut(duration: returnDuration)) {
                    animatedOffsets[targetIndex] = originalOffsets[targetIndex]
                }

                if i == totalCount - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + returnDuration) {
                        onAnimationComplete?()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("기본 (전체 활성)") {
    RippleRingView()
}

#Preview("Blue 등급 강조") {
    RippleRingView(highlightedLevel: .blue)
}

#Preview("Volt 등급 강조") {
    RippleRingView(highlightedLevel: .black)
}

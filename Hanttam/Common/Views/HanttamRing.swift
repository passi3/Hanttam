//
//  HanttamRing.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import SwiftUI

// MARK: - 특정 위치와 크기만큼 구멍이 뚫린 큰 원 Shape
struct PunchedBigCircle: Shape {
    var holeSize: CGFloat
    var holeOffsetY: CGFloat

    var animatableData: CGFloat {
        get { holeOffsetY }
        set { holeOffsetY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.addEllipse(in: rect)

        let cx = rect.midX
        let cy = rect.midY
        let holeR = holeSize / 2

        let holeRect = CGRect(x: cx - holeR,
                              y: cy - holeR + holeOffsetY,
                              width: holeSize,
                              height: holeSize)

        path.addEllipse(in: holeRect)

        return path
    }
}

// MARK: - 메인 뷰
struct HanttamCirclesView: View {
    var topCircleOffsetY: CGFloat = -25
    var size: CGFloat = 200
    var color: Color = AppColor.hanttamRing

    // hole 내부 아이콘 / 보더 (nil이면 표시 안 함)
    var icon: String? = nil
    var iconColor: Color = RunningLevelManager.shared.accentColor

    private var holeSize: CGFloat { 130 * size / 200 }
    private var holeOffY: CGFloat { topCircleOffsetY * size / 200 }
    private var iconSize: CGFloat { size * 32 / 280 }

    var body: some View {
        ZStack {
            PunchedBigCircle(holeSize: holeSize, holeOffsetY: holeOffY)
                .fill(color, style: FillStyle(eoFill: true))
                .frame(width: size, height: size)

            if let icon {

                // 글로우 레이어
                Image(systemName: icon)
                    .font(.system(size: iconSize * 1.3, weight: .medium, design: .default))
                    .foregroundStyle(iconColor.opacity(0.8))
                    .blur(radius: iconSize * 0.4)
                    .offset(y: holeOffY / 2)

                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .medium, design: .default))
                    .foregroundStyle(iconColor)
                    .offset(y: holeOffY / 2)
            }
        }
        .frame(width: size, height: size)
    }
}

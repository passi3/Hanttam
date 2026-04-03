//
//  WatchHanttamRing.swift
//  Hanttam Watch Watch App
//
//  Created by passi on 4/3/26.
//

import SwiftUI

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

struct HanttamCirclesView: View {
    var topCircleOffsetY: CGFloat = -25
    var size: CGFloat = 130
    var color: Color = Color(red: 151/255, green: 42/255, blue: 0)

    var icon: String? = nil
    var iconColor: Color = .white
    var borderColor: Color = .white.opacity(0.15)

    private var holeSize: CGFloat { 130 * size / 200 }
    private var holeOffY: CGFloat { topCircleOffsetY * size / 200 }
    private var iconSize: CGFloat { size * 32 / 280 }

    var body: some View {
        ZStack {
            PunchedBigCircle(holeSize: holeSize, holeOffsetY: holeOffY)
                .fill(color, style: FillStyle(eoFill: true))
                .frame(width: size, height: size)

            if let icon {
                Circle()
                    .strokeBorder(borderColor, lineWidth: size * 1.5 / 280)
                    .frame(width: holeSize - 4, height: holeSize - 4)
                    .offset(y: holeOffY / 2)

                // 글로우 레이어
                Image(systemName: icon)
                    .font(.system(size: iconSize * 1.3, weight: .medium))
                    .foregroundStyle(iconColor.opacity(0.3))
                    .blur(radius: iconSize * 0.4)
                    .offset(y: holeOffY / 2)

                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(iconColor)
                    .offset(y: holeOffY / 2)
            }
        }
        .frame(width: size, height: size)
    }
}
